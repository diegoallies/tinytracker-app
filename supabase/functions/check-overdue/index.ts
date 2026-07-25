// Supabase Edge Function: find babies whose feed or nap is due/overdue and push
// every caregiver who asked to be told.
//
// Replaces the on-device scheduling for feeds and sleeps. The old approach could
// only see what one phone knew — if the nanny logged a feed and the parent's app
// hadn't refreshed, the parent's reminder fired off stale data. This reads the
// database, so all caregivers get the same alert whether or not their app is open.
//
// Deploy:  supabase functions deploy check-overdue --no-verify-jwt
// Schedule: see supabase/2026-07-25_cron_check_overdue.sql (pg_cron, every 15 min)
//
// --no-verify-jwt matters: pg_cron calls this with the service-role key, not a
// user JWT, so the built-in verifier has to be off. The function itself checks
// the shared secret below.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { accessToken, sendPush, serviceAccount } from '../_shared/fcm.ts';

// How long after "due" we escalate. Matches the old local-notification grace
// period so timing doesn't change for existing users.
const OVERDUE_GRACE_MINUTES = 45;

// Age-based feeding guidelines, ported from lib/services/feeding_guidelines.dart.
// Must stay in sync with that file — if you change one, change both.
const MIN_INTERVAL_HOURS = 0.75;
const DAYS_PER_MONTH = 30.4375;
const BRACKETS: Array<{ minMonths: number; targetMl: number; hours: number }> = [
  { minMonths: 0, targetMl: 90, hours: 3 },
  { minMonths: 1, targetMl: 120, hours: 3 },
  { minMonths: 2, targetMl: 150, hours: 3 },
  { minMonths: 3, targetMl: 180, hours: 3 },
  { minMonths: 5, targetMl: 210, hours: 4 },
  { minMonths: 7, targetMl: 240, hours: 4 },
  { minMonths: 12, targetMl: 240, hours: 5 },
];

function feedIntervalMinutes(
  ageDays: number,
  lastAmountMl: number | null,
  configuredMinutes: number,
): number {
  // No recorded volume (breastfed, or just not entered) → the user's own setting.
  if (lastAmountMl == null || lastAmountMl <= 0) return configuredMinutes;
  const months = ageDays / DAYS_PER_MONTH;
  let bracket = BRACKETS[0];
  for (const b of BRACKETS) if (months >= b.minMonths) bracket = b;
  const scaled = (lastAmountMl / bracket.targetMl) * bracket.hours;
  const clamped = Math.min(Math.max(scaled, MIN_INTERVAL_HOURS), bracket.hours);
  return Math.round(clamped * 60);
}

function ageDaysFrom(dob: string | null): number {
  if (!dob) return 0;
  const ms = Date.now() - new Date(dob).getTime();
  return Math.max(0, Math.floor(ms / 86_400_000));
}

interface Alert {
  babyId: string;
  userId: string;
  type: string;
  anchorAt: string;
  title: string;
  body: string;
}

