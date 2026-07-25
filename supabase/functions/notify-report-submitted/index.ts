// Supabase Edge Function: notify a baby's parents (share role = 'owner') that a
// weekly report was submitted. Sends a native APNs push (no Firebase).
//
// Deploy:  supabase functions deploy notify-report-submitted
// Secrets (supabase secrets set ...):
//   APNS_KEY        contents of the AuthKey_XXXX.p8 (the whole file, PEM)
//   APNS_KEY_ID     the 10-char key id
//   APNS_TEAM_ID    your Apple team id
//   APNS_BUNDLE_ID  the app bundle id (e.g. com.diego.tinytrack) - APNs topic
//   APNS_HOST       api.push.apple.com   (prod)  |  api.sandbox.push.apple.com (dev)
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
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

function b64url(bytes: Uint8Array): string {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Import the .p8 (PKCS#8 EC P-256) private key for ES256 signing.
async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

async function apnsJwt(): Promise<string> {
  const keyId = Deno.env.get('APNS_KEY_ID')!;
  const teamId = Deno.env.get('APNS_TEAM_ID')!;
  const key = await importP8(Deno.env.get('APNS_KEY')!);
  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })),
  );
  const claims = b64url(
    new TextEncoder().encode(
      JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }),
    ),
  );
  const signingInput = `${header}.${claims}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${b64url(sig)}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { baby_id, baby_name, actor_name } = await req.json();
    if (!baby_id) {
      return new Response(JSON.stringify({ error: 'baby_id required' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Verify the caller is a member of this baby (uses their JWT).
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: caller } = await asUser.auth.getUser();
    if (!caller?.user) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    // Service-role client to look up recipients + tokens (bypasses RLS).
    const admin = createClient(url, serviceKey);

    const { data: callerShare } = await admin
      .from('baby_shares')
      .select('id')
      .eq('baby_id', baby_id)
      .eq('user_id', caller.user.id)
      .maybeSingle();
    if (!callerShare) {
      return new Response(JSON.stringify({ error: 'not a member of baby' }), {
        status: 403,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

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
      return new Response(JSON.stringify({ sent: 0, reason: 'no recipients' }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token')
      .in('user_id', recipientIds)
      .eq('platform', 'ios');
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no tokens' }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const jwt = await apnsJwt();
    const host = Deno.env.get('APNS_HOST') ?? 'api.push.apple.com';
    const topic = Deno.env.get('APNS_BUNDLE_ID')!;
    const who = actor_name?.trim() ? actor_name.trim() : 'Your nanny';
    const forBaby = baby_name?.trim() ? ` for ${baby_name.trim()}` : '';
    const payload = JSON.stringify({
      aps: {
        alert: {
          title: 'Weekly report submitted 📋',
          body: `${who} submitted this week's report${forBaby}.`,
        },
        sound: 'default',
        badge: 1,
      },
      type: 'weekly_report_submitted',
      baby_id,
    });

    let sent = 0;
    const stale: string[] = [];
    for (const { token } of tokens) {
      const res = await fetch(`https://${host}/3/device/${token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${jwt}`,
          'apns-topic': topic,
          'apns-push-type': 'alert',
          'apns-priority': '10',
        },
        body: payload,
      });
      if (res.ok) sent++;
      else if (res.status === 410) stale.push(token); // token no longer valid
    }

    // Clean up dead tokens.
    if (stale.length) {
      await admin.from('device_tokens').delete().in('token', stale);
    }

    return new Response(JSON.stringify({ sent, cleaned: stale.length }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
