// Pure unit tests for the signature-based match_events diff used by
// `supabase/functions/poll_live_matches`. No Supabase / network — runs
// in milliseconds and exercises the steady-state / VAR / replay /
// duplicate-signature cases that drive the realtime-message budget.

import { describe, test, expect } from "bun:test";
import {
  type ApiEventRow,
  type DbEventRow,
  signEvent,
  diffEvents,
} from "../../supabase/functions/_shared/event_diff.ts";

function db(id: number, e: Partial<ApiEventRow>): DbEventRow {
  return {
    id,
    match_id: e.match_id ?? 1,
    minute: e.minute ?? null,
    minute_extra: e.minute_extra ?? null,
    type: e.type ?? "goal",
    team_id: e.team_id ?? null,
    player_id: e.player_id ?? null,
    player_name: e.player_name ?? null,
    detail: e.detail ?? null,
  };
}

function api(e: Partial<ApiEventRow>): ApiEventRow {
  return {
    match_id: e.match_id ?? 1,
    minute: e.minute ?? null,
    minute_extra: e.minute_extra ?? null,
    type: e.type ?? "goal",
    team_id: e.team_id ?? null,
    player_id: e.player_id ?? null,
    player_name: e.player_name ?? null,
    detail: e.detail ?? null,
  };
}

describe("signEvent", () => {
  test("includes all identifying fields", () => {
    const sig = signEvent(api({
      minute: 23, minute_extra: 1, type: "goal",
      team_id: 7, player_id: 99, detail: null,
    }));
    expect(sig).toBe("23|1|goal|7|99|");
  });

  test("ignores player_name (cosmetic only)", () => {
    const a = signEvent(api({ player_id: 1, player_name: "Alice" }));
    const b = signEvent(api({ player_id: 1, player_name: "Renamed" }));
    expect(a).toBe(b);
  });

  test("null fields render as empty separators (no NaN/undefined leakage)", () => {
    expect(signEvent(api({}))).toBe("||goal|||");
  });

  test("distinguishes type/detail combos", () => {
    const yellow = signEvent(api({ type: "yellow", minute: 50 }));
    const red    = signEvent(api({ type: "red",    minute: 50 }));
    expect(yellow).not.toBe(red);
  });
});

describe("diffEvents — steady state", () => {
  test("identical sets produce empty diff (the critical optimisation)", () => {
    const existing = [
      db(1, { minute: 23, type: "goal", team_id: 7, player_id: 99 }),
      db(2, { minute: 67, type: "yellow", team_id: 8, player_id: 33 }),
    ];
    const incoming = [
      api({ minute: 23, type: "goal", team_id: 7, player_id: 99 }),
      api({ minute: 67, type: "yellow", team_id: 8, player_id: 33 }),
    ];
    const { toInsert, toDelete } = diffEvents(existing, incoming);
    expect(toInsert).toEqual([]);
    expect(toDelete).toEqual([]);
  });

  test("empty + empty = empty diff", () => {
    expect(diffEvents([], [])).toEqual({ toInsert: [], toDelete: [] });
  });

  test("re-ordering does not produce spurious writes", () => {
    const existing = [
      db(1, { minute: 23, type: "goal", player_id: 99 }),
      db(2, { minute: 67, type: "yellow", player_id: 33 }),
    ];
    const incoming = [
      api({ minute: 67, type: "yellow", player_id: 33 }),
      api({ minute: 23, type: "goal", player_id: 99 }),
    ];
    expect(diffEvents(existing, incoming)).toEqual({ toInsert: [], toDelete: [] });
  });

  test("player_name change alone is not a diff (denormalised cosmetic)", () => {
    const existing = [db(1, { minute: 23, player_id: 99, player_name: "Alpha Old" })];
    const incoming = [api({ minute: 23, player_id: 99, player_name: "Alpha New" })];
    expect(diffEvents(existing, incoming)).toEqual({ toInsert: [], toDelete: [] });
  });
});

describe("diffEvents — new events arrive", () => {
  test("single new goal: one insert, zero deletes", () => {
    const existing = [db(1, { minute: 23, type: "goal", player_id: 99 })];
    const newGoal = api({ minute: 67, type: "goal", player_id: 33 });
    const { toInsert, toDelete } = diffEvents(existing, [
      api({ minute: 23, type: "goal", player_id: 99 }),
      newGoal,
    ]);
    expect(toDelete).toEqual([]);
    expect(toInsert).toEqual([newGoal]);
  });

  test("first goal in a previously-empty match", () => {
    const newGoal = api({ minute: 12, type: "goal", player_id: 1 });
    const { toInsert, toDelete } = diffEvents([], [newGoal]);
    expect(toDelete).toEqual([]);
    expect(toInsert).toEqual([newGoal]);
  });
});

