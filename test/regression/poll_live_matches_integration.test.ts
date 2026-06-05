// End-to-end integration check for the optimised poll_live_matches
// function against a live Supabase stack.
//
// We don't have an APISPORTS_KEY in the test env, so the live + FT
// fetches inside the function will both fail with non-OK responses.
// The function MUST still:
//
//   1. Return 200 with ok:true (or skipped:true when no active match).
//   2. Successfully execute the new wider SELECT that includes
//      score/period/minute columns (catches column-name drift).
//   3. Not write spurious rows to `matches` or `match_events`.
//
// Combined with the pure-helper tests in event_diff.test.ts and the
// scoring-engine regression block, this rounds out coverage of the
// optimisation without needing a mocked api-sports.io.

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import {
  adminClient,
  ANON_KEY,
  SUPABASE_URL,
  T,
} from "./helpers";

// Test fixture isolated in the 99_900+ range to avoid colliding with
// `insertTestFixtures` (which uses 99_000-99_500) or the regression
// suite's MATCH ids (100_000+).
const TEST_MATCH_ID = 100_900;
const TEST_TEAM_A = 99_900;
const TEST_TEAM_B = 99_901;

const admin = adminClient();

async function ensureTeam(id: number, code: string) {
  await admin.from("teams").upsert({ id, name: code, code, group_letter: "Z" });
}

async function cleanup() {
  await admin.from("match_events").delete().eq("match_id", TEST_MATCH_ID);
  await admin.from("matches").delete().eq("id", TEST_MATCH_ID);
  await admin.from("teams").delete().in("id", [TEST_TEAM_A, TEST_TEAM_B]);
}

async function callPollLive(): Promise<{ status: number; body: any }> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/poll_live_matches`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body };
}

beforeAll(async () => {
  await cleanup();
  await ensureTeam(TEST_TEAM_A, "ZZA");
  await ensureTeam(TEST_TEAM_B, "ZZB");
});

afterAll(async () => {
  await cleanup();
});

describe("poll_live_matches — wider SELECT (column-drift guard)", () => {
  test("returns 200 with no active matches in the DB", async () => {
    // No fixture inserted yet — function should early-return.
    const { status, body } = await callPollLive();
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.skipped).toBe(true);
    expect(body.reason).toBe("no_active_matches");
  });

  test("active match present + no APISPORTS_KEY → still 200, no writes", async () => {
    // Insert a 'live' match with kickoff in the past so the function's
    // activeMatches SELECT picks it up (and its widened column set
    // including score/period/minute must parse cleanly).
    const ins = await admin.from("matches").insert({
      id: TEST_MATCH_ID,
      team1_id: TEST_TEAM_A,
      team2_id: TEST_TEAM_B,
      kickoff_time: new Date(Date.now() - 30 * 60_000).toISOString(),
      round: "group",
      status: "live",
      score_ft_team1: 0,
      score_ft_team2: 0,
      current_minute: 25,
      current_minute_extra: null,
      current_period: "1H",
    });
    if (ins.error) throw new Error(`matches insert: ${ins.error.message}`);

    // Snapshot row before — used to assert no spurious bumps.
    const { data: before } = await admin
      .from("matches")
      .select("score_ft_team1, score_ft_team2, current_minute, current_period, updated_at")
      .eq("id", TEST_MATCH_ID)
      .single();

    const { status, body } = await callPollLive();
    expect(status).toBe(200);
    expect(body.ok).toBe(true);

    // Without a valid APISPORTS_KEY the live + FT fetches both fail,
    // so Phase A and Phase B should skip. The matches row must NOT
    // have been touched — diff-before-update means even a successful
    // fetch of identical data wouldn't write, and a failed fetch
    // certainly shouldn't.
    const { data: after } = await admin
      .from("matches")
      .select("score_ft_team1, score_ft_team2, current_minute, current_period, updated_at")
      .eq("id", TEST_MATCH_ID)
      .single();

    expect(after?.score_ft_team1).toBe(before?.score_ft_team1);
    expect(after?.score_ft_team2).toBe(before?.score_ft_team2);
    expect(after?.current_minute).toBe(before?.current_minute);
    expect(after?.current_period).toBe(before?.current_period);
    expect(after?.updated_at).toBe(before?.updated_at);

    expect(typeof body.live_updated === "number" || body.skipped).toBeTruthy();
  });
});
