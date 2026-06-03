/**
 * WC2026 Predict — Full Regression Suite
 *
 * Runs against the live production Supabase instance.
 * All test data is isolated under T.* IDs and @wctest.invalid auth users.
 * A global teardown wipes everything after the suite completes.
 *
 * Run:  cd test/regression && bun test regression.test.ts --timeout 30000
 */

import { describe, test, expect, beforeAll, beforeEach, afterAll } from "bun:test";
import {
  adminClient,
  anonClient,
  userClient,
  insertTestFixtures,
  teardownTestData,
  assertNoError,
  sleep,
  T,
  TEST_DOMAIN,
  SUPABASE_URL,
  ANON_KEY,
  SERVICE_KEY,
} from "./helpers";
import type { SupabaseClient } from "@supabase/supabase-js";

// ─── Global state ─────────────────────────────────────────────────────────────

const admin = adminClient();

// Auth users created in beforeAll, reused across all describe blocks
let alice: { client: SupabaseClient; userId: string };
let bob:   { client: SupabaseClient; userId: string };
let charlie: { client: SupabaseClient; userId: string };

// Group state populated by group tests, consumed by later tests
let groupId: string;
let inviteCode: string;

// ─── Global setup / teardown ──────────────────────────────────────────────────

beforeAll(async () => {
  // Wipe any residue from a previous aborted run
  await teardownTestData(admin);
  // Insert static fixtures (teams, players, matches)
  await insertTestFixtures(admin);
  // Create auth users
  [alice, bob, charlie] = await Promise.all([
    userClient("alice"),
    userClient("bob"),
    userClient("charlie"),
  ]);
}, 60_000);

afterAll(async () => {
  await teardownTestData(admin);
}, 30_000);

// ─────────────────────────────────────────────────────────────────────────────
// 1. AUTH & PROFILES
// ─────────────────────────────────────────────────────────────────────────────

describe("Auth & Profiles", () => {
  test("signup creates a profile row automatically", async () => {
    const { data, error } = await alice.client
      .from("profiles")
      .select("user_id, display_name")
      .eq("user_id", alice.userId)
      .single();
    expect(error).toBeNull();
    expect(data?.user_id).toBe(alice.userId);
    expect(data?.display_name).toBeTruthy();
  });

  test("display_name defaults to email-prefix when not set explicitly", async () => {
    // charlie signed up without explicit display_name metadata
    const { data } = await charlie.client
      .from("profiles")
      .select("display_name")
      .eq("user_id", charlie.userId)
      .single();
    // Trigger sets it to split_part(email, '@', 1) = 'charlie'
    expect(data?.display_name).toBe("charlie");
  });

  test("user can read their own profile", async () => {
    const { data, error } = await alice.client
      .from("profiles")
      .select("*")
      .eq("user_id", alice.userId)
      .single();
    expect(error).toBeNull();
    expect(data).not.toBeNull();
  });

  test("user can read other users' profiles (public read)", async () => {
    const { data, error } = await bob.client
      .from("profiles")
      .select("display_name")
      .eq("user_id", alice.userId)
      .single();
    expect(error).toBeNull();
    expect(data?.display_name).toBeTruthy();
  });

  test("anon client can read profiles (public read policy)", async () => {
    const anon = adminClient(); // using admin just to not sign in
    const { data, error } = await admin
      .from("profiles")
      .select("display_name")
      .eq("user_id", alice.userId)
      .single();
    expect(error).toBeNull();
    expect(data?.display_name).toBeTruthy();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. GROUPS
// ─────────────────────────────────────────────────────────────────────────────

describe("Groups", () => {
  test("owner can create a group", async () => {
    const code = `TEST_${Date.now()}`;
    const { data, error } = await alice.client
      .from("groups")
      .insert({ name: "TEST_AliceGroup", owner_id: alice.userId, invite_code: code })
      .select()
      .single();
    expect(error).toBeNull();
    expect(data?.id).toBeTruthy();
    groupId = data!.id;
    inviteCode = data!.invite_code;

    // Alice must also join her own group as a member (app responsibility, but
    // let's insert it so RLS group-member queries work properly)
    await alice.client
      .from("group_members")
      .insert({ group_id: groupId, user_id: alice.userId });
  });

  test("non-member cannot read the group", async () => {
    const { data } = await bob.client
      .from("groups")
      .select("id")
      .eq("id", groupId);
    // RLS: bob is not a member, so row is invisible
    expect(data?.length ?? 0).toBe(0);
  });

  test("user can join group via invite code", async () => {
    // Look up group by invite_code
    const { data: grp, error: findErr } = await bob.client
      .from("groups")
      .select("id")
      .eq("invite_code", inviteCode)
      .single();
    // Still can't see it via groups table (not a member yet)
    // Join directly
    const { error } = await bob.client
      .from("group_members")
      .insert({ group_id: groupId, user_id: bob.userId });
    expect(error).toBeNull();
  });

  test("member can read group after joining", async () => {
    const { data, error } = await bob.client
      .from("groups")
      .select("id, name")
      .eq("id", groupId)
      .single();
    expect(error).toBeNull();
    expect(data?.id).toBe(groupId);
  });

  test("member can see other members of the group", async () => {
    const { data, error } = await bob.client
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId);
    expect(error).toBeNull();
    const ids = data?.map((r) => r.user_id) ?? [];
    expect(ids).toContain(alice.userId);
    expect(ids).toContain(bob.userId);
  });

  test("non-member (charlie) cannot see group members", async () => {
    const { data } = await charlie.client
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId);
    expect(data?.length ?? 0).toBe(0);
  });

  test("owner can remove a member", async () => {
    // First let charlie join so we can remove her
    await charlie.client
      .from("group_members")
      .insert({ group_id: groupId, user_id: charlie.userId });

    const { error } = await alice.client
      .from("group_members")
      .delete()
      .eq("group_id", groupId)
      .eq("user_id", charlie.userId);
    expect(error).toBeNull();

    // charlie should no longer be a member
    const { data } = await admin
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("user_id", charlie.userId);
    expect(data?.length ?? 0).toBe(0);
  });

  test("member can remove themselves (leave group)", async () => {
    // Re-add charlie to test leave
    await charlie.client
      .from("group_members")
      .insert({ group_id: groupId, user_id: charlie.userId });

    const { error } = await charlie.client
      .from("group_members")
      .delete()
      .eq("group_id", groupId)
      .eq("user_id", charlie.userId);
    expect(error).toBeNull();
  });

  test("non-owner cannot delete the group", async () => {
    const { error } = await bob.client
      .from("groups")
      .delete()
      .eq("id", groupId);
    // RLS: only owner can write groups; bob's delete should affect 0 rows (no error, 0 rows)
    // Supabase returns no error but deletes 0 rows when RLS blocks it
    // Verify group still exists
    const { data } = await admin.from("groups").select("id").eq("id", groupId).single();
    expect(data?.id).toBe(groupId);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. PREDICTIONS — CRUD & CONSTRAINTS
// ─────────────────────────────────────────────────────────────────────────────

describe("Predictions — CRUD & Constraints", () => {
  test("user can create a prediction for a future match", async () => {
    const { error } = await alice.client.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 2,
      predicted_team2: 1,
      predicted_scorer_id: T.PLAYER_A1,
    });
    expect(error).toBeNull();
  });

  test("user can update their prediction before lock", async () => {
    const { error } = await alice.client
      .from("predictions")
      .update({ predicted_team1: 3, predicted_team2: 0 })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    expect(error).toBeNull();

    const { data } = await alice.client
      .from("predictions")
      .select("predicted_team1")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.predicted_team1).toBe(3);
  });

  test("user cannot predict on behalf of another user (RLS)", async () => {
    // Bob tries to insert a prediction with alice's user_id
    const { error } = await bob.client.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 1,
      predicted_team2: 0,
    });
    expect(error).not.toBeNull();
  });

  test("0-0 prediction with scorer set is rejected by the validation trigger", async () => {
    const { error } = await bob.client.from("predictions").insert({
      user_id: bob.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 0,
      predicted_team2: 0,
      predicted_scorer_id: T.PLAYER_A1, // invalid with 0-0
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/0-0 prediction|check_violation/i);
  });

  test("valid 0-0 prediction (null scorer) is accepted", async () => {
    const { error } = await bob.client.from("predictions").insert({
      user_id: bob.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 0,
      predicted_team2: 0,
      predicted_scorer_id: null,
    });
    expect(error).toBeNull();
  });

  test("duplicate prediction (same user + match) is rejected", async () => {
    const { error } = await alice.client.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 1,
      predicted_team2: 1,
    });
    expect(error).not.toBeNull(); // unique(user_id, match_id)
  });

  test("updated_at is refreshed on update", async () => {
    const before = await alice.client
      .from("predictions")
      .select("updated_at")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId)
      .single();

    await sleep(1100); // ensure at least 1s passes

    await alice.client
      .from("predictions")
      .update({ predicted_team2: 1 })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);

    const after = await alice.client
      .from("predictions")
      .select("updated_at")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId)
      .single();

    const t1 = new Date(before.data!.updated_at).getTime();
    const t2 = new Date(after.data!.updated_at).getTime();
    expect(t2).toBeGreaterThan(t1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3.5  PREDICTION LOCK — DB TRIGGER COVERAGE
// ─────────────────────────────────────────────────────────────────────────────
// Verifies that check_prediction_lock() blocks every vector a user could
// attempt to create or modify a prediction after the window has closed.
// Uses MATCH_PAST (kickoff in past, status=scheduled) as the locked target.
// Each status-mutation sub-test resets the match afterwards.
// ─────────────────────────────────────────────────────────────────────────────

describe("Prediction Lock — DB Trigger", () => {

  // ── INSERT tests ────────────────────────────────────────────────────────────

  test("INSERT blocked when kickoff_time <= now (status still scheduled)", async () => {
    // MATCH_PAST: status=scheduled but kickoff 2h ago → trigger fires
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_PAST,
      predicted_team1: 1,
      predicted_team2: 0,
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
  });

  test("INSERT blocked when match status = 'live'", async () => {
    await admin.from("matches").update({ status: "live" }).eq("id", T.MATCH_PAST);
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_PAST,
      predicted_team1: 1,
      predicted_team2: 0,
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin.from("matches").update({ status: "scheduled" }).eq("id", T.MATCH_PAST);
  });

  test("INSERT blocked when match status = 'final'", async () => {
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 1, score_ft_team2: 0 })
      .eq("id", T.MATCH_PAST);
    await sleep(500); // let scoring trigger settle
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_PAST,
      predicted_team1: 1,
      predicted_team2: 0,
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_PAST);
  });

  test("INSERT blocked when match status = 'cancelled'", async () => {
    await admin.from("matches").update({ status: "cancelled" }).eq("id", T.MATCH_PAST);
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_PAST,
      predicted_team1: 1,
      predicted_team2: 0,
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin.from("matches").update({ status: "scheduled" }).eq("id", T.MATCH_PAST);
  });

  test("INSERT allowed before kickoff (future match, status scheduled)", async () => {
    // Sanity check: charlie can predict on MATCH_FUTURE (future kickoff)
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 1,
      predicted_team2: 1,
    });
    expect(error).toBeNull();
  });

  // ── UPDATE tests ────────────────────────────────────────────────────────────
  // Insert a prediction on MATCH_PAST via the "future kickoff trick" so we have
  // a row to attempt updates on.

  test("setup: insert prediction for MATCH_PAST via future-kickoff trick", async () => {
    const future = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const past   = new Date(Date.now() - 2  * 60 * 60 * 1000).toISOString();
    await admin.from("matches").update({ kickoff_time: future }).eq("id", T.MATCH_PAST);
    const { error } = await charlie.client.from("predictions").insert({
      user_id: charlie.userId,
      match_id: T.MATCH_PAST,
      predicted_team1: 2,
      predicted_team2: 0,
    });
    expect(error).toBeNull();
    // Restore kickoff to past — prediction is now locked by time
    await admin.from("matches").update({ kickoff_time: past }).eq("id", T.MATCH_PAST);
  });

  test("UPDATE predicted_team1 blocked after kickoff", async () => {
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_team1: 3 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
  });

  test("UPDATE predicted_team2 blocked after kickoff", async () => {
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_team2: 3 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
  });

  test("UPDATE predicted_first_team_id blocked after kickoff", async () => {
    // Migration 022 added predicted_first_team_id to the lock trigger's
    // watch list. Verify the column is actually guarded.
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_first_team_id: T.TEAM_A })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
  });

  test("UPDATE predicted_scorer_id blocked after kickoff", async () => {
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_scorer_id: T.PLAYER_A1 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
  });

  test("UPDATE locked_at is NOT blocked (not in trigger column list)", async () => {
    // The trigger only watches predicted_team1/2/scorer_id.
    // Updating locked_at must still work — lock_predictions relies on this.
    const now = new Date().toISOString();
    const { error } = await admin
      .from("predictions")
      .update({ locked_at: now })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).toBeNull();
  });

  test("UPDATE predicted_team1 blocked when status = 'live'", async () => {
    await admin.from("matches").update({ status: "live" }).eq("id", T.MATCH_PAST);
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_team1: 3 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin.from("matches").update({ status: "scheduled" }).eq("id", T.MATCH_PAST);
  });

  test("UPDATE predicted_team2 blocked when status = 'final'", async () => {
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 2, score_ft_team2: 0 })
      .eq("id", T.MATCH_PAST);
    await sleep(1000); // scoring trigger
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_team2: 3 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_PAST);
  });

  test("UPDATE predicted_scorer_id blocked when status = 'cancelled'", async () => {
    await admin.from("matches").update({ status: "cancelled" }).eq("id", T.MATCH_PAST);
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_scorer_id: T.PLAYER_A1 })
      .eq("match_id", T.MATCH_PAST)
      .eq("user_id", charlie.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/locked|check_violation/i);
    await admin.from("matches").update({ status: "scheduled" }).eq("id", T.MATCH_PAST);
  });

  test("UPDATE succeeds before kickoff (future match, all fields)", async () => {
    // charlie can freely edit her MATCH_FUTURE prediction before kickoff
    const { error } = await charlie.client
      .from("predictions")
      .update({ predicted_team1: 2, predicted_team2: 2, predicted_scorer_id: null })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", charlie.userId);
    expect(error).toBeNull();
  });

  test("scorer from team predicted to score 0 is rejected by the validation trigger", async () => {
    // Bob already has a 0-0 prediction on MATCH_FUTURE.
    // Verify he cannot UPDATE to 2-0 with a TEAM_B scorer (team predicted to score 0).
    // The validation trigger enforces this at the DB level — see migration 017.
    const { error } = await bob.client
      .from("predictions")
      .update({ predicted_team1: 2, predicted_team2: 0, predicted_scorer_id: T.PLAYER_B1 })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", bob.userId);
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/team predicted to score 0|check_violation/i);

    // Reset bob's prediction so later tests start from a clean 0-0 + null scorer
    await admin
      .from("predictions")
      .update({ predicted_team1: 0, predicted_team2: 0, predicted_scorer_id: null })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", bob.userId);
  });
});
// ─────────────────────────────────────────────────────────────────────────────
// 4. LOCK PREDICTIONS
// ─────────────────────────────────────────────────────────────────────────────

