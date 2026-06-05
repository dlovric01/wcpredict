// Pure helpers for choosing exactly one device-token row per user when
// sending push notifications.
//
// ── Why this exists ─────────────────────────────────────────────────
// `device_tokens` has PK `(user_id, token)`. A single user accumulates
// rows over time through:
//   * App reinstall — a fresh FCM token is issued; the old row stays.
//   * Switching between debug/release builds — different bundle ids,
//     different tokens, no dedup.
//   * Token-refresh events fired by FCM — new token inserted, old not
//     deleted.
//   * Simulator + physical device under the same account.
//
// The naive send-to-every-row implementation in
// `notify_predict_reminders` therefore delivers N identical pushes to
// the same human. `pickOneTokenPerUser` collapses this to one push per
// user, preferring the freshest token by `updated_at`. The "primary"
// invariant we settle for: the token most recently touched by client
// registration is the most likely to be live.
//
// Stale token deletion (when FCM returns NOT_FOUND / UNREGISTERED) is
// handled separately in the function; that path actively removes
// rows we observe to be dead.

export interface DeviceTokenRow {
  user_id: string;
  token: string;
  platform: string;
  updated_at?: string | null;
}

/// Given a flat list of `device_tokens` rows (possibly N per user),
/// return exactly one row per user — the one with the most recent
/// `updated_at`. Ties broken by token string for determinism.
///
/// Rows with a null/missing `updated_at` are considered oldest (sort
/// to epoch), so a freshly-touched row always wins over an
/// untouched legacy row.
export function pickOneTokenPerUser<T extends DeviceTokenRow>(
  rows: ReadonlyArray<T>,
): T[] {
  const byUser = new Map<string, T>();
  for (const row of rows) {
    const cur = byUser.get(row.user_id);
    if (!cur || isMoreRecent(row, cur)) {
      byUser.set(row.user_id, row);
    }
  }
  return Array.from(byUser.values());
}

function tsMillis(row: DeviceTokenRow): number {
  if (!row.updated_at) return 0;
  const t = Date.parse(row.updated_at);
  return Number.isFinite(t) ? t : 0;
}

function isMoreRecent(a: DeviceTokenRow, b: DeviceTokenRow): boolean {
  const ta = tsMillis(a);
  const tb = tsMillis(b);
  if (ta !== tb) return ta > tb;
  // Deterministic tiebreaker — pick the lexicographically smaller
  // token so test assertions are stable across runs.
  return a.token < b.token;
}

/// Inspect an FCM HTTP v1 error response body and decide whether the
/// token is permanently dead (and must be purged) or merely
/// transiently failing (leave it; retry next cron).
///
/// Permanently dead tokens to delete: `UNREGISTERED`, `NOT_FOUND`,
/// `INVALID_ARGUMENT` (malformed token), `SENDER_ID_MISMATCH`.
/// Anything else (`INTERNAL`, `UNAVAILABLE`, `QUOTA_EXCEEDED`,
/// auth) is transient.
///
/// FCM v1 error shape:
///   { "error": { "code": 404, "message": "...",
///     "details": [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
///                   "errorCode": "UNREGISTERED" }] } }
export function isPermanentFcmError(
  httpStatus: number,
  body: unknown,
): boolean {
  if (httpStatus === 404) return true;
  if (httpStatus === 400) {
    const code = fcmErrorCode(body);
    return code === "INVALID_ARGUMENT" || code === "UNREGISTERED";
  }
  if (httpStatus === 403) {
    const code = fcmErrorCode(body);
    return code === "SENDER_ID_MISMATCH";
  }
  return false;
}

function fcmErrorCode(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const err = (body as { error?: { details?: unknown } }).error;
  if (!err || typeof err !== "object") return null;
  const details = (err as { details?: unknown }).details;
  if (!Array.isArray(details)) return null;
  for (const d of details) {
    if (d && typeof d === "object") {
      const code = (d as { errorCode?: unknown }).errorCode;
      if (typeof code === "string") return code;
    }
  }
  return null;
}
