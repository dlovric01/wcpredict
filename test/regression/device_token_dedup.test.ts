// Pure-helper tests for the per-user device-token deduplication that
// stops `notify_predict_reminders` from delivering N identical pushes
// to the same human (where N = stale rows accumulated through
// reinstalls / token rotation / debug-vs-release builds).

import { describe, test, expect } from "bun:test";
import {
  type DeviceTokenRow,
  isPermanentFcmError,
  pickOneTokenPerUser,
} from "../../supabase/functions/_shared/device_token_dedup.ts";

function row(
  user_id: string,
  token: string,
  updated_at: string | null = null,
  platform = "ios",
): DeviceTokenRow {
  return { user_id, token, platform, updated_at };
}

describe("pickOneTokenPerUser — dedup invariants", () => {
  test("empty input → empty output", () => {
    expect(pickOneTokenPerUser([])).toEqual([]);
  });

  test("single user, single row → unchanged", () => {
    const r = row("u1", "tok-A");
    expect(pickOneTokenPerUser([r])).toEqual([r]);
  });

  test("single user, three rows → exactly one row out (THE bug we are fixing)", () => {
    const rows = [
      row("u1", "tok-A"),
      row("u1", "tok-B"),
      row("u1", "tok-C"),
    ];
    const picked = pickOneTokenPerUser(rows);
    expect(picked).toHaveLength(1);
    expect(picked[0].user_id).toBe("u1");
  });

  test("two users, three rows each → exactly two rows out, one per user", () => {
    const rows = [
      row("u1", "tok-A1"), row("u1", "tok-A2"), row("u1", "tok-A3"),
      row("u2", "tok-B1"), row("u2", "tok-B2"), row("u2", "tok-B3"),
    ];
    const picked = pickOneTokenPerUser(rows);
    expect(picked).toHaveLength(2);
    const users = picked.map((r) => r.user_id).sort();
    expect(users).toEqual(["u1", "u2"]);
  });
});

describe("pickOneTokenPerUser — recency selection", () => {
  test("newest updated_at wins", () => {
    const old   = row("u1", "tok-old",   "2024-01-01T00:00:00Z");
    const newer = row("u1", "tok-new",   "2026-06-01T00:00:00Z");
    expect(pickOneTokenPerUser([old, newer])[0].token).toBe("tok-new");
    // Order-independent.
    expect(pickOneTokenPerUser([newer, old])[0].token).toBe("tok-new");
  });

  test("null updated_at is treated as oldest (legacy row never wins over touched row)", () => {
    const legacy = row("u1", "tok-legacy", null);
    const recent = row("u1", "tok-recent", "2026-01-01T00:00:00Z");
    expect(pickOneTokenPerUser([legacy, recent])[0].token).toBe("tok-recent");
    expect(pickOneTokenPerUser([recent, legacy])[0].token).toBe("tok-recent");
  });

  test("identical updated_at → deterministic tiebreaker (lexicographic token)", () => {
    const a = row("u1", "tok-a", "2026-06-01T00:00:00Z");
    const z = row("u1", "tok-z", "2026-06-01T00:00:00Z");
    expect(pickOneTokenPerUser([a, z])[0].token).toBe("tok-a");
    expect(pickOneTokenPerUser([z, a])[0].token).toBe("tok-a");
  });

  test("malformed updated_at parses to oldest (defensive)", () => {
    const garbage = row("u1", "tok-garbage", "not-a-date");
    const valid   = row("u1", "tok-valid",   "2026-06-01T00:00:00Z");
    expect(pickOneTokenPerUser([garbage, valid])[0].token).toBe("tok-valid");
  });
});

describe("pickOneTokenPerUser — realistic mixed input", () => {
  test("user with phone + tablet + stale reinstall → newest of the three", () => {
    const stale  = row("u1", "tok-old-install", "2025-06-01T12:00:00Z");
    const tablet = row("u1", "tok-tablet",      "2026-06-03T08:00:00Z");
    const phone  = row("u1", "tok-phone",       "2026-06-04T14:30:00Z"); // newest
    expect(pickOneTokenPerUser([stale, tablet, phone])[0].token).toBe("tok-phone");
  });

  test("multiple users, varied row counts, varied platforms", () => {
    const rows = [
      row("u1", "ios-1",  "2026-06-04T10:00:00Z", "ios"),
      row("u1", "ios-2",  "2026-06-04T12:00:00Z", "ios"),
      row("u2", "and-1",  "2026-06-04T10:00:00Z", "android"),
      row("u3", "ios-3",  null,                   "ios"),
    ];
    const picked = pickOneTokenPerUser(rows);
    expect(picked).toHaveLength(3);
    const byUser = new Map(picked.map((r) => [r.user_id, r.token]));
    expect(byUser.get("u1")).toBe("ios-2");  // newest of u1
    expect(byUser.get("u2")).toBe("and-1");
    expect(byUser.get("u3")).toBe("ios-3");
  });
});

describe("isPermanentFcmError — token-purge classifier", () => {
  test("HTTP 404 → permanent (token unknown to FCM)", () => {
    expect(isPermanentFcmError(404, null)).toBe(true);
  });

  test("HTTP 400 with UNREGISTERED in details → permanent", () => {
    const body = {
      error: {
        code: 400, message: "...",
        details: [
          { "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            errorCode: "UNREGISTERED" },
        ],
      },
    };
    expect(isPermanentFcmError(400, body)).toBe(true);
  });

  test("HTTP 400 with INVALID_ARGUMENT → permanent (malformed token)", () => {
    const body = {
      error: { details: [{ errorCode: "INVALID_ARGUMENT" }] },
    };
    expect(isPermanentFcmError(400, body)).toBe(true);
  });

  test("HTTP 400 with no FCM errorCode → transient (don't purge)", () => {
    expect(isPermanentFcmError(400, { error: { details: [] } })).toBe(false);
  });

  test("HTTP 403 SENDER_ID_MISMATCH → permanent", () => {
    const body = { error: { details: [{ errorCode: "SENDER_ID_MISMATCH" }] } };
    expect(isPermanentFcmError(403, body)).toBe(true);
  });

  test("HTTP 500 INTERNAL → transient (cron retries next tick)", () => {
    const body = { error: { details: [{ errorCode: "INTERNAL" }] } };
    expect(isPermanentFcmError(500, body)).toBe(false);
  });

  test("HTTP 503 UNAVAILABLE → transient", () => {
    expect(isPermanentFcmError(503, null)).toBe(false);
  });

  test("HTTP 429 QUOTA_EXCEEDED → transient", () => {
    expect(isPermanentFcmError(429, null)).toBe(false);
  });

  test("HTTP 401 auth failure → transient (token mint expired)", () => {
    expect(isPermanentFcmError(401, null)).toBe(false);
  });

  test("malformed body never crashes; conservative-transient", () => {
    expect(isPermanentFcmError(400, "not-an-object")).toBe(false);
    expect(isPermanentFcmError(400, undefined)).toBe(false);
    expect(isPermanentFcmError(400, { error: "no-details" })).toBe(false);
  });
});
