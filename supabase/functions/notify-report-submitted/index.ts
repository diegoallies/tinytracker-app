// Supabase Edge Function: notify a baby's parents (share role = 'owner') that a
// weekly report was submitted. Sends via FCM HTTP v1, which reaches both iOS
// (Firebase forwards to APNs using the key uploaded in the console) and Android.
//
// Deploy:  supabase functions deploy notify-report-submitted
// Secrets (supabase secrets set ...):
//   FCM_SERVICE_ACCOUNT   the whole service-account JSON downloaded from
//                         Firebase Console > Project settings > Service accounts
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected by
// the platform — don't set those.
//
// Call from the app after a submit:
//   supabase.functions.invoke('notify-report-submitted',
//     { body: { baby_id, baby_name, actor_name } })

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

interface ServiceAccount {
  project_id: string;
  private_key: string;
  client_email: string;
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// Import the service account's PEM (PKCS#8 RSA) key for RS256 signing.
async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

// Exchange a self-signed service-account JWT for an OAuth2 access token.
// Unlike the old APNs path (where the JWT *was* the credential), FCM v1 needs
// this extra round trip to Google's token endpoint.
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })),
  );
  const claims = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: FCM_SCOPE,
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const signingInput = `${header}.${claims}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      await importKey(sa.private_key),
      new TextEncoder().encode(signingInput),
    ),
  );
  const assertion = `${signingInput}.${b64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  }
  return (await res.json()).access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });

  try {
    const { baby_id, baby_name, actor_name } = await req.json();
    if (!baby_id) return json({ error: 'baby_id required' }, 400);

    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Verify the caller is a member of this baby (uses their JWT).
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: {
        headers: { Authorization: req.headers.get('Authorization') ?? '' },
      },
    });
    const { data: caller } = await asUser.auth.getUser();
    if (!caller?.user) return json({ error: 'unauthorized' }, 401);

    // Service-role client to look up recipients + tokens (bypasses RLS).
    const admin = createClient(url, serviceKey);

    const { data: callerShare } = await admin
      .from('baby_shares')
      .select('id')
      .eq('baby_id', baby_id)
      .eq('user_id', caller.user.id)
      .maybeSingle();
    if (!callerShare) return json({ error: 'not a member of baby' }, 403);

    // Parents = owners of the baby, excluding whoever submitted.
    const { data: owners } = await admin
      .from('baby_shares')
      .select('user_id')
      .eq('baby_id', baby_id)
      .eq('role', 'owner');
    const recipientIds = (owners ?? [])
      .map((o) => o.user_id)
      .filter((id) => id !== caller.user.id);
    if (recipientIds.length === 0) {
      return json({ sent: 0, reason: 'no recipients' });
    }

    // Both platforms live in the same table now — FCM reaches iOS via APNs
    // itself, so we no longer filter by platform.
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token')
      .in('user_id', recipientIds);
    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, reason: 'no tokens' });
    }

    const sa: ServiceAccount = JSON.parse(
      Deno.env.get('FCM_SERVICE_ACCOUNT')!,
    );
    const bearer = await accessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const who = actor_name?.trim() ? actor_name.trim() : 'Your nanny';
    const forBaby = baby_name?.trim() ? ` for ${baby_name.trim()}` : '';
    const title = 'Weekly report submitted 📋';
    const body = `${who} submitted this week's report${forBaby}.`;

    let sent = 0;
    const stale: string[] = [];
    for (const { token } of tokens) {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${bearer}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            // Read by PushService._handleTap to deep-link the right screen.
            // FCM requires every data value to be a string.
            data: { type: 'weekly_report_submitted', baby_id: String(baby_id) },
            android: {
              priority: 'high',
              notification: { channel_id: 'remote_updates', sound: 'default' },
            },
            apns: {
              headers: { 'apns-priority': '10' },
              payload: { aps: { sound: 'default', badge: 1 } },
            },
          },
        }),
      });

      if (res.ok) {
        sent++;
        continue;
      }
      // FCM reports a dead token as 404 UNREGISTERED (app uninstalled or token
      // rotated) or 400 INVALID_ARGUMENT for a malformed one. Both mean stop
      // trying that token. Anything else is a transient/config error worth
      // logging rather than deleting over.
      const err = await res.text();
      if (
        res.status === 404 ||
        err.includes('UNREGISTERED') ||
        err.includes('INVALID_ARGUMENT')
      ) {
        stale.push(token);
      } else {
        console.error(`fcm send failed ${res.status}: ${err}`);
      }
    }

    if (stale.length) {
      await admin.from('device_tokens').delete().in('token', stale);
    }

    return json({ sent, cleaned: stale.length });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
