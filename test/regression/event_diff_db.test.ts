// Direct DB exercise of the signature diff against a real Postgres
// match_events table. Verifies the actual optimisation we claim:
//
//   1. Steady-state polls produce ZERO writes (no row touched).
//   2. New events insert exactly one new row.
//   3. Removed events delete exactly the affected row.
//   4. Migration-037 trigger still fires on the surgical insert/delete
//      when status='final' (no scoring drift).
//   5. updated_at on the matches row is NOT bumped by event syncs
//      (only by Phase A's diff-gated matches UPDATE).
//
// The pure helper tests in event_diff.test.ts prove the diff math.
// THIS file proves the helper + PostgREST + trigger pipeline behave
// as a unit against a real DB.

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  type ApiEventRow,
  type DbEventRow,
  diffEvents,
} from "../../supabase/functions/_shared/event_diff.ts";
import { adminClient } from "./helpers";

const MATCH_ID  = 100_950;
const TEAM_A    = 99_950;
const TEAM_B    = 99_951;
const PLAYER_A1 = 99_960;
const PLAYER_B1 = 99_961;

const admin = adminClient();

async function ensureTeam(id: number, code: string) {
  await admin.from("teams").upsert({ id, name: code, code, group_letter: "Z" });
}

async function ensurePlayer(id: number, teamId: number, name: string) {
  await admin.from("players").upsert({
    id, team_id: teamId, name, grid: "1:1", is_starter: true,
  });
}

async function loadEvents(): Promise<DbEventRow[]> {
  const { data, error } = await admin
    .from("match_events")
    .select("id, match_id, minute, minute_extra, type, team_id, player_id, player_name, detail")
    .eq("match_id", MATCH_ID);
  if (error) throw error;
  return (data ?? []) as DbEventRow[];
}

async function applyDiff(incoming: ApiEventRow[]): Promise<{ inserted: number; deleted: number }> {
  const existing = await loadEvents();
  const { toInsert, toDelete } = diffEvents(existing, incoming);
  if (toDelete.length > 0) {
    const { error } = await admin.from("match_events").delete().in("id", toDelete);
    if (error) throw error;
  }
  if (toInsert.length > 0) {
    const { error } = await admin.from("match_events").insert(toInsert);
    if (error) throw error;
  }
  return { inserted: toInsert.length, deleted: toDelete.length };
}

async function cleanup() {
  await admin.from("predictions").delete().eq("match_id", MATCH_ID);
  await admin.from("match_events").delete().eq("match_id", MATCH_ID);
  await admin.from("matches").delete().eq("id", MATCH_ID);
  await admin.from("players").delete().in("id", [PLAYER_A1, PLAYER_B1]);
  await admin.from("teams").delete().in("id", [TEAM_A, TEAM_B]);
}

beforeAll(async () => {
  await cleanup();
  await ensureTeam(TEAM_A, "ZZA");
  await ensureTeam(TEAM_B, "ZZB");
  await ensurePlayer(PLAYER_A1, TEAM_A, "Alpha Striker");
  await ensurePlayer(PLAYER_B1, TEAM_B, "Beta Forward");
});

afterAll(cleanup);