function hoursMinutes(since: Date): string {
  const mins = Math.floor((Date.now() - since.getTime()) / 60_000);
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

Deno.serve(async (req) => {
  // Called by pg_cron, not by users. A shared secret keeps it from being an open
  // endpoint that anyone can use to spam pushes.
  const expected = Deno.env.get('CRON_SECRET');
  if (expected && req.headers.get('x-cron-secret') !== expected) {
    return new Response(JSON.stringify({ error: 'forbidden' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Only users who actually want these alerts.
    const { data: prefs, error: prefsError } = await admin
      .from('notification_prefs')
      .select(
        'user_id, feeding_enabled, feeding_interval_minutes, sleep_enabled, sleep_window_minutes',
      )
      .or('feeding_enabled.eq.true,sleep_enabled.eq.true');
    // Surface query failures rather than swallowing them. Without this a missing
    // table or a broken policy reads as "nobody opted in" — a silently dead cron
    // job that looks healthy.
    if (prefsError) {
      console.error('notification_prefs query failed', prefsError);
      return json({ error: `notification_prefs: ${prefsError.message}` }, 500);
    }
    if (!prefs?.length) return json({ checked: 0, sent: 0, reason: 'no opted-in users' });

    const prefByUser = new Map(prefs.map((p) => [p.user_id, p]));

    // Which babies those users can see.
    const { data: shares, error: sharesError } = await admin
      .from('baby_shares')
      .select('baby_id, user_id')
      .in('user_id', [...prefByUser.keys()]);
    if (sharesError) {
      console.error('baby_shares query failed', sharesError);
      return json({ error: `baby_shares: ${sharesError.message}` }, 500);
    }
    if (!shares?.length) return json({ checked: 0, sent: 0, reason: 'no shared babies' });

    const usersByBaby = new Map<string, string[]>();
    for (const s of shares) {
      usersByBaby.set(s.baby_id, [...(usersByBaby.get(s.baby_id) ?? []), s.user_id]);
    }

    const { data: babies } = await admin
      .from('babies')
      .select('id, name, date_of_birth')
      .in('id', [...usersByBaby.keys()]);

    const now = Date.now();
    const alerts: Alert[] = [];

    for (const baby of babies ?? []) {
      const userIds = usersByBaby.get(baby.id) ?? [];
      const ageDays = ageDaysFrom(baby.date_of_birth);

      // ── Feeding ──────────────────────────────────────────────────────────
      const { data: feeds } = await admin
        .from('feedings')
        .select('logged_at, amount_ml')
        .eq('baby_id', baby.id)
        .is('deleted_at', null)
        .order('logged_at', { ascending: false })
        .limit(1);
      const lastFeed = feeds?.[0];

      if (lastFeed) {
        const fedAt = new Date(lastFeed.logged_at);
        for (const userId of userIds) {
          const p = prefByUser.get(userId)!;
          if (!p.feeding_enabled) continue;
          const interval = feedIntervalMinutes(
            ageDays,
            lastFeed.amount_ml,
            p.feeding_interval_minutes,
          );
          const dueAt = fedAt.getTime() + interval * 60_000;
          const overdueAt = dueAt + OVERDUE_GRACE_MINUTES * 60_000;
          const who = baby.name ? `${baby.name}` : 'Baby';

          if (now >= overdueAt) {
            alerts.push({
              babyId: baby.id,
              userId,
              type: 'feed_overdue',
              anchorAt: lastFeed.logged_at,
              title: 'Feed overdue',
              body: `${who} hasn't been fed in ${hoursMinutes(fedAt)}.`,
            });
          } else if (now >= dueAt) {
            alerts.push({
              babyId: baby.id,
              userId,
              type: 'feed_due',
              anchorAt: lastFeed.logged_at,
              title: 'Time for a feed',
              body: `${who} was last fed ${hoursMinutes(fedAt)} ago.`,
            });
          }
        }
      }

      // ── Sleep ────────────────────────────────────────────────────────────
      // Skip entirely if the baby is asleep right now — no point telling anyone
      // a nap is due mid-nap.
      const { data: active } = await admin
        .from('sleeps')
        .select('id')
        .eq('baby_id', baby.id)
        .is('end_time', null)
        .is('deleted_at', null)
        .limit(1);
      if (active?.length) continue;

      const { data: sleeps } = await admin
        .from('sleeps')
        .select('end_time')
        .eq('baby_id', baby.id)
        .is('deleted_at', null)
        .not('end_time', 'is', null)
        .order('end_time', { ascending: false })
        .limit(1);
      const lastWake = sleeps?.[0];
      if (!lastWake) continue;

      const wokeAt = new Date(lastWake.end_time);
      for (const userId of userIds) {
        const p = prefByUser.get(userId)!;
        if (!p.sleep_enabled) continue;
        const dueAt = wokeAt.getTime() + p.sleep_window_minutes * 60_000;
        const overdueAt = dueAt + OVERDUE_GRACE_MINUTES * 60_000;
        const who = baby.name ? `${baby.name}` : 'Baby';

        if (now >= overdueAt) {
          alerts.push({
            babyId: baby.id,
            userId,
            type: 'sleep_overdue',
            anchorAt: lastWake.end_time,
            title: 'Overtired',
            body: `${who} has been awake ${hoursMinutes(wokeAt)} — past the usual wake window.`,
          });
        } else if (now >= dueAt) {
          alerts.push({
            babyId: baby.id,
            userId,
            type: 'sleep_due',
            anchorAt: lastWake.end_time,
            title: 'Nap time',
            body: `${who} has been awake ${hoursMinutes(wokeAt)}.`,
          });
        }
      }
    }

    if (!alerts.length) return json({ checked: babies?.length ?? 0, sent: 0 });

    // Drop anything already sent for this exact event.
    const { data: already } = await admin
      .from('push_alerts_sent')
      .select('baby_id, user_id, alert_type, anchor_at')
      .in('baby_id', [...new Set(alerts.map((a) => a.babyId))]);
    const seen = new Set(
      (already ?? []).map(
        (r) =>
          `${r.baby_id}|${r.user_id}|${r.alert_type}|${new Date(r.anchor_at).getTime()}`,
      ),
    );
    const fresh = alerts.filter(
      (a) =>
        !seen.has(
          `${a.babyId}|${a.userId}|${a.type}|${new Date(a.anchorAt).getTime()}`,
        ),
    );
    if (!fresh.length) return json({ checked: babies?.length ?? 0, sent: 0, reason: 'all deduped' });

    // Tokens for the recipients.
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('user_id, token')
      .in('user_id', [...new Set(fresh.map((a) => a.userId))]);
    const tokensByUser = new Map<string, string[]>();
    for (const t of tokens ?? []) {
      tokensByUser.set(t.user_id, [...(tokensByUser.get(t.user_id) ?? []), t.token]);
    }

    const sa = serviceAccount();
    const bearer = await accessToken(sa);

    let sent = 0;
    const stale: string[] = [];
    const ledger: Array<Record<string, string>> = [];

    for (const a of fresh) {
      const userTokens = tokensByUser.get(a.userId) ?? [];
      if (!userTokens.length) continue;
      let delivered = false;
      for (const token of userTokens) {
        const result = await sendPush({
          bearer,
          projectId: sa.project_id,
          token,
          title: a.title,
          body: a.body,
          data: { type: a.type, baby_id: a.babyId },
        });
        if (result === 'sent') {
          sent++;
          delivered = true;
        } else if (result === 'stale') {
          stale.push(token);
        }
      }
      // Only record it if something actually went out, so a transient FCM error
      // doesn't permanently suppress the alert.
      if (delivered) {
        ledger.push({
          baby_id: a.babyId,
          user_id: a.userId,
          alert_type: a.type,
          anchor_at: a.anchorAt,
        });
      }
    }

    if (ledger.length) {
      await admin.from('push_alerts_sent').upsert(ledger, {
        onConflict: 'baby_id,user_id,alert_type,anchor_at',
      });
    }
    if (stale.length) {
      await admin.from('device_tokens').delete().in('token', stale);
    }

    return json({
      checked: babies?.length ?? 0,
      candidates: alerts.length,
      fresh: fresh.length,
      sent,
      cleaned: stale.length,
    });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