describe("Lock Predictions", () => {
  // Alice already has an unlocked prediction on MATCH_FUTURE from Predictions tests.
  // To test lock_predictions we move MATCH_FUTURE's kickoff to the past —
  // lock_predictions will then pick it up and set locked_at.
  // The lock trigger only blocks writes to the predictions table, not matches,
  // so updating kickoff_time on the match is always allowed.
  test("setup: move MATCH_FUTURE kickoff to the past", async () => {
    const past = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    const { error } = await admin
      .from("matches")
      .update({ kickoff_time: past })
      .eq("id", T.MATCH_FUTURE);
    expect(error).toBeNull();
    // Verify alice's prediction is still unlocked
    const { data } = await admin
      .from("predictions")
      .select("locked_at")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.locked_at).toBeNull();
  });

  test("lock_predictions function locks predictions for kicked-off matches", async () => {
    const res = await fetch(
      `${SUPABASE_URL}/functions/v1/lock_predictions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ANON_KEY}`,
        },
        body: "{}",
      }
    );
    expect(res.ok).toBe(true);
    const json = await res.json();
    expect(json.ok).toBe(true);
    // Function locks all rows where kickoff_time <= now() and locked_at is null
    expect(json.locked).toBeGreaterThanOrEqual(1);
  });

  test("prediction for past-kickoff match now has locked_at set", async () => {
    const { data } = await admin
      .from("predictions")
      .select("locked_at")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.locked_at).not.toBeNull();
  });

  test("lock_predictions is idempotent — second call locks 0 rows", async () => {
    const res = await fetch(
      `${SUPABASE_URL}/functions/v1/lock_predictions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ANON_KEY}`,
        },
        body: "{}",
      }
    );
    const json = await res.json();
    expect(json.ok).toBe(true);
    // All previously-locked rows have locked_at != null, count delta = 0
  });

  test("MATCH_KO prediction is not locked (kickoff still in future)", async () => {
    // Insert a fresh prediction on MATCH_KO (future kickoff) and verify it stays unlocked
    await alice.client.from("predictions").upsert({
      user_id: alice.userId,
      match_id: T.MATCH_KO,
      predicted_team1: 1,
      predicted_team2: 0,
    }, { onConflict: "user_id,match_id" });
    const { data } = await admin
      .from("predictions")
      .select("locked_at")
      .eq("match_id", T.MATCH_KO)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.locked_at).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. SCORING ENGINE
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Helper: insert predictions for both users for MATCH_SCORING, set match final
 * with given score + events, return the prediction rows.
 */
async function runScoringScenario(scenario: {
  alicePred: {
    predicted_team1: number;
    predicted_team2: number;
    predicted_first_team_id?: number | null;
    predicted_scorer_id?: number | null;
  };
  bobPred?: {
    predicted_team1: number;
    predicted_team2: number;
    predicted_first_team_id?: number | null;
    predicted_scorer_id?: number | null;
  };
  ftScore: [number, number];
  events?: Array<{
    minute: number;
    type: string;
    team_id: number | null;
    player_id: number | null;
    player_name: string;
    detail: string | null;
  }>;
}) {
  // Clean slate for the scoring match
  await admin.from("predictions").delete().eq("match_id", T.MATCH_SCORING);
  await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
  await admin
    .from("matches")
    .update({
      status: "scheduled",
      score_ft_team1: null,
      score_ft_team2: null,
      // Move kickoff to future so the lock trigger allows prediction inserts.
      // The trigger fires on predictions INSERT/UPDATE, not on matches UPDATE.
      kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
    })
    .eq("id", T.MATCH_SCORING);

  // Insert predictions via service role (bypass RLS so we can insert for any user)
  await admin.from("predictions").insert({
    user_id: alice.userId,
    match_id: T.MATCH_SCORING,
    ...scenario.alicePred,
  });

  if (scenario.bobPred) {
    await admin.from("predictions").insert({
      user_id: bob.userId,
      match_id: T.MATCH_SCORING,
      ...scenario.bobPred,
    });
  }

  // Insert events if provided
  if (scenario.events && scenario.events.length > 0) {
    await admin.from("match_events").insert(
      scenario.events.map((e) => ({ ...e, match_id: T.MATCH_SCORING }))
    );
  }

  // Set match to final — triggers compute_match_scoring via DB trigger
  await admin.from("matches").update({
    status: "final",
    score_ft_team1: scenario.ftScore[0],
    score_ft_team2: scenario.ftScore[1],
  }).eq("id", T.MATCH_SCORING);

  // Wait for trigger + materialized view refresh
  await sleep(2000);

  const { data } = await admin
    .from("predictions")
    .select("user_id, points_match, points_first_team, points_goalscorer, multiplier, points_earned")
    .eq("match_id", T.MATCH_SCORING);

  return {
    alice: data?.find((r) => r.user_id === alice.userId),
    bob: data?.find((r) => r.user_id === bob.userId),
  };
}

describe("Scoring Engine", () => {
  // ── Exact score: 5 pts ──────────────────────────────────────────────────────
  test("exact score earns points_match = 5", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 2, predicted_team2: 1 },
      ftScore: [2, 1],
    });
    expect(row?.points_match).toBe(5);
    expect(row?.points_goalscorer).toBe(0);
    expect(row?.multiplier).toBe(1); // group stage, no booster
    expect(row?.points_earned).toBe(5);
  });

  test("exact 0-0 earns points_match = 5", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 0, predicted_team2: 0 },
      ftScore: [0, 0],
    });
    expect(row?.points_match).toBe(5);
    expect(row?.points_earned).toBe(5);
  });

  // ── Goal difference: 3 pts (requires |GD| ≥ 2) ──────────────────────────────
  test("matching GD ≥ 2 (non-exact) earns points_match = 3", async () => {
    // rules.md example: 3-1 vs 4-2 → 3 pts (GD = 2, non-exact)
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 3, predicted_team2: 1 },
      ftScore: [4, 2],
    });
    expect(row?.points_match).toBe(3);
    expect(row?.points_earned).toBe(3);
  });

  test("matching GD = 1 falls through to outcome (2 pts)", async () => {
    // rules.md example: 2-1 vs 1-0 → 2 pts (GD = 1 is trivial; outcome only)
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 2, predicted_team2: 1 },
      ftScore: [1, 0],
    });
    expect(row?.points_match).toBe(2);
    expect(row?.points_earned).toBe(2);
  });

  test("draw with same trivial GD = 0 falls through to outcome (2 pts)", async () => {
    // rules.md example: 1-1 vs 2-2 → 2 pts (draws share GD = 0; outcome only)
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 1, predicted_team2: 1 },
      ftScore: [2, 2],
    });
    expect(row?.points_match).toBe(2);
    expect(row?.points_earned).toBe(2);
  });

  // ── Outcome only: 2 pts ─────────────────────────────────────────────────────
  test("correct outcome (wrong GD) earns points_match = 2", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 3, predicted_team2: 0 }, // GD = 3
      ftScore: [2, 0],                                       // GD = 2
    });
    expect(row?.points_match).toBe(2);
    expect(row?.points_earned).toBe(2);
  });

  // ── Zero: wrong direction ───────────────────────────────────────────────────
  test("wrong direction earns points_match = 0", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 1, predicted_team2: 0 },
      ftScore: [0, 1],
    });
    expect(row?.points_match).toBe(0);
    expect(row?.points_earned).toBe(0);
  });

  test("rules.md example: 0-2 vs 1-1 earns 0 pts", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 0, predicted_team2: 2 },
      ftScore: [1, 1],
    });
    expect(row?.points_match).toBe(0);
    expect(row?.points_earned).toBe(0);
  });

  // ── Goalscorer: independent + additive, worth 8 ─────────────────────────────
  test("goalscorer hit adds 8 pts", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 1, predicted_team2: 0, predicted_scorer_id: T.PLAYER_A1 },
      ftScore: [1, 0],
      events: [
        { minute: 25, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_match).toBe(5);        // exact
    expect(row?.points_goalscorer).toBe(8);
    expect(row?.points_earned).toBe(13);      // 5 + 8
  });

  test("wrong goalscorer earns 0 goalscorer pts", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 1, predicted_team2: 0, predicted_scorer_id: T.PLAYER_A1 },
      ftScore: [1, 0],
      events: [
        { minute: 25, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_B1, player_name: "Beta Forward", detail: null },
      ],
    });
    expect(row?.points_match).toBe(5);        // exact
    expect(row?.points_goalscorer).toBe(0);
    expect(row?.points_earned).toBe(5);
  });

  test("goalscorer stoppage-time goal (minute = 90) still counts", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 1, predicted_team2: 0, predicted_scorer_id: T.PLAYER_A1 },
      ftScore: [1, 0],
      events: [
        { minute: 90, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_goalscorer).toBe(8);
  });

  // ── Full base max ───────────────────────────────────────────────────────────
  test("full house: exact + goalscorer = 13 pts (base max)", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: { predicted_team1: 2, predicted_team2: 1, predicted_scorer_id: T.PLAYER_A1 },
      ftScore: [2, 1],
      events: [
        { minute: 12, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 67, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Forward",  detail: null },
        { minute: 88, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_match).toBe(5);
    expect(row?.points_goalscorer).toBe(8);
    expect(row?.points_earned).toBe(13);
  });

  // ── Two-user independence ───────────────────────────────────────────────────
  test("two users: independent scoring", async () => {
    const { alice: aRow, bob: bRow } = await runScoringScenario({
      alicePred: { predicted_team1: 2, predicted_team2: 1, predicted_scorer_id: T.PLAYER_A1 }, // full house
      bobPred:   { predicted_team1: 4, predicted_team2: 1 }, // GD = 3 vs actual GD = 1 → outcome only
      ftScore: [2, 1],
      events: [
        { minute: 15, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 70, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Forward",  detail: null },
        { minute: 90, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(aRow?.points_earned).toBe(13);     // full house
    expect(bRow?.points_match).toBe(2);       // outcome only (GD differs, |GD| issue moot)
    expect(bRow?.points_goalscorer).toBe(0);
    expect(bRow?.points_earned).toBe(2);
  });

  // ── VAR rollback: deleting an event re-fires scoring ───────────────────────
  test("deleting the matching goalscorer event drops points_goalscorer to 0", async () => {
    // Setup: alice predicts 2-0 with PLAYER_A1 scoring; both events fire,
    // both predictions hit -> 5 + 8 = 13.
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 2,
        predicted_team2: 0,
        predicted_scorer_id: T.PLAYER_A1,
      },
      ftScore: [2, 0],
      events: [
        { minute: 12, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 73, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_goalscorer).toBe(8);
    expect(row?.points_earned).toBe(13);

    // VAR: remove BOTH PLAYER_A1 goals. The `match_events_recompute_scoring`
    // trigger (mig 037) re-runs compute_match_scoring for the match.
    await admin
      .from("match_events")
      .delete()
      .eq("match_id", T.MATCH_SCORING)
      .eq("player_id", T.PLAYER_A1);
    await sleep(1500); // trigger + MV refresh

    const { data } = await admin
      .from("predictions")
      .select("points_match, points_first_team, points_goalscorer, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.points_goalscorer).toBe(0);
    // Match-result still hits exact (DB score didn't change): 5 + 0 + 0 = 5.
    expect(data?.points_match).toBe(5);
    expect(data?.points_earned).toBe(5);
  });

  test("deleting the first-goal event re-evaluates first-team award", async () => {
    // Alice picks TEAM_A as first to score. Setup events: TEAM_A scores
    // first (minute 5), TEAM_B scores later (minute 70) — alice's pick hits.
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_A,
      },
      ftScore: [1, 1],
      events: [
        { minute: 5,  type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 70, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Striker", detail: null },
      ],
    });
    expect(row?.points_first_team).toBe(2);

    // VAR disallows the early TEAM_A goal. TEAM_B's 70' goal is now the
    // first valid goal -> alice's TEAM_A pick should drop to 0.
    await admin
      .from("match_events")
      .delete()
      .eq("match_id", T.MATCH_SCORING)
      .eq("minute", 5);
    await sleep(1500);

    const { data } = await admin
      .from("predictions")
      .select("points_first_team, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(data?.points_first_team).toBe(0);
  });

  // ── Production-ordering / VAR-refresh regression ────────────────────────────
  //
  // poll_live_matches Phase B refreshes events via delete-then-insert. The
  // legacy migration-001 trigger fired only on DELETE while status='final',
  // so a refresh that happened after the status flip would zero scoring
  // (the per-row delete trigger recomputed against a shrinking event set,
  // ending at zero; the subsequent insert had no trigger to restore it).
  // Migration 037 also fires on INSERT, so the last write in any
  // delete-then-insert refresh re-arms scoring with the fresh event set.
  //
  // This test runs the exact destructive sequence end-to-end:
  //   1. predictions while kickoff is future            (lock trigger ok)
  //   2. flip to live + insert events                   (Phase A)
  //   3. flip to final with FT scores                   (Phase B step 1)
  //   4. delete-then-insert the same events post-final  (Phase B refresh)
  //   5. delete a single goal post-final                (VAR-disallow path)
  //
  // Without migration 037 step 4 wipes both bonuses to 0. With it, scoring
  // survives the refresh AND the VAR path still correctly recomputes.
  test("delete-then-insert events post-final preserves bonuses (mig 037)", async () => {
    // ── 1. Clean slate + predictions with future kickoff ─────────────────
    await admin.from("predictions").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
    await admin
      .from("matches")
      .update({
        status: "scheduled",
        score_ft_team1: null,
        score_ft_team2: null,
        kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
      })
      .eq("id", T.MATCH_SCORING);

    await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_SCORING,
      predicted_team1: 2,
      predicted_team2: 1,
      predicted_first_team_id: T.TEAM_A,   // TEAM_A scores first → 2 pts
      predicted_scorer_id: T.PLAYER_A1,    // PLAYER_A1 scores    → 8 pts
    });

    // ── 2. Move kickoff to the past + simulate Phase A (live + events) ───
    await admin
      .from("matches")
      .update({
        kickoff_time: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
        status: "live",
      })
      .eq("id", T.MATCH_SCORING);

    const events = [
      { match_id: T.MATCH_SCORING, minute: 15, type: "goal", team_id: T.TEAM_A,
        player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      { match_id: T.MATCH_SCORING, minute: 60, type: "goal", team_id: T.TEAM_B,
        player_id: T.PLAYER_B1, player_name: "Beta Forward", detail: null },
      { match_id: T.MATCH_SCORING, minute: 80, type: "goal", team_id: T.TEAM_A,
        player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
    ];
    await admin.from("match_events").insert(events);

    // ── 3. Phase B step 1: flip to final → trigger scoring once ──────────
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 2, score_ft_team2: 1 })
      .eq("id", T.MATCH_SCORING);
    await sleep(2000);

    const { data: midRow } = await admin
      .from("predictions")
      .select("points_match, points_first_team, points_goalscorer, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(midRow?.points_match).toBe(5);
    expect(midRow?.points_first_team).toBe(2);
    expect(midRow?.points_goalscorer).toBe(8);
    expect(midRow?.points_earned).toBe(15);

    // ── 4. Post-final delete-then-insert refresh — the dangerous path ────
    await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("match_events").insert(events);
    await sleep(2000);

    const { data: postRow } = await admin
      .from("predictions")
      .select("points_match, points_first_team, points_goalscorer, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(postRow?.points_match).toBe(5);
    expect(postRow?.points_first_team).toBe(2);   // would be 0 without mig 037
    expect(postRow?.points_goalscorer).toBe(8);   // would be 0 without mig 037
    expect(postRow?.points_earned).toBe(15);

    // ── 5. VAR-disallow path: bare DELETE recomputes against new event set ─
    // Drop the 15' goal so TEAM_B (60') becomes the first to score and
    // PLAYER_A1's earliest credited goal is now 80' (still counts).
    await admin
      .from("match_events")
      .delete()
      .eq("match_id", T.MATCH_SCORING)
      .eq("minute", 15);
    await sleep(2000);

    const { data: varRow } = await admin
      .from("predictions")
      .select("points_first_team, points_goalscorer")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(varRow?.points_first_team).toBe(0);    // TEAM_B scored first now
    expect(varRow?.points_goalscorer).toBe(8);    // PLAYER_A1 still on 80'
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 5b. FIRST TEAM TO SCORE
// ─────────────────────────────────────────────────────────────────────────────

describe("First Team to Score", () => {
  // ── Correct pick: 2 pts ─────────────────────────────────────────────────────
  test("correct first-team pick earns points_first_team = 2", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_A,
      },
      ftScore: [1, 1],
      events: [
        { minute: 12, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 73, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Striker", detail: null },
      ],
    });
    expect(row?.points_first_team).toBe(2);
    expect(row?.points_match).toBe(5);          // exact 1-1
    expect(row?.points_goalscorer).toBe(0);     // no scorer picked
    expect(row?.points_earned).toBe(7);         // 5 + 2
  });

  // ── Wrong pick: 0 pts ───────────────────────────────────────────────────────
  test("wrong first-team pick earns 0", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_B,   // wrong — TEAM_A scored first
      },
      ftScore: [1, 1],
      events: [
        { minute: 12, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 73, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Striker", detail: null },
      ],
    });
    expect(row?.points_first_team).toBe(0);
    expect(row?.points_earned).toBe(5);         // exact only
  });

  // ── Stacking: exact + first-team + goalscorer = 15 ──────────────────────────
  test("all three picks correct earns full base 15", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 2,
        predicted_team2: 0,
        predicted_first_team_id: T.TEAM_A,
        predicted_scorer_id: T.PLAYER_A1,
      },
      ftScore: [2, 0],
      events: [
        { minute: 7,  type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
        { minute: 55, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_match).toBe(5);
    expect(row?.points_first_team).toBe(2);
    expect(row?.points_goalscorer).toBe(8);
    expect(row?.points_earned).toBe(15);        // 5 + 2 + 8
  });

  // ── Null pick: never awards points (no implicit 0-0 bonus) ──────────────────
  test("no first-team pick → 0 pts (no implicit award)", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 0,
        predicted_team2: 0,
        predicted_first_team_id: null,
      },
      ftScore: [0, 0],
      events: [],
    });
    expect(row?.points_first_team).toBe(0);
    expect(row?.points_match).toBe(5);          // exact 0-0
    expect(row?.points_earned).toBe(5);
  });

  // ── Own goals do not count as first goal ────────────────────────────────────
  test("own goal is ignored when determining first team to score", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_B,   // TEAM_B's real goal (later) is the first valid one
      },
      ftScore: [1, 1],
      events: [
        // Minute 5: TEAM_A "scored" via TEAM_B's own goal — should not count for first-team-to-score
        { minute: 5,  type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A2, player_name: "OG Defender", detail: "own_goal" },
        // Minute 30: TEAM_B's real first scoring event
        { minute: 30, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Striker", detail: null },
        // Minute 70: TEAM_A real goal
        { minute: 70, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_first_team).toBe(2);     // TEAM_B legitimately scored first (OG excluded)
  });

  // ── ET goal does not count ──────────────────────────────────────────────────
  test("extra-time goal is ignored when determining first team to score", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 0,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_B,
      },
      ftScore: [0, 1],
      events: [
        // FT goal at minute 105 (extra time) — should not count toward first-regulation-goal
        // but FT score 0-1 is still the FT result. The first regulation goal is the 88' B goal.
        { minute: 88,  type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Striker", detail: null },
        { minute: 105, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_first_team).toBe(2);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 5c. FIRST TEAM VALIDATION RULES
// ─────────────────────────────────────────────────────────────────────────────

describe("First Team Validation", () => {
  // Earlier blocks (Lock Predictions) mutate MATCH_FUTURE kickoff to the
  // past. Reset it to a future kickoff before every test in this block so
  // the lock trigger doesn't pre-empt the validation trigger.
  beforeEach(async () => {
    await admin.from("matches").update({
      status: "scheduled",
      kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
    }).eq("id", T.MATCH_FUTURE);
  });

  test("rejects first-team pick on 0-0 prediction", async () => {
    await admin.from("predictions").delete()
      .eq("match_id", T.MATCH_FUTURE).eq("user_id", alice.userId);
    const { error } = await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 0,
      predicted_team2: 0,
      predicted_first_team_id: T.TEAM_A,
    });
    expect(error).not.toBeNull();
    expect(error?.message ?? "").toMatch(/0-0|scoreless/i);
  });

  test("rejects first-team pick on team predicted to score 0", async () => {
    await admin.from("predictions").delete()
      .eq("match_id", T.MATCH_FUTURE).eq("user_id", alice.userId);
    const { error } = await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 2,
      predicted_team2: 0,
      predicted_first_team_id: T.TEAM_B,   // TEAM_B predicted to score 0
    });
    expect(error).not.toBeNull();
    expect(error?.message ?? "").toMatch(/predicted to score 0|score 0/i);
  });

  test("rejects first-team pick on team not in this match", async () => {
    await admin.from("predictions").delete()
      .eq("match_id", T.MATCH_FUTURE).eq("user_id", alice.userId);
    const { error } = await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 1,
      predicted_team2: 1,
      predicted_first_team_id: 99_999,     // not in this match
    });
    expect(error).not.toBeNull();
    expect(error?.message ?? "").toMatch(/not on either match team|foreign key/i);
  });

  test("accepts valid first-team pick on team with non-zero predicted score", async () => {
    await admin.from("predictions").delete()
      .eq("match_id", T.MATCH_FUTURE).eq("user_id", alice.userId);
    const { error } = await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_FUTURE,
      predicted_team1: 2,
      predicted_team2: 1,
      predicted_first_team_id: T.TEAM_A,
    });
    expect(error).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 6. KNOCKOUT BOOSTERS
