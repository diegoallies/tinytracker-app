// Supabase Edge Function: notify a baby's parents (share role = 'owner') that a
// weekly report was submitted. Sends via FCM HTTP v1, which reaches both iOS
// (Firebase forwards to APNs using the key uploaded in the console) and Android.
//
// The OAuth + send logic lives in ../_shared/fcm.ts, shared with check-overdue.
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
import { accessToken, sendPush, serviceAccount } from '../_shared/fcm.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

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

    // Both platforms live in the same table — FCM reaches iOS via APNs itself,
    // so we no longer filter by platform.
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token')
      .in('user_id', recipientIds);
    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, reason: 'no tokens' });
    }

    const sa = serviceAccount();
    const bearer = await accessToken(sa);

    const who = actor_name?.trim() ? actor_name.trim() : 'Your nanny';
    const forBaby = baby_name?.trim() ? ` for ${baby_name.trim()}` : '';

    let sent = 0;
    const stale: string[] = [];
    for (const { token } of tokens) {
      const result = await sendPush({
        bearer,
        projectId: sa.project_id,
        token,
        title: 'Weekly report submitted',
        body: `${who} submitted this week's report${forBaby}.`,
        data: { type: 'weekly_report_submitted', baby_id: String(baby_id) },
      });
      if (result === 'sent') sent++;
      else if (result === 'stale') stale.push(token);
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
