// Shared FCM HTTP v1 sending. Used by notify-report-submitted and check-overdue
// so the OAuth dance and payload shape exist in exactly one place.
//
// Requires the FCM_SERVICE_ACCOUNT secret: the whole service-account JSON from
// Firebase Console → Project settings → Service accounts.

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

export interface ServiceAccount {
  project_id: string;
  private_key: string;
  client_email: string;
}

export function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT secret is not set');
  return JSON.parse(raw);
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

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

/// Exchange a self-signed service-account JWT for an OAuth2 access token.
/// Valid for an hour, so callers should fetch once and reuse across sends.
export async function accessToken(sa: ServiceAccount): Promise<string> {
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

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${signingInput}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  }
  return (await res.json()).access_token as string;
}

export type SendResult = 'sent' | 'stale' | 'error';

/// Send one notification. Returns 'stale' when FCM says the token is dead, so
/// the caller can prune it.
export async function sendPush(opts: {
  bearer: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${opts.projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${opts.bearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: opts.token,
          notification: { title: opts.title, body: opts.body },
          data: opts.data ?? {},
          android: {
            priority: 'high',
            notification: { channel_id: 'remote_updates', sound: 'default' },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default' } },
          },
        },
      }),
    },
  );

  if (res.ok) return 'sent';

  // 404 UNREGISTERED = app uninstalled or token rotated. INVALID_ARGUMENT =
  // malformed. Either way, stop trying that token.
  const err = await res.text();
  if (
    res.status === 404 ||
    err.includes('UNREGISTERED') ||
    err.includes('INVALID_ARGUMENT')
  ) {
    return 'stale';
  }
  console.error(`fcm send failed ${res.status}: ${err}`);
  return 'error';
}
