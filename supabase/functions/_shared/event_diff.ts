// Pure helpers for surgical sync of `match_events` against the
// api-sports.io events response.
//
// ── Why this exists ─────────────────────────────────────────────────
// The naive sync is `DELETE WHERE match_id=X; INSERT all`. That is
// idempotent and easy to reason about, but it emits `2N` WAL changes
// per poll cycle even when nothing actually changed. With Supabase
// Realtime subscribers watching the table, every poll fans out
// `2 × eventCount × subscribers` messages — the bulk of our realtime
// quota during the tournament.
//
// `diffEvents` reduces the steady-state case (no new goals / cards /
// subs since last poll) to ZERO writes. Only genuinely new rows
// insert; only genuinely removed rows delete. The legitimate VAR
// removal path (event vanishes between polls) still fires the
// migration-037 recompute trigger via the surgical DELETE.
//
// Multiset semantics: if api-sports returns two identical events
// (rare — e.g. two yellow cards same minute same player), and the DB
// has only one, we insert one more. Conversely, if the DB has two
// and the API returns one, we delete one.
//
// `player_name` is denormalized and intentionally NOT part of the
// signature — api-sports occasionally rewrites a display string and
// we don't want that to count as a "new event".

export interface ApiEventRow {
  match_id: number;
  minute: number | null;
  minute_extra: number | null;
  type: string;
  team_id: number | null;
  player_id: number | null;
  player_name: string | null;
  detail: string | null;
}

export interface DbEventRow extends ApiEventRow {
  id: number;
}

export interface EventDiff {
  toInsert: ApiEventRow[];
  toDelete: number[]; // primary keys
}

/// Stable signature for matching api rows against db rows. Excludes
/// `id` (db-only) and `player_name` (cosmetic).
export function signEvent(e: ApiEventRow): string {
  return [
    e.minute ?? "",
    e.minute_extra ?? "",
    e.type,
    e.team_id ?? "",
    e.player_id ?? "",
    e.detail ?? "",
  ].join("|");
}

/// Compute the minimum set of inserts + deletes that turn `existing`
/// into a multiset matching `incoming` (by signature).
///
/// Returns `{ toInsert: [], toDelete: [] }` when nothing changed —
/// the caller MUST short-circuit and skip writes in that case.
export function diffEvents(
  existing: ReadonlyArray<DbEventRow>,
  incoming: ReadonlyArray<ApiEventRow>,
): EventDiff {
  // Bucket existing rows by signature → queue of ids. Pop from the
  // queue as incoming rows match, so duplicates are handled.
  const bySig = new Map<string, number[]>();
  for (const e of existing) {
    const sig = signEvent(e);
    const ids = bySig.get(sig);
    if (ids) ids.push(e.id);
    else bySig.set(sig, [e.id]);
  }

  const toInsert: ApiEventRow[] = [];
  for (const e of incoming) {
    const sig = signEvent(e);
    const ids = bySig.get(sig);
    if (ids && ids.length > 0) {
      ids.pop(); // existing row claimed
    } else {
      toInsert.push(e);
    }
  }

  // Anything left in the queues is no longer reported by the API.
  const toDelete: number[] = [];
  for (const ids of bySig.values()) {
    for (const id of ids) toDelete.push(id);
  }

  return { toInsert, toDelete };
}