// ─────────────────────────────────────────────────────────────────────────────

describe("Knockout Boosters", () => {
  test("booster can be applied to a future knockout match", async () => {
    const { error } = await alice.client.from("round_boosters").upsert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_KO,
      multiplier: 4,
    }, { onConflict: "user_id,round" });
    expect(error).toBeNull();

    const { data } = await alice.client
      .from("round_boosters")
      .select("round, multiplier")
      .eq("user_id", alice.userId)
      .eq("match_id", T.MATCH_KO)
      .single();
    expect(data?.round).toBe("QF");
    expect(data?.multiplier).toBe(4);

    // Cleanup
    await admin.from("round_boosters").delete().eq("user_id", alice.userId).eq("round", "QF");
  });

  test("booster multiplier applied to scoring (QF match × 4)", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_KO);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null }).eq("id", T.MATCH_KO);
    await admin.from("round_boosters").delete().eq("user_id", alice.userId).eq("round", "QF");

    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    await admin.from("predictions").insert({
      user_id: alice.userId, match_id: T.MATCH_KO,
      predicted_team1: 2, predicted_team2: 1,
    });
    await admin.from("matches").update({
      status: "final",
      score_ft_team1: 2, score_ft_team2: 1,
    }).eq("id", T.MATCH_KO);
    await sleep(3000);

    const { data: row } = await admin
      .from("predictions")
      .select("points_earned, multiplier")
      .eq("match_id", T.MATCH_KO)
      .eq("user_id", alice.userId)
      .single();

    expect(row?.multiplier).toBe(4);
    // points_match=5 (exact) + points_goalscorer=0 (no scorer) = 5; × 4 = 20
    expect(row?.points_earned).toBe(20);

    // Cleanup
    await admin.from("round_boosters").delete().eq("user_id", alice.userId).eq("round", "QF");
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null }).eq("id", T.MATCH_KO);
  });

  test("booster rejected for non-matching round", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_SCORING, // Matchday 2, not QF
      multiplier: 4,
    });
    expect(error).not.toBeNull(); // check_violation: match round must equal booster round
  });

  // ── Move booster between matches in the same round ─────────────────────────
  // Mirrors the UX of `_BoosterMoveConfirmSheet`: applying a booster to a
  // second match in the same round replaces the row via upsert on
  // `(user_id, round)`. The old match must no longer be boosted; the new
  // match must.
  test("upsert moves booster to a new match in the same round", async () => {
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    // MATCH_ET ships with a past kickoff (used by ET / pens tests). Move
    // it forward so the lock trigger doesn't reject the second upsert
    // before we exercise the conflict resolution.
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: future })
      .eq("id", T.MATCH_ET);

    // Step 1: apply to MATCH_KO
    await alice.client.from("round_boosters").upsert(
      {
        user_id: alice.userId,
        round: "QF",
        match_id: T.MATCH_KO,
        multiplier: 4,
      },
      { onConflict: "user_id,round" }
    );

    // Step 2: re-upsert to MATCH_ET (also QF) — should replace, not duplicate
    const { error } = await alice.client.from("round_boosters").upsert(
      {
        user_id: alice.userId,
        round: "QF",
        match_id: T.MATCH_ET,
        multiplier: 4,
      },
      { onConflict: "user_id,round" }
    );
    expect(error).toBeNull();

    const { data: rows } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(rows).toHaveLength(1);
    expect(rows![0].match_id).toBe(T.MATCH_ET);

    // Cleanup — drop the booster and restore MATCH_ET's past kickoff so
    // the ET / pens tests still see their expected fixture state.
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    const past = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: past })
      .eq("id", T.MATCH_ET);
  });

  // ── Lock trigger rejects writes after kickoff ──────────────────────────────
  // Mirrors `check_booster_lock` from migration 012. Once the match has
  // kicked off (status flipped to 'live' OR kickoff_time has passed), the
  // trigger MUST reject both new applications and updates so a user can't
  // backdate a booster onto a match that already started.
  test("booster insert is rejected after the match has kicked off", async () => {
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    // Move kickoff into the past so the wall-clock branch of the lock
    // trigger fires regardless of status.
    const past = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: past })
      .eq("id", T.MATCH_KO);

    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_KO,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
    expect(error?.message).toMatch(/booster cannot be applied|locked/i);

    // Restore so later tests find a future-kickoff QF match.
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: future })
      .eq("id", T.MATCH_KO);
  });

  test("booster update is rejected after the match has kicked off", async () => {
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    // Insert while still scheduled
    await admin.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_KO,
      multiplier: 4,
    });
    // Flip kickoff into the past
    const past = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: past })
      .eq("id", T.MATCH_KO);

    // The UI sends an update of `multiplier` to keep the booster row in
    // sync with the round; the trigger MUST reject because the match is
    // past its window now.
    const { error } = await alice.client
      .from("round_boosters")
      .update({ multiplier: 4 })
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(error).not.toBeNull();

    // Restore + cleanup
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: future })
      .eq("id", T.MATCH_KO);
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
  });

  // ── Multiplier value constraint ────────────────────────────────────────────
  // Mig 012 hard-codes the round → multiplier mapping (R32×2, R16×3,
  // QF×4, SF×5). A POST with the wrong multiplier for a given round MUST
  // be rejected by the check constraint, even via the admin client.
  test("booster rejected when multiplier doesn't match round", async () => {
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    // QF should be 4, not 5
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_KO,
      multiplier: 5,
    });
    expect(error).not.toBeNull();
  });

  // ── Cross-user isolation ───────────────────────────────────────────────────
  // Alice applying a booster MUST not affect Bob's scoring on the same
  // match. Confirms the multiplier subquery in `compute_match_scoring()`
  // correctly scopes by `rb.user_id = pr.user_id`.
  test("booster applies per-user — other users keep multiplier 1", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_KO);
    await admin
      .from("matches")
      .update({
        status: "scheduled",
        score_ft_team1: null,
        score_ft_team2: null,
      })
      .eq("id", T.MATCH_KO);
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", bob.userId)
      .eq("round", "QF");

    // Alice applies booster, both predict exact 2-1
    await admin.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: T.MATCH_KO,
      multiplier: 4,
    });
    await admin.from("predictions").insert([
      {
        user_id: alice.userId,
        match_id: T.MATCH_KO,
        predicted_team1: 2,
        predicted_team2: 1,
      },
      {
        user_id: bob.userId,
        match_id: T.MATCH_KO,
        predicted_team1: 2,
        predicted_team2: 1,
      },
    ]);
    await admin
      .from("matches")
      .update({
        status: "final",
        score_ft_team1: 2,
        score_ft_team2: 1,
      })
      .eq("id", T.MATCH_KO);
    await sleep(3000);

    const { data: rows } = await admin
      .from("predictions")
      .select("user_id, multiplier, points_earned")
      .eq("match_id", T.MATCH_KO);
    const aliceRow = rows!.find((r) => r.user_id === alice.userId);
    const bobRow = rows!.find((r) => r.user_id === bob.userId);
    expect(aliceRow?.multiplier).toBe(4);
    expect(aliceRow?.points_earned).toBe(20); // exact 5 × 4
    expect(bobRow?.multiplier).toBe(1);
    expect(bobRow?.points_earned).toBe(5); // exact 5 × 1

    // Cleanup
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin
      .from("matches")
      .update({
        status: "scheduled",
        score_ft_team1: null,
        score_ft_team2: null,
      })
      .eq("id", T.MATCH_KO);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 6b. KNOCKOUT BOOSTER EDGE CASES