describe("event diff against live DB — write minimisation", () => {
  test("first poll: empty + empty → zero writes", async () => {
    const upsertRes = await admin.from("matches").upsert({
      id: MATCH_ID,
      team1_id: TEAM_A,
      team2_id: TEAM_B,
      kickoff_time: new Date(Date.now() - 30 * 60_000).toISOString(),
      round: "group",
      status: "live",
      score_ft_team1: 0,
      score_ft_team2: 0,
    });
    if (upsertRes.error) throw new Error(`matches upsert: ${upsertRes.error.message}`);

    const r = await applyDiff([]);
    expect(r.inserted).toBe(0);
    expect(r.deleted).toBe(0);

    const after = await loadEvents();
    expect(after).toHaveLength(0);
  });

  test("first goal: one insert", async () => {
    const goal1: ApiEventRow = {
      match_id: MATCH_ID, minute: 23, minute_extra: null, type: "goal",
      team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha Striker", detail: null,
    };
    const r = await applyDiff([goal1]);
    expect(r.inserted).toBe(1);
    expect(r.deleted).toBe(0);
  });

  test("steady-state polls (×20) on unchanged input: ZERO writes total", async () => {
    const stableSet: ApiEventRow[] = [{
      match_id: MATCH_ID, minute: 23, minute_extra: null, type: "goal",
      team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha Striker", detail: null,
    }];

    let totalWrites = 0;
    for (let i = 0; i < 20; i++) {
      const r = await applyDiff(stableSet);
      totalWrites += r.inserted + r.deleted;
    }
    expect(totalWrites).toBe(0);
  });

  test("player_name change alone is not a write", async () => {
    const renamed: ApiEventRow[] = [{
      match_id: MATCH_ID, minute: 23, minute_extra: null, type: "goal",
      team_id: TEAM_A, player_id: PLAYER_A1, player_name: "A. Striker (renamed)", detail: null,
    }];
    const r = await applyDiff(renamed);
    expect(r.inserted).toBe(0);
    expect(r.deleted).toBe(0);
  });

  test("VAR removes the goal: exactly one delete", async () => {
    const r = await applyDiff([]);
    expect(r.inserted).toBe(0);
    expect(r.deleted).toBe(1);

    const after = await loadEvents();
    expect(after).toHaveLength(0);
  });

  test("realistic 90-min match: 4 events spread across 60 polls → 4 inserts total", async () => {
    // Reset to zero state.
    await admin.from("match_events").delete().eq("match_id", MATCH_ID);

    const e1: ApiEventRow = { match_id: MATCH_ID, minute: 15, minute_extra: null, type: "goal",   team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha", detail: null };
    const e2: ApiEventRow = { match_id: MATCH_ID, minute: 42, minute_extra: null, type: "goal",   team_id: TEAM_B, player_id: PLAYER_B1, player_name: "Beta",  detail: null };
    const e3: ApiEventRow = { match_id: MATCH_ID, minute: 67, minute_extra: null, type: "goal",   team_id: TEAM_B, player_id: PLAYER_B1, player_name: "Beta",  detail: null };
    const e4: ApiEventRow = { match_id: MATCH_ID, minute: 88, minute_extra: null, type: "goal",   team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha", detail: null };

    // 60 polls; events accumulate at minutes 15, 42, 67, 88.
    let writes = 0;
    for (let pollMinute = 1; pollMinute <= 60; pollMinute++) {
      const seen: ApiEventRow[] = [];
      // api-sports reports an event from the minute it happens onward.
      // We model 1.5x real-time poll cadence (60 polls / 90 match-min).
      const matchMinute = Math.floor(pollMinute * 1.5);
      if (matchMinute >= 15) seen.push(e1);
      if (matchMinute >= 42) seen.push(e2);
      if (matchMinute >= 67) seen.push(e3);
      if (matchMinute >= 88) seen.push(e4);
      const r = await applyDiff(seen);
      writes += r.inserted + r.deleted;
    }
    expect(writes).toBe(4); // exactly one insert per new event, zero deletes
  });

  test("trigger-037 still fires on surgical delete when status=final (no scoring drift)", async () => {
    // Reset events + matches; load a real prediction so we can observe
    // scoring movement under the trigger.
    await admin.from("match_events").delete().eq("match_id", MATCH_ID);
    await admin.from("predictions").delete().eq("match_id", MATCH_ID);

    // Get-or-create test user. If a prior run left it behind we reuse.
    const email = "diff_db_alice@wctest.invalid";
    const { data: existing } = await admin.auth.admin.listUsers();
    let userId = existing?.users.find((u) => u.email === email)?.id;
    if (!userId) {
      const { data: created, error } = await admin.auth.admin.createUser({
        email, password: "TestPass99!", email_confirm: true,
      });
      if (error) throw new Error(`createUser: ${error.message}`);
      userId = created?.user?.id;
    }
    if (!userId) throw new Error("could not resolve test user id");

    await admin.from("matches").update({
      kickoff_time: new Date(Date.now() + 24 * 3600_000).toISOString(),
      status: "scheduled",
      score_ft_team1: null, score_ft_team2: null,
    }).eq("id", MATCH_ID);

    await admin.from("predictions").insert({
      user_id: userId,
      match_id: MATCH_ID,
      predicted_team1: 2,
      predicted_team2: 1,
      predicted_first_team_id: TEAM_A,
      predicted_scorer_id: PLAYER_A1,
    });

    // Kickoff in past + live + goals
    await admin.from("matches").update({
      kickoff_time: new Date(Date.now() - 3600_000).toISOString(),
      status: "live",
    }).eq("id", MATCH_ID);

    const events: ApiEventRow[] = [
      { match_id: MATCH_ID, minute: 15, minute_extra: null, type: "goal", team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha", detail: null },
      { match_id: MATCH_ID, minute: 70, minute_extra: null, type: "goal", team_id: TEAM_B, player_id: PLAYER_B1, player_name: "Beta",  detail: null },
      { match_id: MATCH_ID, minute: 88, minute_extra: null, type: "goal", team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha", detail: null },
    ];
    await applyDiff(events);

    // Flip to final → scoring trigger runs.
    await admin.from("matches").update({
      status: "final",
      score_ft_team1: 2,
      score_ft_team2: 1,
    }).eq("id", MATCH_ID);
    await new Promise((r) => setTimeout(r, 2000));

    const { data: before } = await admin
      .from("predictions")
      .select("points_match, points_first_team, points_goalscorer, points_earned")
      .eq("match_id", MATCH_ID).eq("user_id", userId).single();
    expect(before?.points_match).toBe(5);
    expect(before?.points_first_team).toBe(2);
    expect(before?.points_goalscorer).toBe(8);

    // VAR cancels the 15' goal via the SURGICAL diff path (this is the
    // path that distinguishes the new code from the old wipe-reinsert).
    // diffEvents must produce exactly one delete; the trigger must
    // recompute scoring against the remaining events.
    const withoutGoal1: ApiEventRow[] = events.slice(1);
    const r = await applyDiff(withoutGoal1);
    expect(r.inserted).toBe(0);
    expect(r.deleted).toBe(1);
    await new Promise((r) => setTimeout(r, 2000));

    const { data: after } = await admin
      .from("predictions")
      .select("points_match, points_first_team, points_goalscorer, points_earned")
      .eq("match_id", MATCH_ID).eq("user_id", userId).single();

    // TEAM_B scored first now → predicted_first_team_id=TEAM_A misses.
    expect(after?.points_first_team).toBe(0);
    // PLAYER_A1 still scored at 88' → goalscorer bonus survives.
    expect(after?.points_goalscorer).toBe(8);
    // Match result still 2-1 → exact match still hits.
    expect(after?.points_match).toBe(5);

    // Cleanup created user.
    await admin.auth.admin.deleteUser(userId);
  });

  test("matches.updated_at is NOT bumped by event syncs", async () => {
    // Get baseline updated_at, run several event-only diff cycles, confirm
    // the matches row was not touched. (Production code keeps the matches
    // UPDATE separate from the events UPDATE — Phase A only writes when
    // material match fields changed.)
    await admin.from("match_events").delete().eq("match_id", MATCH_ID);
    await admin.from("matches").update({
      status: "live",
      score_ft_team1: 1,
      score_ft_team2: 1,
    }).eq("id", MATCH_ID);

    const { data: before } = await admin
      .from("matches").select("updated_at").eq("id", MATCH_ID).single();

    const stable: ApiEventRow[] = [
      { match_id: MATCH_ID, minute: 30, minute_extra: null, type: "goal", team_id: TEAM_A, player_id: PLAYER_A1, player_name: "Alpha", detail: null },
    ];
    await applyDiff(stable);
    for (let i = 0; i < 5; i++) await applyDiff(stable);

    const { data: after } = await admin
      .from("matches").select("updated_at").eq("id", MATCH_ID).single();

    expect(after?.updated_at).toBe(before?.updated_at);
  });
});
