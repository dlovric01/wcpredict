// notify_predict_reminders — every-minute cron worker.
//
// For each match kicking off in [now+29min, now+31min], finds every
// user who:
//   * has a device_token registered, AND
//   * has NOT yet predicted this match, AND
//   * has NOT already been notified for it.
//
// Sends one FCM HTTP v1 push per device token and logs
// (user_id, match_id) into prediction_reminders_sent so the next
// cron tick won't re-send.
//
// The function is a no-op when FCM_SERVICE_ACCOUNT_JSON is missing
// (e.g. before the credentials are wired up — see the plan's
// "Manual blockers" section). It logs and returns 200 so cron
// doesn't error-loop.

import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id?: string;
};

type DeviceTokenRow = { user_id: string; token: string; platform: string };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function loadServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.client_email || !parsed.private_key) return null;
    return parsed;
  } catch (_err) {
    return null;
  }
}

function projectId(svc: ServiceAccount): string | null {
  return Deno.env.get('FCM_PROJECT_ID') ?? svc.project_id ?? null;
}

// ── OAuth2 access-token minting (Google service account JWT) ──────────────────
//
// FCM HTTP v1 requires a Bearer access token. We mint one by signing a
// JWT with the service account's private key and exchanging it at
// Google's token endpoint. The token lives 1 h; we cache per cold start.

let cachedToken: { token: string; expiresAt: number } | null = null;

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : input;
  let str = '';
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const bin = atob(cleaned);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function mintAccessToken(svc: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.token;

  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: svc.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claim))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(svc.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(new Uint8Array(sig))}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  if (!tokenRes.ok) {
    const txt = await tokenRes.text();
    throw new Error(`token mint failed: ${tokenRes.status} ${txt}`);
  }
  const { access_token, expires_in } = await tokenRes.json();
  cachedToken = {
    token: access_token,
    expiresAt: now + Number(expires_in ?? 3600),
  };
  return access_token;
}

// ── Edge entry point ──────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const svc = loadServiceAccount();
    const pid = svc ? projectId(svc) : null;
    if (!svc || !pid) {
      // No credentials wired up yet — log and 200 so cron doesn't error-loop.
      console.warn(
        'notify_predict_reminders: FCM_SERVICE_ACCOUNT_JSON / FCM_PROJECT_ID missing; skipping.',
      );
      return jsonResponse({ ok: true, skipped: 'fcm_not_configured' });
    }

    const now = Date.now();
    // Window [now+29min, now+31min] — wide enough to absorb cron drift,
    // narrow enough that we don't pre-send for the cron tick AFTER this one
    // (which would also catch [now+28min, now+30min] on the next tick).
    const windowStart = new Date(now + 29 * 60 * 1000).toISOString();
    const windowEnd = new Date(now + 31 * 60 * 1000).toISOString();

    const { data: matches, error: matchErr } = await supabaseAdmin
      .from('matches')
      .select('id, kickoff_time, team1:teams!team1_id(code), team2:teams!team2_id(code)')
      .eq('status', 'scheduled')
      .gte('kickoff_time', windowStart)
      .lte('kickoff_time', windowEnd);
    if (matchErr) throw new Error(matchErr.message);
    if (!matches || matches.length === 0) {
      return jsonResponse({ ok: true, matches: 0 });
    }

    let accessToken: string;
    try {
      accessToken = await mintAccessToken(svc);
    } catch (err) {
      console.error(err);
      return jsonResponse({ ok: false, error: 'token_mint_failed' }, 500);
    }

    let totalSends = 0;
    let totalSkipped = 0;

    for (const m of matches as Array<{
      id: number;
      kickoff_time: string;
      team1: { code: string | null } | null;
      team2: { code: string | null } | null;
    }>) {
      // Recipients: anyone with a device token, no prediction yet,
      // not yet reminded.
      const { data: predictedRows } = await supabaseAdmin
        .from('predictions')
        .select('user_id')
        .eq('match_id', m.id);
      const predictedSet = new Set(
        (predictedRows ?? []).map((r: { user_id: string }) => r.user_id),
      );

      const { data: alreadySentRows } = await supabaseAdmin
        .from('prediction_reminders_sent')
        .select('user_id')
        .eq('match_id', m.id);
      const alreadySent = new Set(
        (alreadySentRows ?? []).map((r: { user_id: string }) => r.user_id),
      );

      const { data: tokens } = await supabaseAdmin
        .from('device_tokens')
        .select('user_id, token, platform');

      const candidates = (tokens ?? []) as DeviceTokenRow[];
      const targets = candidates.filter(
        (t) => !predictedSet.has(t.user_id) && !alreadySent.has(t.user_id),
      );

      if (targets.length === 0) {
        totalSkipped++;
        continue;
      }

      const recipientUserIds = new Set<string>();
      const title = `Predict ${m.team1?.code ?? 'TBD'} vs ${m.team2?.code ?? 'TBD'}`;
      const body = 'Kickoff in 30 minutes — tap to submit your pick';
      const deepLink = `/matches/${m.id}`;

      // Fire-and-forget per token. We log a "sent" record per recipient
      // regardless of HTTP outcome to avoid retry storms — one missed
      // push is acceptable, repeated pushes are not.
      await Promise.allSettled(
        targets.map(async (t) => {
          const payload = {
            message: {
              token: t.token,
              notification: { title, body },
              data: { match_id: String(m.id), deep_link: deepLink },
              apns: {
                payload: { aps: { sound: 'default' } },
              },
              android: { priority: 'HIGH' },
            },
          };
          try {
            const res = await fetch(
              `https://fcm.googleapis.com/v1/projects/${pid}/messages:send`,
              {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload),
              },
            );
            if (!res.ok) {
              const txt = await res.text();
              console.warn(
                `FCM send failed for ${t.token.slice(0, 10)}…: ${res.status} ${txt}`,
              );
            } else {
              totalSends++;
            }
          } catch (err) {
            console.warn('FCM send threw:', err);
          }
          recipientUserIds.add(t.user_id);
        }),
      );

      if (recipientUserIds.size > 0) {
        const rows = Array.from(recipientUserIds).map((uid) => ({
          user_id: uid,
          match_id: m.id,
        }));
        const { error: logErr } = await supabaseAdmin
          .from('prediction_reminders_sent')
          .upsert(rows, { onConflict: 'user_id,match_id' });
        if (logErr) {
          console.error('reminder log upsert failed:', logErr.message);
        }
      }
    }

    return jsonResponse({
      ok: true,
      matches: matches.length,
      sends: totalSends,
      skipped_matches: totalSkipped,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('notify_predict_reminders error:', message);
    return jsonResponse({ ok: false, error: message }, 500);
  }
});