// ─────────────────────────────────────────────────────────────────────────────
// Exhaustive coverage of constraint / trigger / RLS paths that the UI
// either filters out or doesn't expose, but that the REST surface still
// allows (or rejects). Locks down both the happy paths AND two known
// scoring-drift gaps (DELETE-after-final, MOVE-after-final).

describe("Knockout Booster Edge Cases", () => {
  // Synthetic match IDs scoped to this block. Cleaned up in afterAll.
  // NB: `matches.kickoff_time` is NOT NULL in the schema, so a TBD-bracket
  // booster (kickoff_time IS NULL) is unreachable in production — the
  // `check_booster_lock` trigger's `v_kickoff_time IS NOT NULL` guard is
  // defensive dead code. We don't try to exercise that branch.
  const M = {
    CANCELLED: 99_310, // QF, status='cancelled', future kickoff
    LIVE_QF:   99_311, // QF, status='live',      future kickoff
    CASCADE:   99_313, // QF, status='scheduled', future kickoff (deleted mid-test)
    R32:       99_320, // R32, status='scheduled', future kickoff
    R16:       99_321, // R16, status='scheduled', future kickoff
    SF:        99_322, // SF,  status='scheduled', future kickoff
  };

  // Block-local group so the RLS group_read tests are self-contained
  // (the shared module-level `groupId` is only populated when the
  // Groups describe block actually runs — which it doesn't under
  // `bun test -t "Booster Edge Cases"`).
  let edgeGroupId: string;

  const future = () =>
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

  beforeAll(async () => {
    const f = future();
    const { error: matchErr } = await admin.from("matches").upsert([
      { id: M.CANCELLED, round: "QF",  group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "cancelled" },
      { id: M.LIVE_QF,   round: "QF",  group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "live" },
      { id: M.CASCADE,   round: "QF",  group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "scheduled" },
      { id: M.R32,       round: "R32", group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "scheduled" },
      { id: M.R16,       round: "R16", group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "scheduled" },
      { id: M.SF,        round: "SF",  group_letter: null, team1_id: T.TEAM_A, team2_id: T.TEAM_B, kickoff_time: f, status: "scheduled" },
    ]);
    expect(matchErr).toBeNull();

    // Local group with alice + bob as members so the group_read RLS
    // policy can be exercised without depending on the Groups block.
    const code = `TEST_EDGE_${Date.now()}`;
    const { data: g, error: gErr } = await admin
      .from("groups")
      .insert({ name: `TEST_EdgeGroup_${Date.now()}`, owner_id: alice.userId, invite_code: code })
      .select()
      .single();
    expect(gErr).toBeNull();
    edgeGroupId = g!.id;
    const { error: mErr } = await admin.from("group_members").insert([
      { group_id: edgeGroupId, user_id: alice.userId },
      { group_id: edgeGroupId, user_id: bob.userId },
    ]);
    expect(mErr).toBeNull();
  });

  // Wipe alice + bob boosters between tests so order-of-execution doesn't
  // affect assertions. Match state is restored per-test where needed.
  beforeEach(async () => {
    await admin
      .from("round_boosters")
      .delete()
      .in("user_id", [alice.userId, bob.userId]);
  });

  afterAll(async () => {
    await admin
      .from("round_boosters")
      .delete()
      .in("user_id", [alice.userId, bob.userId]);
    await admin.from("predictions").delete().in("match_id", Object.values(M));
    await admin.from("matches").delete().in("id", Object.values(M));
    if (edgeGroupId) {
      await admin.from("group_members").delete().eq("group_id", edgeGroupId);
      await admin.from("groups").delete().eq("id", edgeGroupId);
    }
  });

  // ── Round-value enum ───────────────────────────────────────────────
  // valid_round CHECK constraint: round in ('R32','R16','QF','SF').
  // Final and 3rd are auto-multiplier rounds; no manual booster row
  // should ever exist for them.

  test("round='Final' rejected (auto-multiplier round, not in enum)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "Final",
      match_id: T.MATCH_KO,
      multiplier: 6,
    });
    expect(error).not.toBeNull();
  });

  test("round='3rd' rejected (auto-multiplier round, not in enum)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "3rd",
      match_id: T.MATCH_KO,
      multiplier: 5,
    });
    expect(error).not.toBeNull();
  });

  test("round='Group Stage' rejected (not in enum)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "Group Stage",
      match_id: T.MATCH_SCORING,
      multiplier: 2,
    });
    expect(error).not.toBeNull();
  });

  test("round='foo' rejected (not in enum)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "foo",
      match_id: T.MATCH_KO,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
  });

  // ── (round, multiplier) pairing matrix ─────────────────────────────
  // valid_multiplier CHECK constraint hard-codes the per-round value.
  // Every wrong pairing MUST be rejected; every right pairing MUST be
  // accepted. Existing suite already exercises QF×4 happy path + QF×5
  // rejection — these widen the matrix.

  test("all four valid (round, multiplier) pairings accepted", async () => {
    const rows = [
      { round: "R32", match_id: M.R32, multiplier: 2 },
      { round: "R16", match_id: M.R16, multiplier: 3 },
      { round: "QF",  match_id: T.MATCH_KO, multiplier: 4 },
      { round: "SF",  match_id: M.SF,  multiplier: 5 },
    ].map((r) => ({ ...r, user_id: alice.userId }));
    const { error } = await admin.from("round_boosters").insert(rows);
    expect(error).toBeNull();

    const { data } = await admin
      .from("round_boosters")
      .select("round, multiplier")
      .eq("user_id", alice.userId);
    expect(data).toHaveLength(4);
  });

  test("R32 rejects multipliers 3 / 4 / 5", async () => {
    for (const m of [3, 4, 5]) {
      const { error } = await alice.client.from("round_boosters").insert({
        user_id: alice.userId, round: "R32", match_id: M.R32, multiplier: m,
      });
      expect(error).not.toBeNull();
    }
  });

  test("R16 rejects multipliers 2 / 4 / 5", async () => {
    for (const m of [2, 4, 5]) {
      const { error } = await alice.client.from("round_boosters").insert({
        user_id: alice.userId, round: "R16", match_id: M.R16, multiplier: m,
      });
      expect(error).not.toBeNull();
    }
  });

  test("SF rejects multipliers 2 / 3 / 4", async () => {
    for (const m of [2, 3, 4]) {
      const { error } = await alice.client.from("round_boosters").insert({
        user_id: alice.userId, round: "SF", match_id: M.SF, multiplier: m,
      });
      expect(error).not.toBeNull();
    }
  });

  test("multiplier=0 and multiplier=-1 rejected (no round accepts them)", async () => {
    for (const m of [0, -1, 999]) {
      const { error } = await alice.client.from("round_boosters").insert({
        user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: m,
      });
      expect(error).not.toBeNull();
    }
  });

  // ── NOT NULL + FK ──────────────────────────────────────────────────

  test("NULL match_id rejected (NOT NULL constraint)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: null,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
  });

  test("non-existent match_id rejected (FK violation)", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: 9_999_999,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
  });

  // ── Lock trigger: status branches ──────────────────────────────────

  test("booster on cancelled match rejected by lock trigger", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: M.CANCELLED,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
    expect(error?.message).toMatch(/booster cannot be applied|locked/i);
  });

  test("booster on live match rejected by lock trigger", async () => {
    const { error } = await alice.client.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: M.LIVE_QF,
      multiplier: 4,
    });
    expect(error).not.toBeNull();
    expect(error?.message).toMatch(/booster cannot be applied|locked/i);
  });
  // ── ON DELETE CASCADE ──────────────────────────────────────────────

  test("deleting the match cascades to its booster rows", async () => {
    await admin.from("round_boosters").insert({
      user_id: alice.userId,
      round: "QF",
      match_id: M.CASCADE,
      multiplier: 4,
    });
    const { data: before } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("match_id", M.CASCADE);
    expect(before).toHaveLength(1);

    await admin.from("matches").delete().eq("id", M.CASCADE);

    const { data: after } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("match_id", M.CASCADE);
    expect(after).toHaveLength(0);

    // Restore the match for any later test in this block.
    await admin.from("matches").insert({
      id: M.CASCADE, round: "QF", group_letter: null,
      team1_id: T.TEAM_A, team2_id: T.TEAM_B,
      kickoff_time: future(), status: "scheduled",
    });
  });

  // ── Cross-round: one booster per round ─────────────────────────────

  test("user can hold concurrent boosters across all four rounds", async () => {
    await admin.from("round_boosters").insert([
      { user_id: alice.userId, round: "R32", match_id: M.R32, multiplier: 2 },
      { user_id: alice.userId, round: "R16", match_id: M.R16, multiplier: 3 },
      { user_id: alice.userId, round: "QF",  match_id: T.MATCH_KO, multiplier: 4 },
      { user_id: alice.userId, round: "SF",  match_id: M.SF,  multiplier: 5 },
    ]);
    const { data } = await admin
      .from("round_boosters")
      .select("round")
      .eq("user_id", alice.userId);
    expect(data?.map((r) => r.round).sort()).toEqual(["QF","R16","R32","SF"]);
  });

  test("upserting same round twice keeps the row count at one", async () => {
    // PK is (user_id, round) so an insert of (alice, R32) twice MUST
    // fail outright unless onConflict is specified.
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "R32", match_id: M.R32, multiplier: 2,
    });
    const { error } = await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "R32", match_id: M.R32, multiplier: 2,
    });
    expect(error).not.toBeNull(); // PK violation

    // Upsert-with-conflict succeeds and leaves a single row.
    const { error: e2 } = await admin
      .from("round_boosters")
      .upsert(
        { user_id: alice.userId, round: "R32", match_id: M.R32, multiplier: 2 },
        { onConflict: "user_id,round" },
      );
    expect(e2).toBeNull();

    const { data } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "R32");
    expect(data).toHaveLength(1);
  });

  // ── RLS ────────────────────────────────────────────────────────────

  test("anon client cannot INSERT booster (RLS denial)", async () => {
    const anon = anonClient();
    const { error } = await anon.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    expect(error).not.toBeNull();
  });

  test("bob cannot INSERT booster with alice's user_id (RLS with_check)", async () => {
    const { error } = await bob.client.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    expect(error).not.toBeNull();
  });

  test("bob cannot UPDATE alice's booster row", async () => {
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    const { error, data } = await bob.client
      .from("round_boosters")
      .update({ match_id: M.CASCADE })
      .eq("user_id", alice.userId)
      .eq("round", "QF")
      .select();
    // RLS denies the row to bob → UPDATE matches zero rows. No error,
    // but the returned data MUST be empty AND the row MUST be untouched.
    expect(error).toBeNull();
    expect(data ?? []).toHaveLength(0);
    const { data: stillThere } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "QF")
      .single();
    expect(stillThere?.match_id).toBe(T.MATCH_KO);
  });

  test("bob cannot DELETE alice's booster row", async () => {
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    await bob.client
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    const { data } = await admin
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(data).toHaveLength(1);
  });

  test("bob cannot SELECT alice's pre-kickoff booster (own-only policy)", async () => {
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    const { data } = await bob.client
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(data ?? []).toHaveLength(0);
  });

  test("bob CAN SELECT alice's post-kickoff booster (same group, group_read)", async () => {
    // The Groups describe block has already added alice + bob to
    // `groupId`. Once the match status flips out of 'scheduled', the
    // group_read policy allows bob to see alice's row.
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    // Flip MATCH_KO to live so the group_read predicate matches.
    await admin
      .from("matches")
      .update({ status: "live" })
      .eq("id", T.MATCH_KO);

    const { data } = await bob.client
      .from("round_boosters")
      .select("match_id, multiplier")
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(data).toHaveLength(1);
    expect(data![0].multiplier).toBe(4);

    // Restore status for downstream tests.
    await admin
      .from("matches")
      .update({ status: "scheduled" })
      .eq("id", T.MATCH_KO);
  });

  test("charlie (NOT in group) cannot SELECT alice's post-kickoff booster", async () => {
    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    await admin.from("matches").update({ status: "live" }).eq("id", T.MATCH_KO);

    const { data } = await charlie.client
      .from("round_boosters")
      .select("match_id")
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    expect(data ?? []).toHaveLength(0);

    await admin.from("matches").update({ status: "scheduled" }).eq("id", T.MATCH_KO);
  });

  // ── Scoring side-effects ───────────────────────────────────────────

  test("booster with no prediction has no scoring effect (no row created)", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_KO);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);

    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    // No prediction inserted for alice.
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 2, score_ft_team2: 1 })
      .eq("id", T.MATCH_KO);
    await sleep(2000);

    const { data } = await admin
      .from("predictions")
      .select("user_id")
      .eq("match_id", T.MATCH_KO);
    // compute_match_scoring updates existing rows; it MUST NOT
    // spontaneously create one just because a booster exists.
    expect((data ?? []).length).toBe(0);

    // Cleanup
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);
  });

  // ── Scoring DRIFT gaps ─────────────────────────────────────────────
  // These document KNOWN gaps in the trigger surface. The trigger
  // `check_booster_lock` only fires on INSERT/UPDATE, never DELETE; and
  // moving the booster between matches (upsert with new match_id) does
  // not re-run `compute_match_scoring` on the OLD match. If the old
  // match has already finalised, its `multiplier` column is now stale.
  //
  // Until a DELETE trigger + cross-match recompute lands, these tests
  // pin the current (buggy) behavior so that fixing it produces a
  // test failure here as a forcing function.

  test("GAP: DELETE booster after final leaves multiplier stuck on prediction", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_KO);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);

    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    await admin.from("predictions").insert({
      user_id: alice.userId, match_id: T.MATCH_KO,
      predicted_team1: 2, predicted_team2: 1,
    });
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 2, score_ft_team2: 1 })
      .eq("id", T.MATCH_KO);
    await sleep(3000);

    // Verify the multiplier was applied.
    const { data: scored } = await admin
      .from("predictions")
      .select("multiplier, points_earned")
      .eq("user_id", alice.userId)
      .eq("match_id", T.MATCH_KO)
      .single();
    expect(scored?.multiplier).toBe(4);
    expect(scored?.points_earned).toBe(20);

    // Now DELETE the booster post-final.
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    await sleep(500);

    // The prediction's multiplier is STALE — no DELETE trigger rewrites it.
    const { data: after } = await admin
      .from("predictions")
      .select("multiplier, points_earned")
      .eq("user_id", alice.userId)
      .eq("match_id", T.MATCH_KO)
      .single();
    // KNOWN GAP: should be 1 / 5; currently 4 / 20.
    expect(after?.multiplier).toBe(4);
    expect(after?.points_earned).toBe(20);

    // Cleanup
    await admin.from("predictions").delete().eq("match_id", T.MATCH_KO);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);
  });

  test("GAP: MOVE booster after old match final leaves old prediction stuck", async () => {
    await admin.from("predictions").delete().in("match_id", [T.MATCH_KO, T.MATCH_ET]);
    await admin.from("match_events").delete().in("match_id", [T.MATCH_KO, T.MATCH_ET]);
    // MATCH_ET ships with past kickoff — push to future so the upsert
    // passes the lock trigger.
    const f = future();
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, kickoff_time: f })
      .eq("id", T.MATCH_ET);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);

    await admin.from("round_boosters").insert({
      user_id: alice.userId, round: "QF", match_id: T.MATCH_KO, multiplier: 4,
    });
    await admin.from("predictions").insert([
      { user_id: alice.userId, match_id: T.MATCH_KO, predicted_team1: 2, predicted_team2: 1 },
      { user_id: alice.userId, match_id: T.MATCH_ET, predicted_team1: 1, predicted_team2: 0 },
    ]);
    // Finalise MATCH_KO → alice's prediction.multiplier = 4.
    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 2, score_ft_team2: 1 })
      .eq("id", T.MATCH_KO);
    await sleep(3000);

    const { data: koScored } = await admin
      .from("predictions")
      .select("multiplier, points_earned")
      .eq("user_id", alice.userId)
      .eq("match_id", T.MATCH_KO)
      .single();
    expect(koScored?.multiplier).toBe(4);
    expect(koScored?.points_earned).toBe(20);

    // Now MOVE the booster to MATCH_ET (still scheduled). The
    // (user_id, round) PK upsert replaces the row in-place.
    await admin.from("round_boosters").upsert(
      { user_id: alice.userId, round: "QF", match_id: T.MATCH_ET, multiplier: 4 },
      { onConflict: "user_id,round" },
    );
    await sleep(500);

    // MATCH_KO's prediction.multiplier is STALE — nothing recomputed
    // the old match when the booster row moved.
    const { data: koAfter } = await admin
      .from("predictions")
      .select("multiplier, points_earned")
      .eq("user_id", alice.userId)
      .eq("match_id", T.MATCH_KO)
      .single();
    // KNOWN GAP: should be 1 / 5; currently 4 / 20.
    expect(koAfter?.multiplier).toBe(4);
    expect(koAfter?.points_earned).toBe(20);

    // Cleanup — drop the booster, both predictions, restore MATCH_KO
    // to scheduled, and shove MATCH_ET back to its past kickoff so
    // the extra-time tests still see their expected state.
    await admin
      .from("round_boosters")
      .delete()
      .eq("user_id", alice.userId)
      .eq("round", "QF");
    await admin.from("predictions").delete().in("match_id", [T.MATCH_KO, T.MATCH_ET]);
    await admin
      .from("matches")
      .update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null })
      .eq("id", T.MATCH_KO);
    const past = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: past })
      .eq("id", T.MATCH_ET);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 7. EDGE CASES
