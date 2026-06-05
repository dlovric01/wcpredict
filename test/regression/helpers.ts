/**
 * Test helpers: client creation, fixture insertion, teardown.
 *
 * Test data uses IDs >= 99_000 so they never clash with real BALLDONTLIE IDs.
 * All test auth users use the @wctest.invalid domain so cleanup is deterministic.
 */

import { createClient, SupabaseClient } from "@supabase/supabase-js";

// ─── Configuration ────────────────────────────────────────────────────────────

// Credentials MUST be supplied via env. There is no in-file fallback by
// design — committing keys (especially `service_role`) to a public repo
// is a one-way trip: rotating after exposure is the only real fix, so
// we forbid the literal here entirely.
//
// For a local Supabase stack (`supabase start`), copy values from
// `supabase status -o env`. For the live project, take them from the
// dashboard → Project Settings → API.
//
// Required: SUPABASE_REGRESSION_URL, SUPABASE_REGRESSION_ANON,
// SUPABASE_REGRESSION_SERVICE. Optional: nothing.
//
// Note: CLI v2.75+ signs the auth admin endpoint with ES256, so the
// legacy HS256 keys printed by `supabase status` work for PostgREST
// but not for `auth.admin.createUser` against a fresh local stack —
// sign with the JWK private key in the `supabase_auth_<project>`
// container env (`GOTRUE_JWT_KEYS`).
function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(
      `[regression suite] missing env ${name}. ` +
      `Set SUPABASE_REGRESSION_URL/_ANON/_SERVICE before running bun test. ` +
      `Never commit live keys to this repo — rotate immediately if you do.`
    );
  }
  return v;
}

export const SUPABASE_URL  = requireEnv("SUPABASE_REGRESSION_URL");
export const ANON_KEY      = requireEnv("SUPABASE_REGRESSION_ANON");
export const SERVICE_KEY   = requireEnv("SUPABASE_REGRESSION_SERVICE");

// ─── Test constants ────────────────────────────────────────────────────────────

// Stable IDs for mock entities — use range 99_000+ to avoid BALLDONTLIE collisions
export const T = {
  // Teams
  TEAM_A: 99_001,
  TEAM_B: 99_002,
  // Players
  PLAYER_A1: 99_101, // plays for TEAM_A, will score
  PLAYER_A2: 99_102, // plays for TEAM_A, own-goal scorer
  PLAYER_B1: 99_111, // plays for TEAM_B
  // Matches
  MATCH_FUTURE: 99_201, // kickoff far in future (predictions open)
  MATCH_PAST: 99_202,   // kickoff in the past (predictions should be locked)
  MATCH_SCORING: 99_203, // used for scoring engine tests
  MATCH_ET: 99_204,     // extra-time / penalties test
  MATCH_KO: 99_205,     // future QF knockout match for booster tests
  MATCH_REMINDER: 99_206, // synthetic match in [now+29m, now+31m] for reminder flow
};

export const TEST_DOMAIN = "wctest.invalid";

export function testEmail(name: string): string {
  return `${name}@${TEST_DOMAIN}`;
}

export const TEST_PASSWORD = "TestPass99!";

// ─── Client factories ─────────────────────────────────────────────────────────