describe("diffEvents — VAR / corrections", () => {
  test("VAR removes a goal: one delete, zero inserts", () => {
    const removedId = 7;
    const existing = [
      db(7, { minute: 23, type: "goal", player_id: 99 }),
      db(8, { minute: 67, type: "yellow", player_id: 33 }),
    ];
    const incoming = [api({ minute: 67, type: "yellow", player_id: 33 })];
    const { toInsert, toDelete } = diffEvents(existing, incoming);
    expect(toInsert).toEqual([]);
    expect(toDelete).toEqual([removedId]);
  });

  test("event detail changed (goal → own goal): delete + insert", () => {
    const existing = [db(7, { minute: 23, type: "goal", player_id: 99, detail: null })];
    const incoming = [api({ minute: 23, type: "goal", player_id: 99, detail: "own_goal" })];
    const { toInsert, toDelete } = diffEvents(existing, incoming);
    expect(toDelete).toEqual([7]);
    expect(toInsert).toHaveLength(1);
    expect(toInsert[0].detail).toBe("own_goal");
  });

  test("clear all (cancelled match): delete every existing id", () => {
    const existing = [db(1, {}), db(2, {}), db(3, {})];
    const { toInsert, toDelete } = diffEvents(existing, []);
    expect(toInsert).toEqual([]);
    expect(toDelete.sort()).toEqual([1, 2, 3]);
  });
});

describe("diffEvents — duplicate signatures (multiset semantics)", () => {
  test("two identical incoming events match two existing", () => {
    const existing = [
      db(10, { minute: 50, type: "yellow", player_id: 5 }),
      db(11, { minute: 50, type: "yellow", player_id: 5 }),
    ];
    const incoming = [
      api({ minute: 50, type: "yellow", player_id: 5 }),
      api({ minute: 50, type: "yellow", player_id: 5 }),
    ];
    expect(diffEvents(existing, incoming)).toEqual({ toInsert: [], toDelete: [] });
  });

  test("one existing, two incoming: insert the extra", () => {
    const existing = [db(10, { minute: 50, type: "yellow", player_id: 5 })];
    const incoming = [
      api({ minute: 50, type: "yellow", player_id: 5 }),
      api({ minute: 50, type: "yellow", player_id: 5 }),
    ];
    const { toInsert, toDelete } = diffEvents(existing, incoming);
    expect(toDelete).toEqual([]);
    expect(toInsert).toHaveLength(1);
  });

  test("two existing, one incoming: delete the extra", () => {
    const existing = [
      db(10, { minute: 50, type: "yellow", player_id: 5 }),
      db(11, { minute: 50, type: "yellow", player_id: 5 }),
    ];
    const incoming = [api({ minute: 50, type: "yellow", player_id: 5 })];
    const { toInsert, toDelete } = diffEvents(existing, incoming);
    expect(toInsert).toEqual([]);
    expect(toDelete).toHaveLength(1);
    // Either id is acceptable — semantics is "remove one of the duplicates".
    expect([10, 11]).toContain(toDelete[0]);
  });
});

describe("diffEvents — realistic poll sequence", () => {
  test("90-minute match with 3 goals: only inserts fire when goals are scored", () => {
    // Minute 0: empty state, no events yet.
    let existing: DbEventRow[] = [];
    let nextId = 1;

    const applyDiff = (incoming: ApiEventRow[]) => {
      const { toInsert, toDelete } = diffEvents(existing, incoming);
      existing = existing
        .filter((r) => !toDelete.includes(r.id))
        .concat(toInsert.map((r) => ({ ...r, id: nextId++ })));
      return { toInsert, toDelete };
    };

    // 30 idle polls (0-30 min, nothing scored) — all no-op.
    for (let i = 0; i < 30; i++) {
      const r = applyDiff([]);
      expect(r.toInsert).toEqual([]);
      expect(r.toDelete).toEqual([]);
    }

    // Goal at 23'.
    const goal1 = api({ minute: 23, type: "goal", team_id: 7, player_id: 99 });
    let r = applyDiff([goal1]);
    expect(r.toInsert).toEqual([goal1]);
    expect(r.toDelete).toEqual([]);

    // 20 idle polls (24-43 min) — no-op.
    for (let i = 0; i < 20; i++) {
      r = applyDiff([goal1]);
      expect(r.toInsert).toEqual([]);
      expect(r.toDelete).toEqual([]);
    }

    // Two more goals + a yellow card.
    const goal2 = api({ minute: 55, type: "goal", team_id: 8, player_id: 33 });
    const yellow = api({ minute: 67, type: "yellow", team_id: 7, player_id: 99 });
    const goal3 = api({ minute: 88, type: "goal", team_id: 8, player_id: 33 });
    r = applyDiff([goal1, goal2, yellow, goal3]);
    expect(r.toInsert).toEqual([goal2, yellow, goal3]);
    expect(r.toDelete).toEqual([]);

    // VAR review at 89: yellow card was wrong.
    r = applyDiff([goal1, goal2, goal3]);
    expect(r.toInsert).toEqual([]);
    expect(r.toDelete).toHaveLength(1);

    // Final whistle polls — no-op.
    for (let i = 0; i < 5; i++) {
      r = applyDiff([goal1, goal2, goal3]);
      expect(r.toInsert).toEqual([]);
      expect(r.toDelete).toEqual([]);
    }

    // Total writes across all 56 polls: 4 inserts + 1 delete = 5 writes.
    // Vs the old delete-then-insert: 56 × (Nexisting + Nincoming) ≈ 200+
    // writes per match per minute. Order-of-magnitude reduction.
  });
});