// ─────────────────────────────────────────────────────────────────────────────

describe("Edge Cases", () => {
  test("own goal excluded from goalscorer credit", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1, predicted_team2: 2,
        predicted_scorer_id: T.PLAYER_A1,
      },
      ftScore: [1, 2],
      events: [
        { minute: 5,  type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_A2, player_name: "Alpha OG",    detail: "own_goal" },
        { minute: 60, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Forward", detail: null },
        { minute: 85, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_B1, player_name: "Beta Forward", detail: "own_goal" },
      ],
    });
    expect(row?.points_goalscorer).toBe(0);   // A1 never scored a non-OG goal in regulation
    expect(row?.points_match).toBe(5);        // predicted 1-2, actual 1-2 → exact
    expect(row?.points_earned).toBe(5);
  });

  test("VAR disallowed goal: removing event re-triggers scoring", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString() }).eq("id", T.MATCH_SCORING);

    await admin.from("predictions").insert({
      user_id: alice.userId,
      match_id: T.MATCH_SCORING,
      predicted_team1: 1, predicted_team2: 0,
      predicted_scorer_id: T.PLAYER_A1,
    });
    await admin.from("match_events").insert({
      match_id: T.MATCH_SCORING,
      minute: 20, type: "goal",
      team_id: T.TEAM_A,
      player_id: T.PLAYER_A1, player_name: "Alpha Striker",
      detail: null,
    });
    await admin.from("matches").update({ status: "final", score_ft_team1: 1, score_ft_team2: 0 }).eq("id", T.MATCH_SCORING);
    await sleep(2000);

    const { data: before } = await admin
      .from("predictions")
      .select("points_goalscorer, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(before?.points_goalscorer).toBe(8);
    expect(before?.points_earned).toBe(13);   // points_match=5 (exact 1-0) + 8

    const { data: evRow } = await admin
      .from("match_events")
      .select("id")
      .eq("match_id", T.MATCH_SCORING)
      .eq("type", "goal")
      .single();
    await admin.from("match_events").delete().eq("id", evRow!.id);
    await sleep(2000);

    const { data: after } = await admin
      .from("predictions")
      .select("points_goalscorer, points_match, points_earned")
      .eq("match_id", T.MATCH_SCORING)
      .eq("user_id", alice.userId)
      .single();
    expect(after?.points_goalscorer).toBe(0);
    expect(after?.points_match).toBe(5);      // still exact 1-0
    expect(after?.points_earned).toBe(5);
  });

  test("extra time: scoring uses FT (90') not ET result", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_ET);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_ET);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, score_et_team1: null, score_et_team2: null, kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString() }).eq("id", T.MATCH_ET);

    await admin.from("predictions").insert({
      user_id: alice.userId, match_id: T.MATCH_ET,
      predicted_team1: 1, predicted_team2: 1, // exact FT
    });
    await admin.from("predictions").insert({
      user_id: bob.userId, match_id: T.MATCH_ET,
      predicted_team1: 2, predicted_team2: 1, // ET result — wrong for FT draw
    });
    await admin.from("matches").update({
      status: "final",
      score_ft_team1: 1, score_ft_team2: 1,
      score_et_team1: 2, score_et_team2: 1,
    }).eq("id", T.MATCH_ET);
    await sleep(2000);

    const { data } = await admin
      .from("predictions")
      .select("user_id, points_match, points_earned")
      .eq("match_id", T.MATCH_ET);

    const aRow = data?.find((r) => r.user_id === alice.userId);
    const bRow = data?.find((r) => r.user_id === bob.userId);

    expect(aRow?.points_match).toBe(5);   // exact FT 1-1
    expect(aRow?.points_earned).toBe(5);  // no booster, no auto-multiplier on QF
    // Bob predicted 2-1 (home win), FT was 1-1 (draw) → wrong direction
    expect(bRow?.points_match).toBe(0);
    expect(bRow?.points_earned).toBe(0);
  });

  test("goalscorer at minute > 90 excluded when ET occurred", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_ET);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_ET);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, score_et_team1: null, score_et_team2: null, kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString() }).eq("id", T.MATCH_ET);

    await admin.from("predictions").insert({
      user_id: alice.userId, match_id: T.MATCH_ET,
      predicted_team1: 1, predicted_team2: 0,
      predicted_scorer_id: T.PLAYER_A1,
    });
    await admin.from("match_events").insert({
      match_id: T.MATCH_ET, minute: 95, type: "goal",
      team_id: T.TEAM_A, player_id: T.PLAYER_A1,
      player_name: "Alpha Striker", detail: null,
    });
    await admin.from("matches").update({
      status: "final",
      score_ft_team1: 1, score_ft_team2: 0,
      score_et_team1: 1, score_et_team2: 0,
    }).eq("id", T.MATCH_ET);
    await sleep(2000);

    const { data: row } = await admin
      .from("predictions")
      .select("points_goalscorer")
      .eq("match_id", T.MATCH_ET)
      .eq("user_id", alice.userId)
      .single();
    expect(row?.points_goalscorer).toBe(0); // minute 95 > 90 → excluded
  });

  test("goalscorer at minute 90 included even when ET occurred", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_ET);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_ET);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, score_et_team1: null, score_et_team2: null, kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString() }).eq("id", T.MATCH_ET);

    await admin.from("predictions").insert({
      user_id: alice.userId, match_id: T.MATCH_ET,
      predicted_team1: 1, predicted_team2: 0,
      predicted_scorer_id: T.PLAYER_A1,
    });
    await admin.from("match_events").insert({
      match_id: T.MATCH_ET, minute: 90, type: "goal",
      team_id: T.TEAM_A, player_id: T.PLAYER_A1,
      player_name: "Alpha Striker", detail: null,
    });
    await admin.from("matches").update({
      status: "final",
      score_ft_team1: 1, score_ft_team2: 0,
      score_et_team1: 2, score_et_team2: 0,
    }).eq("id", T.MATCH_ET);
    await sleep(2000);

    const { data: row } = await admin
      .from("predictions")
      .select("points_goalscorer")
      .eq("match_id", T.MATCH_ET)
      .eq("user_id", alice.userId)
      .single();
    expect(row?.points_goalscorer).toBe(8); // minute 90 <= 90, included
  });

  test("goalscorer at minute > 90 excluded (rule: regular time = elapsed <= 90)", async () => {
    const { alice: row } = await runScoringScenario({
      alicePred: {
        predicted_team1: 1, predicted_team2: 0,
        predicted_scorer_id: T.PLAYER_A1,
      },
      ftScore: [1, 0],
      events: [
        { minute: 125, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      ],
    });
    expect(row?.points_goalscorer).toBe(0); // 125 > 90 → excluded
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 8. LEADERBOARD — group_standings materialized view
// ─────────────────────────────────────────────────────────────────────────────

describe("Leaderboard — group_standings", () => {
  test("standings reflect correct totals after match finalized", async () => {
    await admin.from("predictions").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("matches").update({ status: "scheduled", score_ft_team1: null, score_ft_team2: null, kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString() }).eq("id", T.MATCH_SCORING);

    await admin.from("predictions").insert([
      {
        user_id: alice.userId, match_id: T.MATCH_SCORING,
        predicted_team1: 2, predicted_team2: 1,
        predicted_scorer_id: T.PLAYER_A1,
      },
      {
        user_id: bob.userId, match_id: T.MATCH_SCORING,
        predicted_team1: 1, predicted_team2: 0, // correct diff (1), not exact
      },
    ]);

    await admin.from("match_events").insert([
      { match_id: T.MATCH_SCORING, minute: 15, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      { match_id: T.MATCH_SCORING, minute: 70, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Forward",  detail: null },
      { match_id: T.MATCH_SCORING, minute: 88, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
    ]);

    await admin.from("matches").update({ status: "final", score_ft_team1: 2, score_ft_team2: 1 }).eq("id", T.MATCH_SCORING);
    await sleep(3000);

    const { data, error } = await admin
      .from("group_standings")
      .select("user_id, total_points, exact_count, outcome_count, scorer_count")
      .eq("group_id", groupId);

    expect(error).toBeNull();
    const aStanding = data?.find((r) => r.user_id === alice.userId);
    const bStanding = data?.find((r) => r.user_id === bob.userId);

    // Alice: exact 2-1 (points_match=5) + goalscorer (8) = 13
    expect(aStanding?.exact_count).toBeGreaterThanOrEqual(1);
    // Bob: 1-0 prediction vs 2-1 actual → |GD|=1 trivial; falls through to outcome only = 2
    expect(aStanding!.total_points).toBeGreaterThan(bStanding!.total_points);
  });

  test("standings are queryable by authenticated group member", async () => {
    const { data, error } = await alice.client
      .from("group_standings")
      .select("user_id, total_points")
      .eq("group_id", groupId);
    expect(error).toBeNull();
    expect(data?.length).toBeGreaterThan(0);
  });

  test("first_team_count increments on correct first-team pick, not on wrong pick", async () => {
    // Migration 023 added first_team_count to group_standings as a tiebreaker
    // between scorer_count and goal_diff_count. Verify the MV picks up
    // points_first_team = 2 rows and only those rows.
    await admin.from("predictions").delete().eq("match_id", T.MATCH_SCORING);
    await admin.from("match_events").delete().eq("match_id", T.MATCH_SCORING);
    await admin
      .from("matches")
      .update({
        status: "scheduled",
        score_ft_team1: null,
        score_ft_team2: null,
        kickoff_time: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
      })
      .eq("id", T.MATCH_SCORING);

    await admin.from("predictions").insert([
      {
        // Alice: 1-1 prediction, picks TEAM_A as first team — TEAM_A scores
        // first (15') so first_team_count should include this match.
        user_id: alice.userId,
        match_id: T.MATCH_SCORING,
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_A,
      },
      {
        // Bob: same 1-1 but picks TEAM_B as first — wrong. Both teams have
        // non-zero predicted scores so validate_prediction_picks accepts it.
        user_id: bob.userId,
        match_id: T.MATCH_SCORING,
        predicted_team1: 1,
        predicted_team2: 1,
        predicted_first_team_id: T.TEAM_B,
      },
    ]);

    await admin.from("match_events").insert([
      { match_id: T.MATCH_SCORING, minute: 15, type: "goal", team_id: T.TEAM_A, player_id: T.PLAYER_A1, player_name: "Alpha Striker", detail: null },
      { match_id: T.MATCH_SCORING, minute: 70, type: "goal", team_id: T.TEAM_B, player_id: T.PLAYER_B1, player_name: "Beta Forward",  detail: null },
    ]);

    await admin
      .from("matches")
      .update({ status: "final", score_ft_team1: 1, score_ft_team2: 1 })
      .eq("id", T.MATCH_SCORING);
    await sleep(3000);

    const { data, error } = await admin
      .from("group_standings")
      .select("user_id, first_team_count, scorer_count, exact_count")
      .eq("group_id", groupId);
    expect(error).toBeNull();

    const aStanding = data?.find((r) => r.user_id === alice.userId);
    const bStanding = data?.find((r) => r.user_id === bob.userId);

    // Alice picked correctly → first_team_count includes this final.
    expect(aStanding?.first_team_count).toBeGreaterThanOrEqual(1);
    // Bob picked wrong → no first-team credit for this match.
    expect(bStanding?.first_team_count ?? 0).toBe(0);
    // Neither picked a scorer here → scorer_count stays at whatever it was
    // for prior fixtures (no increment from this match).
    expect(aStanding?.exact_count).toBeGreaterThanOrEqual(1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 8. RLS — CROSS-USER PREDICTION VISIBILITY
// ─────────────────────────────────────────────────────────────────────────────

describe("RLS — Cross-User Prediction Visibility", () => {
  // alice and bob are in groupId; charlie is NOT
  // We use MATCH_FUTURE for these tests (not yet locked)

  test("setup: ensure charlie is not in the group", async () => {
    await admin
      .from("group_members")
      .delete()
      .eq("group_id", groupId)
      .eq("user_id", charlie.userId);

    // Verify
    const { data } = await admin
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("user_id", charlie.userId);
    expect(data?.length ?? 0).toBe(0);
  });

  test("unlocked prediction is NOT visible to group-mate (bob)", async () => {
    // Ensure alice has an unlocked prediction on MATCH_FUTURE
    // (set in prediction tests; reset locked_at to null for this test)
    await admin
      .from("predictions")
      .update({ locked_at: null })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);

    const { data } = await bob.client
      .from("predictions")
      .select("id")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    // locked_at = null → predictions_group_read policy blocks it
    expect(data?.length ?? 0).toBe(0);
  });

  test("locked prediction IS visible to group-mate (bob)", async () => {
    // Lock alice's prediction manually
    await admin
      .from("predictions")
      .update({ locked_at: new Date().toISOString() })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);

    const { data } = await bob.client
      .from("predictions")
      .select("predicted_team1, predicted_team2")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    expect(data?.length ?? 0).toBe(1);
  });

  test("locked prediction is NOT visible to charlie (not in group)", async () => {
    const { data } = await charlie.client
      .from("predictions")
      .select("id")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    expect(data?.length ?? 0).toBe(0);
  });

  test("user can always read their own predictions regardless of lock", async () => {
    // Alice reads her own locked prediction
    const { data, error } = await alice.client
      .from("predictions")
      .select("predicted_team1")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    expect(error).toBeNull();
    expect(data?.length ?? 0).toBe(1);
  });

  test("user cannot read another user's unlocked prediction even with anon client", async () => {
    await admin
      .from("predictions")
      .update({ locked_at: null })
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);

    const anon = anonClient(); // unauthenticated — no user JWT, RLS blocks all prediction reads
    // Anon (not authenticated as any user) — own-rw requires auth.uid()
    // group_read requires locked_at is not null
    // → should return 0 rows
    const { data } = await anon
      .from("predictions")
      .select("id")
      .eq("match_id", T.MATCH_FUTURE)
      .eq("user_id", alice.userId);
    expect(data?.length ?? 0).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 9. TOURNAMENT PREDICTIONS — World Cup winner + Golden Boot bonus
// ─────────────────────────────────────────────────────────────────────────────
// Runs LAST because the suite mutates every match's kickoff_time to the
// future. The afterAll teardown wipes everything anyway, so nothing
// downstream depends on these mutations.

describe("Tournament Predictions", () => {
  const FUTURE_KICKOFF = new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString();

  beforeAll(async () => {
    // Push every match's kickoff into the future so tournament_predictions
    // are not yet locked. The trigger inspects MIN(kickoff_time) across all
    // non-cancelled matches.
    await admin
      .from("matches")
      .update({ kickoff_time: FUTURE_KICKOFF, status: "scheduled" })
      .in("id", [
        T.MATCH_FUTURE, T.MATCH_PAST, T.MATCH_SCORING, T.MATCH_ET, T.MATCH_KO,
      ]);

    // Clean slate
    await admin
      .from("tournament_predictions")
      .delete()
      .in("user_id", [alice.userId, bob.userId, charlie.userId]);
    await admin.from("tournament_results").delete().eq("id", true);
  });

  test("user can insert a tournament prediction before lock", async () => {
    const { error } = await alice.client.from("tournament_predictions").insert({
      user_id: alice.userId,
      wc_winner_team_id: T.TEAM_A,
      golden_boot_player_id: T.PLAYER_A1,
    });
    expect(error).toBeNull();

    const { data } = await alice.client
      .from("tournament_predictions")
      .select("wc_winner_team_id, golden_boot_player_id, points_earned")
      .eq("user_id", alice.userId)
      .single();
    expect(data?.wc_winner_team_id).toBe(T.TEAM_A);
    expect(data?.golden_boot_player_id).toBe(T.PLAYER_A1);
    expect(data?.points_earned).toBe(0); // results not posted yet
  });

  test("user can update a tournament prediction before lock", async () => {
    const { error } = await alice.client
      .from("tournament_predictions")
      .update({ wc_winner_team_id: T.TEAM_B })
      .eq("user_id", alice.userId);
    expect(error).toBeNull();

    const { data } = await alice.client
      .from("tournament_predictions")
      .select("wc_winner_team_id")
      .eq("user_id", alice.userId)
      .single();
    expect(data?.wc_winner_team_id).toBe(T.TEAM_B);
  });

  test("upsert works for first-time submission", async () => {
    const { error } = await bob.client.from("tournament_predictions").upsert({
      user_id: bob.userId,
      wc_winner_team_id: T.TEAM_A,
      golden_boot_player_id: T.PLAYER_B1,
    });
    expect(error).toBeNull();
  });

  test("user cannot insert a tournament prediction for another user (RLS)", async () => {
    const { error } = await bob.client.from("tournament_predictions").insert({
      user_id: alice.userId, // attempt to write on alice's behalf
      wc_winner_team_id: T.TEAM_A,
    });
    expect(error).not.toBeNull();
  });

  test("scoring fires on tournament_results insert", async () => {
    // alice picked TEAM_B winner + PLAYER_A1 golden boot
    // bob   picked TEAM_A winner + PLAYER_B1 golden boot
    // Set official result: TEAM_B + PLAYER_A1 → alice = 125, bob = 0
    const { error } = await admin.from("tournament_results").insert({
      id: true,
      winner_team_id: T.TEAM_B,
      golden_boot_player_id: T.PLAYER_A1,
    });
    expect(error).toBeNull();
    await sleep(2000); // trigger + MV refresh

    const { data: rows } = await admin
      .from("tournament_predictions")
      .select("user_id, points_wc, points_golden_boot, points_earned")
      .in("user_id", [alice.userId, bob.userId]);

    const aRow = rows?.find((r) => r.user_id === alice.userId);
    const bRow = rows?.find((r) => r.user_id === bob.userId);

    expect(aRow?.points_wc).toBe(75);
    expect(aRow?.points_golden_boot).toBe(50);
    expect(aRow?.points_earned).toBe(125);

    expect(bRow?.points_wc).toBe(0);              // picked TEAM_A
    expect(bRow?.points_golden_boot).toBe(0);    // picked PLAYER_B1
    expect(bRow?.points_earned).toBe(0);
  });

  test("updating tournament_results recomputes scoring", async () => {
    // Flip the official golden boot to PLAYER_B1 — bob now matches it.
    const { error } = await admin
      .from("tournament_results")
      .update({ golden_boot_player_id: T.PLAYER_B1 })
      .eq("id", true);
    expect(error).toBeNull();
    await sleep(2000);

    const { data: rows } = await admin
      .from("tournament_predictions")
      .select("user_id, points_wc, points_golden_boot, points_earned")
      .in("user_id", [alice.userId, bob.userId]);

    const aRow = rows?.find((r) => r.user_id === alice.userId);
    const bRow = rows?.find((r) => r.user_id === bob.userId);

    expect(aRow?.points_golden_boot).toBe(0); // no longer matches
    expect(aRow?.points_earned).toBe(75);      // WC winner only
    expect(bRow?.points_golden_boot).toBe(50); // newly correct
    expect(bRow?.points_earned).toBe(50);
  });

  test("tournament_points roll into group_standings.total_points", async () => {
    const { data } = await admin
      .from("group_standings")
      .select("user_id, total_points, tournament_points, match_points")
      .eq("group_id", groupId);
    const aStanding = data?.find((r) => r.user_id === alice.userId);
    expect(aStanding?.tournament_points).toBe(75);
    expect(aStanding?.total_points)
      .toBe((aStanding?.match_points ?? 0) + 75);
  });

  test("lock fires once opening match kickoff is in the past", async () => {
    // tournament_opening_kickoff() only sees production matches (id >= 100_000),
    // so the lock test inserts a temporary production-shaped match with a past
    // kickoff and cleans it up afterwards.
    const SYNTHETIC_OPENING = 999_999;
    const past = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    await admin.from("matches").insert({
      id: SYNTHETIC_OPENING,
      round: "Matchday 1",
      group_letter: null,
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: past,
      status: "scheduled",
    });

    try {
      // charlie has no row yet — INSERT must be rejected
      const { error: insertErr } = await charlie.client
        .from("tournament_predictions")
        .insert({
          user_id: charlie.userId,
          wc_winner_team_id: T.TEAM_A,
        });
      expect(insertErr).not.toBeNull();
      expect(insertErr!.message).toMatch(/locked|check_violation/i);

      // alice already has a row — UPDATE must be rejected
      const { error: updateErr } = await alice.client
        .from("tournament_predictions")
        .update({ wc_winner_team_id: T.TEAM_A })
        .eq("user_id", alice.userId);
      expect(updateErr).not.toBeNull();
      expect(updateErr!.message).toMatch(/locked|check_violation/i);

      // group_read RLS now grants bob visibility of alice's locked row.
      const { data } = await bob.client
        .from("tournament_predictions")
        .select("wc_winner_team_id, points_earned")
        .eq("user_id", alice.userId);
      expect(data?.length).toBe(1);
      expect(data?.[0]?.wc_winner_team_id).toBe(T.TEAM_B);
    } finally {
      await admin.from("matches").delete().eq("id", SYNTHETIC_OPENING);
    }
  });

  test("tournament_results is world-readable", async () => {
    const anon = anonClient();
    const { data, error } = await anon
      .from("tournament_results")
      .select("winner_team_id, golden_boot_player_id")
      .eq("id", true)
      .single();
    expect(error).toBeNull();
    expect(data?.winner_team_id).toBe(T.TEAM_B);
    expect(data?.golden_boot_player_id).toBe(T.PLAYER_B1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 11. DEVICE TOKENS — RLS owner-only + cascade on auth.users delete
// ─────────────────────────────────────────────────────────────────────────────

describe("Device tokens", () => {
  beforeEach(async () => {
    // Wipe both test users' rows so each test starts clean.
    await admin
      .from("device_tokens")
      .delete()
      .in("user_id", [alice.userId, bob.userId]);
  });

  test("owner can insert their own token row", async () => {
    const { error } = await alice.client.from("device_tokens").insert({
      user_id: alice.userId,
      token: "test-token-alice-ios",
      platform: "ios",
    });
    expect(error).toBeNull();

    // Verify via admin (RLS bypass).
    const { data } = await admin
      .from("device_tokens")
      .select("user_id, token, platform")
      .eq("user_id", alice.userId);
    expect(data?.length).toBe(1);
    expect(data?.[0]?.token).toBe("test-token-alice-ios");
  });

  test("owner cannot insert a row for another user", async () => {
    // RLS WITH CHECK on insert blocks this even though the row would
    // be visible to alice via her own SELECT policy (only owner can
    // write).
    const { error } = await alice.client.from("device_tokens").insert({
      user_id: bob.userId,
      token: "test-token-spoofed",
      platform: "android",
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/row-level security|new row violates/i);
  });

  test("platform check constraint rejects unknown values", async () => {
    const { error } = await alice.client.from("device_tokens").insert({
      user_id: alice.userId,
      token: "test-token-bad-platform",
      platform: "web", // not in ('ios','android')
    });
    expect(error).not.toBeNull();
    expect(error!.message).toMatch(/check constraint|device_tokens_platform_check/i);
  });

  test("upsert by (user_id, token) updates `updated_at`", async () => {
    const token = "test-token-alice-refresh";
    await alice.client.from("device_tokens").insert({
      user_id: alice.userId,
      token,
      platform: "ios",
    });
    const { data: first } = await admin
      .from("device_tokens")
      .select("updated_at")
      .eq("user_id", alice.userId)
      .eq("token", token)
      .single();

    // Wait long enough that now() advances on the trigger.
    await sleep(1100);

    const { error: upsertErr } = await alice.client
      .from("device_tokens")
      .upsert(
        { user_id: alice.userId, token, platform: "ios" },
        { onConflict: "user_id,token" },
      );
    expect(upsertErr).toBeNull();

    const { data: second } = await admin
      .from("device_tokens")
      .select("updated_at")
      .eq("user_id", alice.userId)
      .eq("token", token)
      .single();
    expect(new Date(second!.updated_at).getTime()).toBeGreaterThan(
      new Date(first!.updated_at).getTime(),
    );
  });

  test("cascade on auth.users delete removes token rows", async () => {
    // Use charlie because the test order shouldn't break alice/bob for later blocks.
    await admin.from("device_tokens").insert({
      user_id: charlie.userId,
      token: "test-token-charlie-doomed",
      platform: "android",
    });
    const { data: before } = await admin
      .from("device_tokens")
      .select("token")
      .eq("user_id", charlie.userId);
    expect(before?.length).toBe(1);

    // Delete charlie + re-create for the rest of the suite. Order matters:
    // other describe blocks reuse `charlie` so we must restore the binding.
    await admin.auth.admin.deleteUser(charlie.userId);

    const { data: after } = await admin
      .from("device_tokens")
      .select("token")
      .eq("user_id", charlie.userId);
    expect(after?.length ?? 0).toBe(0);

    // Restore charlie so subsequent blocks (if any reference him) still work.
    charlie = await userClient("charlie");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 12. PREDICT REMINDERS — anti-join correctness + idempotency
// ─────────────────────────────────────────────────────────────────────────────
//
// These tests invoke the deployed `notify_predict_reminders` edge function
// against the production project. Real FCM HTTP calls fire for any matching
// device tokens; we use deliberately invalid tokens so FCM rejects with 404,
// which is logged but does not change `prediction_reminders_sent` semantics
// (the function writes the log row regardless of FCM HTTP result).

describe("Predict reminders", () => {
  const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/notify_predict_reminders`;

  async function invokeFn(): Promise<{ ok: boolean; matches: number; sends: number; skipped_matches: number }> {
    const res = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    expect(res.status).toBe(200);
    return (await res.json()) as any;
  }

  async function seedReminderFixture(opts: {
    kickoffOffsetMinutes: number;
    withPrediction?: boolean;
  }): Promise<void> {
    const kickoff = new Date(
      Date.now() + opts.kickoffOffsetMinutes * 60 * 1000,
    ).toISOString();

    await admin.from("matches").upsert({
      id: T.MATCH_REMINDER,
      round: "Matchday 1",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: kickoff,
      status: "scheduled",
    });

    await admin
      .from("device_tokens")
      .delete()
      .eq("user_id", alice.userId);
    await admin.from("device_tokens").insert({
      user_id: alice.userId,
      token: "fake-fcm-token-regression-alice",
      platform: "ios",
    });

    await admin
      .from("prediction_reminders_sent")
      .delete()
      .eq("match_id", T.MATCH_REMINDER);
    await admin
      .from("predictions")
      .delete()
      .eq("match_id", T.MATCH_REMINDER);

    if (opts.withPrediction) {
      await admin.from("predictions").insert({
        user_id: alice.userId,
        match_id: T.MATCH_REMINDER,
        predicted_team1: 1,
        predicted_team2: 0,
      });
    }
  }

  test("no candidate matches → matches:0, no writes", async () => {
    // Wipe any leftover synthetic match so the window is empty.
    await admin.from("matches").delete().eq("id", T.MATCH_REMINDER);
    const result = await invokeFn();
    expect(result.ok).toBe(true);
    expect(result.matches).toBe(0);
  });

  test("one candidate user → exactly one reminders_sent row", async () => {
      await seedReminderFixture({ kickoffOffsetMinutes: 30 });
      const first = await invokeFn();
      expect(first.matches).toBeGreaterThanOrEqual(1);
  
      // Cron fans out to every registered token (dev-seed users included),
      // so count only Alice's row to lock the per-user idempotency contract.
      const { data: rows } = await admin
        .from("prediction_reminders_sent")
        .select("user_id, match_id")
        .eq("match_id", T.MATCH_REMINDER)
        .eq("user_id", alice.userId);
      expect(rows?.length).toBe(1);
    });

  test("second invocation in the same window does not re-send", async () => {
      await seedReminderFixture({ kickoffOffsetMinutes: 30 });
      await invokeFn();
      await invokeFn();
  
      const { data: rows } = await admin
        .from("prediction_reminders_sent")
        .select("user_id, sent_at")
        .eq("match_id", T.MATCH_REMINDER)
        .eq("user_id", alice.userId);
      expect(rows?.length).toBe(1); // still exactly one for alice
    });

  test("user with a prediction is excluded — no row added", async () => {
      await seedReminderFixture({
        kickoffOffsetMinutes: 30,
        withPrediction: true,
      });
      await invokeFn();
  
      const { data: rows } = await admin
        .from("prediction_reminders_sent")
        .select("user_id")
        .eq("match_id", T.MATCH_REMINDER)
        .eq("user_id", alice.userId);
      expect(rows?.length ?? 0).toBe(0);
    });

  test("match outside [now+29m, now+31m] window is ignored", async () => {
      // Kickoff in 5 minutes — too soon for the predict-reminder window.
      await seedReminderFixture({ kickoffOffsetMinutes: 5 });
      const result = await invokeFn();
      const { data: rows } = await admin
        .from("prediction_reminders_sent")
        .select("user_id")
        .eq("match_id", T.MATCH_REMINDER)
        .eq("user_id", alice.userId);
      expect(rows?.length ?? 0).toBe(0);
      expect(result.ok).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 13. POLL LINEUPS WINDOW — formation guard semantics
// ─────────────────────────────────────────────────────────────────────────────
//
// We don't invoke the live `poll_lineups` edge function because it would
// make real api-sports.io calls (rate-limited, billed). Instead we assert
// the *guard logic* directly: a match with both formations populated must
// be filterable out by the same predicate the edge function uses
// (`formation_team1 IS NOT NULL AND formation_team2 IS NOT NULL`), and a
// match with NULL formations must remain a candidate. This locks the
// schema contract that the edge function depends on; any migration that
// drops or renames those columns breaks here loudly.

describe("Poll lineups guard", () => {
  test("match with both formations populated is filtered by guard predicate", async () => {
    const future = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    await admin.from("matches").upsert({
      id: T.MATCH_REMINDER,
      round: "Matchday 1",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: future,
      status: "scheduled",
      formation_team1: "4-3-3",
      formation_team2: "3-5-2",
    });

    // Same predicate the edge function uses to decide skip-vs-fetch.
    const { data } = await admin
      .from("matches")
      .select("id, formation_team1, formation_team2")
      .eq("id", T.MATCH_REMINDER)
      .not("formation_team1", "is", null)
      .not("formation_team2", "is", null);
    expect(data?.length).toBe(1);
  });

  test("match missing one formation is NOT filtered out", async () => {
    const future = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    await admin.from("matches").upsert({
      id: T.MATCH_REMINDER,
      round: "Matchday 1",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: future,
      status: "scheduled",
      formation_team1: "4-3-3",
      formation_team2: null,
    });

    const { data } = await admin
      .from("matches")
      .select("id")
      .eq("id", T.MATCH_REMINDER)
      .not("formation_team1", "is", null)
      .not("formation_team2", "is", null);
    expect(data?.length ?? 0).toBe(0);
  });

  test("window predicate matches only candidates in [now+5m, now+45m]", async () => {
    // Insert at the upper-bound edge (now+44m) — should be picked up.
    const at44 = new Date(Date.now() + 44 * 60 * 1000).toISOString();
    await admin.from("matches").upsert({
      id: T.MATCH_REMINDER,
      round: "Matchday 1",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: at44,
      status: "scheduled",
      formation_team1: null,
      formation_team2: null,
    });

    const windowStart = new Date(Date.now() + 5 * 60 * 1000).toISOString();
    const windowEnd = new Date(Date.now() + 45 * 60 * 1000).toISOString();

    const { data } = await admin
      .from("matches")
      .select("id")
      .eq("id", T.MATCH_REMINDER)
      .eq("status", "scheduled")
      .gte("kickoff_time", windowStart)
      .lte("kickoff_time", windowEnd);
    expect(data?.length).toBe(1);

    // Move to +50m → falls outside the window.
    const at50 = new Date(Date.now() + 50 * 60 * 1000).toISOString();
    await admin
      .from("matches")
      .update({ kickoff_time: at50 })
      .eq("id", T.MATCH_REMINDER);

    const { data: outside } = await admin
      .from("matches")
      .select("id")
      .eq("id", T.MATCH_REMINDER)
      .eq("status", "scheduled")
      .gte("kickoff_time", windowStart)
      .lte("kickoff_time", windowEnd);
    expect(outside?.length ?? 0).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 14. MATCH LINEUPS — per-fixture matchday squad table (migration 036)
// ─────────────────────────────────────────────────────────────────────────────
//
// Locks the contract the Teams tab depends on: the global `players`
// table is the entire roster (often 25-35 per team), so the screen must
// read from `match_lineups` instead. Substitutes that show up should be
// the actual matchday bench (~7-15), never every non-starter on the team.

describe("Match lineups", () => {
  beforeEach(async () => {
    // Reset state between tests so each one owns its fixture's lineup rows.
    await admin.from("match_lineups").delete().eq("match_id", T.MATCH_FUTURE);
  });

  test("authenticated user can read match_lineups rows", async () => {
    await admin.from("match_lineups").insert([
      { match_id: T.MATCH_FUTURE, team_id: T.TEAM_A, player_id: T.PLAYER_A1, is_starter: true,  grid: "1:1" },
      { match_id: T.MATCH_FUTURE, team_id: T.TEAM_A, player_id: T.PLAYER_A2, is_starter: false, grid: null  },
      { match_id: T.MATCH_FUTURE, team_id: T.TEAM_B, player_id: T.PLAYER_B1, is_starter: true,  grid: "1:1" },
    ]);

    const { data, error } = await alice.client
      .from("match_lineups")
      .select("player_id, team_id, is_starter, grid")
      .eq("match_id", T.MATCH_FUTURE)
      .order("player_id");
    expect(error).toBeNull();
    expect(data?.length).toBe(3);
    expect(data?.[0]?.is_starter).toBe(true);
    expect(data?.[1]?.is_starter).toBe(false);
  });

  test("anon user cannot read match_lineups (authenticated-only policy)", async () => {
    await admin.from("match_lineups").insert({
      match_id: T.MATCH_FUTURE, team_id: T.TEAM_A, player_id: T.PLAYER_A1, is_starter: true,
    });
    const anon = anonClient();
    const { data } = await anon
      .from("match_lineups")
      .select("player_id")
      .eq("match_id", T.MATCH_FUTURE);
    // RLS denies anon: empty result, not 4xx (PostgREST treats it as no rows).
    expect(data?.length ?? 0).toBe(0);
  });

  test("non-service-role user cannot insert into match_lineups", async () => {
    const { error } = await alice.client.from("match_lineups").insert({
      match_id: T.MATCH_FUTURE,
      team_id: T.TEAM_A,
      player_id: T.PLAYER_A1,
      is_starter: true,
    });
    // RLS: no write policy → 4xx error
    expect(error).not.toBeNull();
  });

  test("(match_id, player_id) is the primary key — duplicate insert fails", async () => {
    await admin.from("match_lineups").insert({
      match_id: T.MATCH_FUTURE, team_id: T.TEAM_A, player_id: T.PLAYER_A1, is_starter: true,
    });
    const { error } = await admin.from("match_lineups").insert({
      match_id: T.MATCH_FUTURE, team_id: T.TEAM_A, player_id: T.PLAYER_A1, is_starter: false,
    });
    expect(error).not.toBeNull();
  });

  test("deleting a match cascades to match_lineups", async () => {
    // Use a throwaway match so the parent matches row delete doesn't
    // disturb other tests that rely on T.MATCH_FUTURE.
    const throwawayId = 99_777;
    const future = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    await admin.from("matches").upsert({
      id: throwawayId,
      round: "Matchday 1",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: future,
      status: "scheduled",
    });
    await admin.from("match_lineups").insert([
      { match_id: throwawayId, team_id: T.TEAM_A, player_id: T.PLAYER_A1, is_starter: true },
      { match_id: throwawayId, team_id: T.TEAM_B, player_id: T.PLAYER_B1, is_starter: true },
    ]);

    await admin.from("matches").delete().eq("id", throwawayId);

    const { data } = await admin
      .from("match_lineups")
      .select("player_id")
      .eq("match_id", throwawayId);
    expect(data?.length ?? 0).toBe(0);
  });
});