/** Unauthenticated anon client */
export function anonClient(): SupabaseClient {
  return createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Service-role client — bypasses all RLS */
export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Create or retrieve a test user via admin API; sign in and return authenticated client */
export async function userClient(
  name: string,
  adm: SupabaseClient = adminClient()
): Promise<{ client: SupabaseClient; userId: string }> {
  const email = testEmail(name);

  // Check if user already exists (admin list users, filter by email)
  const { data: existing } = await adm.auth.admin.listUsers();
  let userId: string | undefined = existing?.users.find((u) => u.email === email)?.id;

  if (!userId) {
    // Create via admin API — bypasses public rate-limit entirely
    const { data: created, error: createErr } = await adm.auth.admin.createUser({
      email,
      password: TEST_PASSWORD,
      user_metadata: { display_name: name },
      email_confirm: true, // mark email as confirmed so sign-in works immediately
    });
    if (createErr) throw new Error(`createUser(${name}): ${createErr.message}`);
    userId = created.user.id;
  }

  // Sign in via the anon client (creates a real session with JWT)
  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({ email, password: TEST_PASSWORD });
  if (error || !data.user) throw new Error(`signIn(${name}): ${error?.message}`);

  return { client, userId: data.user.id };
}

// ─── Static fixture insertion (service role) ─────────────────────────────────

export async function insertTestFixtures(admin: SupabaseClient): Promise<void> {
  // Teams
  await admin.from("teams").upsert([
    { id: T.TEAM_A, name: "Test Alpha", code: "TTA", flag_url: null, group_letter: "Z" },
    { id: T.TEAM_B, name: "Test Beta",  code: "TTB", flag_url: null, group_letter: "Z" },
  ]);

  // Players
  await admin.from("players").upsert([
    { id: T.PLAYER_A1, team_id: T.TEAM_A, name: "Alpha Striker", position: "FWD" },
    { id: T.PLAYER_A2, team_id: T.TEAM_A, name: "Alpha OG",      position: "DEF" },
    { id: T.PLAYER_B1, team_id: T.TEAM_B, name: "Beta Forward",  position: "FWD" },
  ]);

  // Matches
  const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();
  const past   = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();

  await admin.from("matches").upsert([
    {
      id: T.MATCH_FUTURE,
      round: "Matchday 1",
      group_letter: "Z",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: future,
      status: "scheduled",
    },
    {
      id: T.MATCH_PAST,
      round: "Matchday 1",
      group_letter: "Z",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: past,
      status: "scheduled",
    },
    {
      id: T.MATCH_SCORING,
      round: "Matchday 2",
      group_letter: "Z",
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: past,
      status: "scheduled",
    },
    {
      id: T.MATCH_ET,
      round: "QF",
      group_letter: null,
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: past,
      status: "scheduled",
    },
    {
      id: T.MATCH_KO,
      round: "QF",
      group_letter: null,
      team1_id: T.TEAM_A,
      team2_id: T.TEAM_B,
      kickoff_time: future,
      status: "scheduled",
    },
  ]);
}

// ─── Teardown ─────────────────────────────────────────────────────────────────

export async function teardownTestData(admin: SupabaseClient): Promise<void> {
  const matchIds = [
    T.MATCH_FUTURE,
    T.MATCH_PAST,
    T.MATCH_SCORING,
    T.MATCH_ET,
    T.MATCH_KO,
    T.MATCH_REMINDER,
    99_777, // throwaway used by "deleting a match cascades to match_lineups"
  ];

  // predictions → match_events → matches → players → teams (foreign key order)
  await admin.from("predictions").delete().in("match_id", matchIds);
  await admin.from("match_events").delete().in("match_id", matchIds);
  await admin.from("round_boosters").delete().in("match_id", matchIds);
  // Per-match lineup join table (migration 036). Cascades on match delete
  // anyway, but explicit wipe is fast and idempotent across reruns.
  await admin.from("match_lineups").delete().in("match_id", matchIds);
  // New post-MVP tables (cascade via auth.users covers them when test users
  // are deleted below, but explicit wipe by match id is faster and idempotent).
  await admin.from("prediction_reminders_sent").delete().in("match_id", matchIds);

  // Tournament tables (no match-id FK, scope by test-user IDs implicitly via
  // auth.users cascade; the singleton tournament_results is also wiped).
  await admin.from("tournament_results").delete().eq("id", true);

  // Delete test matches entirely. Leaving them in place (even with scores
  // reset) means their kickoff_time still pollutes production queries —
  // e.g. tournament_opening_kickoff() previously locked tournament
  // predictions because a leftover test fixture was the "earliest match".
  await admin.from("matches").delete().in("id", matchIds);

  // Delete test auth users (also cascades profiles, group memberships)
  const { data: users } = await admin.auth.admin.listUsers();
  const testUsers = (users?.users ?? []).filter((u) =>
    u.email?.endsWith(`@${TEST_DOMAIN}`)
  );
  for (const u of testUsers) {
    await admin.auth.admin.deleteUser(u.id);
  }

  // Delete any test groups (owned by now-deleted users should already be gone
  // via cascade, but belt-and-suspenders for invite_code uniqueness)
  await admin
    .from("groups")
    .delete()
    .like("name", "TEST_%");

  // Remove test players / teams last
  await admin
    .from("players")
    .delete()
    .in("id", [T.PLAYER_A1, T.PLAYER_A2, T.PLAYER_B1]);
  await admin
    .from("teams")
    .delete()
    .in("id", [T.TEAM_A, T.TEAM_B]);
}

// ─── Convenience assertions ───────────────────────────────────────────────────

export function assertNoError(
  result: { error: any },
  context: string
): void {
  if (result.error) {
    throw new Error(`${context}: ${result.error.message ?? JSON.stringify(result.error)}`);
  }
}

/** Pause to let DB triggers / materialized view refresh settle */
export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
