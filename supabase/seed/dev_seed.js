/**
 * WC2026 Predict — Dev Seed (v3)
 *
 * Hand-crafted prediction matrix (all 16 Matchday 1 games) plus auxiliary
 * fixtures that exercise the post-MVP features:
 *
 *   • device_tokens          — one fake FCM token per dev user (platform
 *                              alternates ios/android). Lets `notify_predict_reminders`
 *                              anti-join logic be exercised locally without
 *                              standing up real devices. Tokens are
 *                              deliberately invalid (FCM 404s) so no real
 *                              push fires.
 *   • formations             — two finalised matches get `formation_team1`
 *                              and `formation_team2` populated so the Teams
 *                              tab renders a roster; the rest keep NULL so
 *                              the "lineups available 45 min before
 *                              kickoff" placeholder is also exercisable.
 *   • prediction_reminders   — one synthetic log row for a finalised match
 *                              demonstrates the schema and lets the
 *                              reminder UI smoke-test idempotency.
 *   • Multi-user same-match  — Matchday-2 + 3 predictions cover every dev
 *                              user, so the OTHERS tab has rows on first
 *                              boot for any upcoming match.
 *
 * Expected standings (verified against compute_match_scoring logic):
 *   Alice   120 pts  — careful analyst, nails exact scores
 *   Bob      95 pts  — aggressive scorer picker, big pts when right
 *   Danijel  69 pts  — decent direction, misses close calls
 *   Charlie  31 pts  — picks underdogs, lucky on 0-0 draws
 *
 * Run:  node supabase/seed/dev_seed.js
 * Safe to re-run: cleans existing dev data first.
 */

const https = require("https");

const URL  = "https://txziwjxvfprjilfyibol.supabase.co";
const ANON_KEY = "REDACTED-ANON-JWT";
const SERVICE_KEY = "REDACTED-SERVICE-ROLE-JWT";

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : undefined;
    const opts = {
      hostname: "txziwjxvfprjilfyibol.supabase.co",
      path,
      method,
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
        ...(payload ? { "Content-Length": Buffer.byteLength(payload) } : {}),
      },
    };
    const r = https.request(opts, (res) => {
      let d = "";
      res.on("data", (c) => (d += c));
      res.on("end", () => {
        try { resolve({ status: res.statusCode, body: d ? JSON.parse(d) : null }); }
        catch { resolve({ status: res.statusCode, body: d }); }
      });
    });
    r.on("error", reject);
    if (payload) r.write(payload);
    r.end();
  });
}

const get  = (path)        => req("GET",    path);
const post = (path, body)  => req("POST",   path, body);
const patch = (path, body) => req("PATCH",  path, body);
const del  = (path)        => req("DELETE", path);

async function authPost(path, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const opts = {
      hostname: "txziwjxvfprjilfyibol.supabase.co",
      path: `/auth/v1/admin/${path}`,
      method: "POST",
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload),
      },
    };
    const r = https.request(opts, (res) => {
      let d = "";
      res.on("data", (c) => (d += c));
      res.on("end", () => resolve({ status: res.statusCode, body: JSON.parse(d) }));
    });
    r.on("error", reject);
    r.write(payload);
    r.end();
  });
}

async function authGet(path) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: "txziwjxvfprjilfyibol.supabase.co",
      path: `/auth/v1/admin/${path}`,
      method: "GET",
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    };
    const r = https.request(opts, (res) => {
      let d = "";
      res.on("data", (c) => (d += c));
      res.on("end", () => resolve({ status: res.statusCode, body: JSON.parse(d) }));
    });
    r.on("error", reject);
    r.end();
  });
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

// ─── Constants ────────────────────────────────────────────────────────────────

const DEV_PASSWORD = "DevPass2026!";
const DEV_DOMAIN   = "wcpredict.dev";

const DEV_USERS = [
  { name: "danijel",  display: "Danijel" },
  { name: "alice",    display: "Alice" },
  { name: "bob",      display: "Bob" },
  { name: "charlie",  display: "Charlie" },
];

// ─── Match results for all 16 finalized Matchday 1 games ─────────────────────
//
// Actual scores, team IDs, and goal scorer player IDs
// (only set where events have non-null player_id).

const FINAL_MATCHES = [
  // id         t1Id   t2Id   ft1 ft2  scorer1(t1) scorer2(t2)
  { id: 1489369, t1: 16,   t2: 1531, ft1: 2, ft2: 1, scorerT1: 248,  scorerT2: null  }, // MEX 2-1 SOU
  { id: 1538999, t1: 17,   t2: 770,  ft1: 1, ft2: 0, scorerT1: 186,  scorerT2: null  }, // SKO 1-0 CZE
  { id: 1539000, t1: 5529, t2: 1113, ft1: 0, ft2: 0, scorerT1: null, scorerT2: null  }, // CAN 0-0 BOS
  { id: 1489370, t1: 2384, t2: 2380, ft1: 3, ft2: 1, scorerT1: null, scorerT2: null  }, // USA 3-1 PAR
  { id: 1489373, t1: 1569, t2: 15,   ft1: 1, ft2: 1, scorerT1: null, scorerT2: 5     }, // QAT 1-1 SWI (Akanji scored for SWI at min65)
  { id: 1489371, t1: 6,    t2: 31,   ft1: 2, ft2: 0, scorerT1: 257,  scorerT2: null  }, // BRA 2-0 MOR
  { id: 1489372, t1: 2386, t2: 1108, ft1: 1, ft2: 2, scorerT1: null, scorerT2: null  }, // HAI 1-2 SCO
  { id: 1539001, t1: 20,   t2: 777,  ft1: 0, ft2: 1, scorerT1: null, scorerT2: null  }, // AUS 0-1 TÜR
  { id: 1489374, t1: 25,   t2: 5530, ft1: 2, ft2: 2, scorerT1: null, scorerT2: null  }, // GER 2-2 CUR
  { id: 1489376, t1: 1118, t2: 12,   ft1: 1, ft2: 0, scorerT1: 247,  scorerT2: null  }, // NET 1-0 JAP
  { id: 1489375, t1: 1501, t2: 2382, ft1: 3, ft2: 2, scorerT1: null, scorerT2: null  }, // IVO 3-2 ECU
  { id: 1539002, t1: 5,    t2: 28,   ft1: 0, ft2: 0, scorerT1: null, scorerT2: null  }, // SWE 0-0 TUN
  { id: 1489380, t1: 9,    t2: 1533, ft1: 1, ft2: 0, scorerT1: 44,   scorerT2: null  }, // SPA 1-0 CAP
  { id: 1489377, t1: 1,    t2: 32,   ft1: 2, ft2: 1, scorerT1: 20,   scorerT2: null  }, // BEL 2-1 EGY
  { id: 1489379, t1: 23,   t2: 7,    ft1: 0, ft2: 2, scorerT1: null, scorerT2: 31    }, // SAU 0-2 URU
  { id: 1489378, t1: 22,   t2: 4673, ft1: 1, ft2: 1, scorerT1: null, scorerT2: null  }, // IRA 1-1 NEW
];

// ─── Per-match predictions (hand-crafted) ────────────────────────────────────
//
// Format per user: [pred_t1, pred_t2, pred_scorer_id]
//
// Expected points per match listed in comments.
// Total: Alice 120 | Bob 95 | Danijel 69 | Charlie 31
//
// Scoring rules (group stage, multiplier 1×):
//   outcome=2, goal_diff=3, exact=3, scorer=5 (base max 13)
//   goal_diff requires correct outcome; exact requires correct goal_diff

const PREDICTIONS = {
  // MEX 2-1 SOU | scorer=248(Lozano)
  1489369: {
    danijel: [2, 0,  null],  //  2-0 MEX  → outcome ✓, diff wrong              = 2
    alice:   [1, 0,  248],   //  1-0 MEX  → outcome ✓, diff=1=1 ✓, scr ✓     = 5+5=10
    bob:     [2, 1,  248],   //  2-1 MEX  → exact ✓, scr ✓                    = 8+5=13
    charlie: [0, 1,  null],  //  0-1 SOU  → outcome ✗                          = 0
  },
  // SKO 1-0 CZE | scorer=186(Son)
  1538999: {
    danijel: [1, 0,  null],  //  1-0 SKO  → exact ✓                            = 8
    alice:   [1, 0,  186],   //  1-0 SKO  → exact ✓, scr ✓                    = 8+5=13
    bob:     [2, 0,  186],   //  2-0 SKO  → outcome ✓, diff wrong, scr ✓      = 2+5=7
    charlie: [2, 1,  null],  //  2-1 SKO  → outcome ✓, diff=1=1 ✓, not exact  = 5
  },
  // CAN 0-0 BOS | no scorer
  1539000: {
    danijel: [1, 0,  null],  //  1-0 CAN  → outcome ✗ (actual draw)            = 0
    alice:   [0, 0,  null],  //  0-0      → exact ✓                            = 8
    bob:     [0, 1,  null],  //  0-1 BOS  → outcome ✗                          = 0
    charlie: [1, 1,  null],  //  1-1 draw → outcome ✓, diff=0=0 ✓, not exact  = 5
  },
  // USA 3-1 PAR | no scorer with player_id
  1489370: {
    danijel: [3, 1,  null],  //  3-1 USA  → exact ✓                            = 8
    alice:   [2, 0,  null],  //  2-0 USA  → outcome ✓, diff=2=2 ✓, not exact  = 5
    bob:     [2, 1,  null],  //  2-1 USA  → outcome ✓, diff=1 vs 2 ✗          = 2
    charlie: [1, 0,  null],  //  1-0 USA  → outcome ✓, diff=1 vs 2 ✗          = 2
  },
  // QAT 1-1 SWI | scorer=5(Akanji/SWI)
  1489373: {
    danijel: [2, 1,  null],  //  2-1 QAT  → outcome ✗ (actual draw)            = 0
    alice:   [1, 1,  5],     //  1-1 draw → exact ✓, scr ✓                    = 8+5=13
    bob:     [1, 0,  null],  //  1-0 QAT  → outcome ✗ (actual draw)            = 0
    charlie: [0, 0,  null],  //  0-0 draw → outcome ✓, diff=0=0 ✓, not exact  = 5
  },
  // BRA 2-0 MOR | scorer=257(Marquinhos)
  1489371: {
    danijel: [3, 1,  257],   //  3-1 BRA  → outcome ✓, diff=2=2 ✓, scr ✓     = 5+5=10
    alice:   [1, 0,  null],  //  1-0 BRA  → outcome ✓, diff=1 vs 2 ✗          = 2
    bob:     [2, 0,  257],   //  2-0 BRA  → exact ✓, scr ✓                    = 8+5=13
    charlie: [0, 1,  null],  //  0-1 MOR  → outcome ✗                          = 0
  },
  // HAI 1-2 SCO | no scorer with player_id
  1489372: {
    danijel: [2, 1,  null],  //  2-1 HAI  → outcome ✗ (SCO wins)               = 0
    alice:   [1, 2,  null],  //  1-2 SCO  → exact ✓                            = 8
    bob:     [0, 2,  null],  //  0-2 SCO  → outcome ✓, diff=2 vs 1 ✗          = 2
    charlie: [0, 2,  null],  //  0-2 SCO  → outcome ✓, diff=2 vs 1 ✗          = 2
  },
  // AUS 0-1 TÜR | no scorer with player_id
  1539001: {
    danijel: [1, 0,  null],  //  1-0 AUS  → outcome ✗                          = 0
    alice:   [1, 0,  null],  //  1-0 AUS  → outcome ✗                          = 0
    bob:     [0, 1,  null],  //  0-1 TÜR  → exact ✓                            = 8
    charlie: [0, 2,  null],  //  0-2 TÜR  → outcome ✓, diff=2 vs 1 ✗          = 2
  },
  // GER 2-2 CUR | no scorer with player_id
  1489374: {
    danijel: [2, 2,  null],  //  2-2 draw → exact ✓                            = 8
    alice:   [3, 1,  null],  //  3-1 GER  → outcome ✗ (actual draw)            = 0
    bob:     [2, 0,  null],  //  2-0 GER  → outcome ✗ (actual draw)            = 0
    charlie: [1, 3,  null],  //  1-3 CUR  → outcome ✗                          = 0
  },
  // NET 1-0 JAP | scorer=247(Gakpo)
  1489376: {
    danijel: [1, 0,  null],  //  1-0 NET  → exact ✓                            = 8
    alice:   [2, 0,  247],   //  2-0 NET  → outcome ✓, diff wrong, scr ✓      = 2+5=7
    bob:     [1, 0,  247],   //  1-0 NET  → exact ✓, scr ✓                    = 8+5=13
    charlie: [1, 0,  null],  //  1-0 NET  → exact ✓                            = 8
  },
  // IVO 3-2 ECU | no scorer with player_id
  1489375: {
    danijel: [2, 0,  null],  //  2-0 IVO  → outcome ✓, diff=2 vs 1 ✗          = 2
    alice:   [3, 2,  null],  //  3-2 IVO  → exact ✓                            = 8
    bob:     [2, 1,  null],  //  2-1 IVO  → outcome ✓, diff=1=1 ✓, not exact  = 5
    charlie: [0, 2,  null],  //  0-2 ECU  → outcome ✗                          = 0
  },
  // SWE 0-0 TUN | no scorer
  1539002: {
    danijel: [0, 0,  null],  //  0-0      → exact ✓                            = 8
    alice:   [1, 1,  null],  //  1-1 draw → outcome ✓, diff=0=0 ✓, not exact  = 5
    bob:     [1, 0,  null],  //  1-0 SWE  → outcome ✗ (actual draw)            = 0
    charlie: [2, 1,  null],  //  2-1 SWE  → outcome ✗ (actual draw)            = 0
  },
  // SPA 1-0 CAP | scorer=44(Rodri)
  1489380: {
    danijel: [1, 0,  44],    //  1-0 SPA  → exact ✓, scr ✓                    = 8+5=13
    alice:   [2, 1,  44],    //  2-1 SPA  → outcome ✓, diff=1=1 ✓, scr ✓     = 5+5=10
    bob:     [2, 0,  44],    //  2-0 SPA  → outcome ✓, diff wrong, scr ✓      = 2+5=7
    charlie: [2, 0,  null],  //  2-0 SPA  → outcome ✓, diff wrong              = 2
  },
  // BEL 2-1 EGY | scorer=20(Lukaku/Witsel)
  1489377: {
    danijel: [2, 0,  null],  //  2-0 BEL  → outcome ✓, diff wrong              = 2
    alice:   [1, 0,  20],    //  1-0 BEL  → outcome ✓, diff=1=1 ✓, scr ✓     = 5+5=10
    bob:     [2, 1,  20],    //  2-1 BEL  → exact ✓, scr ✓                    = 8+5=13
    charlie: [1, 1,  null],  //  1-1 draw → outcome ✗ (BEL wins)               = 0
  },
  // SAU 0-2 URU | scorer=31(Giménez)
  1489379: {
    danijel: [1, 0,  null],  //  1-0 SAU  → outcome ✗                          = 0
    alice:   [0, 2,  31],    //  0-2 URU  → exact ✓, scr ✓                    = 8+5=13
    bob:     [0, 1,  31],    //  0-1 URU  → outcome ✓, diff=1 vs 2 ✗, scr ✓  = 2+5=7
    charlie: [1, 1,  null],  //  1-1 draw → outcome ✗ (URU wins)               = 0
  },
  // IRA 1-1 NEW | no scorer with player_id
  1489378: {
    danijel: [2, 0,  null],  //  2-0 IRA  → outcome ✗ (actual draw)            = 0
    alice:   [1, 1,  null],  //  1-1 draw → exact ✓                            = 8
    bob:     [0, 0,  null],  //  0-0 draw → outcome ✓, diff=0=0 ✓, not exact  = 5
    charlie: [0, 1,  null],  //  0-1 NEW  → outcome ✗ (actual draw)            = 0
  },
};

// Matchday 2 and 3 IDs — predictions here are all scheduled (no scoring yet)
const MATCHDAY2_IDS = [
  1539004, 1539005, 1489387, 1489388, 1489391, 1489390,
  1489389, 1539006, 1539007, 1489393, 1489392, 1489394,
  1489397, 1489395, 1489398, 1489396, 1489399, 1539017,
  1489401, 1489400, 1489404, 1489402, 1489403, 1539008,
];
const MATCHDAY3_IDS = [
  1489408, 1539009, 1489405, 1489406, 1539010, 1489407,
  1489410, 1489409, 1539011, 1489412, 1539012, 1489411,
  1539074, 1489416, 1489417, 1489413, 1489414, 1489415,
  1489420, 1489422, 1489419, 1539013, 1489418, 1489421,
];

// Realistic score pool for upcoming/unscored matches
const SCORE_POOL = [
  [1, 0], [2, 1], [2, 0], [1, 1], [0, 0],
  [0, 1], [1, 2], [3, 1], [2, 2], [3, 0],
  [1, 3], [0, 2], [2, 3], [4, 1], [1, 4],
];

function pickScore(seed) {
  return SCORE_POOL[((seed * 37 + 13) >>> 0) % SCORE_POOL.length];
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log("=== WC2026 Dev Seed v2 ===\n");

  // ── 1. Create dev users ────────────────────────────────────────────────────
  console.log("Step 1: Creating dev users...");
  const userMap = {};

  const { body: existingUsers } = await authGet("users?per_page=500");
  const existingByEmail = Object.fromEntries(
    (existingUsers.users || [])
      .filter((u) => u.email?.endsWith(`@${DEV_DOMAIN}`))
      .map((u) => [u.email, u.id])
  );

  for (const u of DEV_USERS) {
    const email = `${u.name}@${DEV_DOMAIN}`;
    if (existingByEmail[email]) {
      console.log(`  ${email} — already exists`);
      userMap[u.name] = existingByEmail[email];
    } else {
      const { body } = await authPost("users", {
        email,
        password: DEV_PASSWORD,
        user_metadata: { display_name: u.display },
        email_confirm: true,
      });
      if (body.id) {
        console.log(`  ${email} — created`);
        userMap[u.name] = body.id;
      } else {
        console.error(`  ${email} — FAILED:`, body);
      }
      await sleep(200);
    }
  }

  const [danijelId, aliceId, bobId, charlieId] = DEV_USERS.map((u) => userMap[u.name]);
  const users = { danijel: danijelId, alice: aliceId, bob: bobId, charlie: charlieId };
  console.log("  User IDs:", users);

  // ── 2. Create groups ──────────────────────────────────────────────────────
  console.log("\nStep 2: Creating groups...");
  await del("/rest/v1/groups?name=like.%5BDEV%5D%25");
  await sleep(300);

  const groupsRes = await post("/rest/v1/groups", [
    { name: "[DEV] WC Friends",    owner_id: danijelId, invite_code: "WCFRIENDS26" },
    { name: "[DEV] Office Rivals", owner_id: danijelId, invite_code: "OFFICE26" },
  ]);
  if (groupsRes.status !== 201) { console.error("Groups failed:", groupsRes.body); return; }
  const [groupFriends, groupOffice] = groupsRes.body;
  console.log(`  Created: "${groupFriends.name}" (${groupFriends.id})`);
  console.log(`  Created: "${groupOffice.name}" (${groupOffice.id})`);

  // ── 3. Add members ────────────────────────────────────────────────────────
  console.log("\nStep 3: Adding group members...");
  await post("/rest/v1/group_members", [
    { group_id: groupFriends.id, user_id: danijelId },
    { group_id: groupFriends.id, user_id: aliceId },
    { group_id: groupFriends.id, user_id: bobId },
    { group_id: groupFriends.id, user_id: charlieId },
    { group_id: groupOffice.id,  user_id: danijelId },
    { group_id: groupOffice.id,  user_id: aliceId },
  ]);
  console.log("  Members added");

  // ── 3.5 Device tokens (one fake FCM token per user) ────────────────────────
  // Deterministic strings, deliberately invalid — they exercise the
  // notify_predict_reminders anti-join logic without delivering real pushes.
  console.log("\nStep 3.5: Registering dev device tokens...");
  for (const uid of Object.values(users)) {
    await del(`/rest/v1/device_tokens?user_id=eq.${uid}`);
  }
  await sleep(200);
  const tokenRows = Object.entries(users).map(([name, uid], i) => ({
    user_id: uid,
    token: `dev-fcm-token-${name}-${i % 2 === 0 ? "ios" : "android"}`,
    platform: i % 2 === 0 ? "ios" : "android",
  }));
  const tokRes = await post("/rest/v1/device_tokens", tokenRows);
  if (tokRes.status !== 201) {
    console.error("  device_tokens insert failed:", tokRes.status, tokRes.body);
  } else {
    console.log(`  Registered ${tokenRows.length} fake device tokens`);
  }

  // ── 4. Wipe existing dev predictions ──────────────────────────────────────
  console.log("\nStep 4: Clearing old predictions...");
  for (const uid of Object.values(users)) {
    await del(`/rest/v1/predictions?user_id=eq.${uid}`);
  }
  await sleep(400);

  // ── 5. Insert hand-crafted predictions for finalized matches ──────────────
  console.log("\nStep 5: Inserting scored predictions...");
  for (const match of FINAL_MATCHES) {
    const preds = PREDICTIONS[match.id];
    if (!preds) { console.warn(`  No predictions defined for match ${match.id}`); continue; }

    const rows = Object.entries(preds).map(([uName, [t1, t2, scorer]]) => ({
      user_id: users[uName],
      match_id: match.id,
      predicted_team1: t1,
      predicted_team2: t2,
      predicted_scorer_id: scorer,
    }));

    const res = await post("/rest/v1/predictions", rows);
    if (res.status !== 201) {
      console.error(`  Match ${match.id} predictions failed:`, res.status,
        JSON.stringify(res.body).slice(0, 200));
    }
  }
  console.log(`  Inserted ${FINAL_MATCHES.length * 4} scored predictions`);

  // ── 6. Insert predictions for upcoming matches ────────────────────────────
  console.log("\nStep 6: Inserting upcoming match predictions...");
  const upcomingIds = [...MATCHDAY2_IDS, ...MATCHDAY3_IDS];
  let upcomingCount = 0;

  for (let i = 0; i < upcomingIds.length; i++) {
    const matchId = upcomingIds[i];
    const rows = Object.entries(users).map(([uName, uid]) => {
      const [t1, t2] = pickScore((matchId + Object.keys(users).indexOf(uName) * 7 + i * 13));
      return { user_id: uid, match_id: matchId, predicted_team1: t1, predicted_team2: t2 };
    });
    const res = await post("/rest/v1/predictions", rows);
    if (res.status === 201) upcomingCount += rows.length;
  }
  console.log(`  Inserted ${upcomingCount} upcoming predictions`);

  // ── 7. Insert match events and finalize matches ────────────────────────────
  console.log("\nStep 7: Inserting events and finalizing matches...");
  for (const match of FINAL_MATCHES) {
    // Events
    const events = [];
    let min = 12;
    if (match.ft1 > 0) {
      for (let g = 0; g < match.ft1; g++) {
        events.push({ match_id: match.id, minute: min + g * 18, type: "goal",
          team_id: match.t1, player_id: match.scorerT1 || null, player_name: null, detail: null });
      }
    }
    if (match.ft2 > 0) {
      const base = match.ft1 > 0 ? 65 : 20;
      for (let g = 0; g < match.ft2; g++) {
        events.push({ match_id: match.id, minute: base + g * 10, type: "goal",
          team_id: match.t2, player_id: match.scorerT2 || null, player_name: null, detail: null });
      }
    }

    // Reset to scheduled first — the scoring trigger only fires on the
    // scheduled→final transition. Without this, final→final is a no-op.
    await patch(`/rest/v1/matches?id=eq.${match.id}`, {
      status: "scheduled",
      score_ft_team1: null, score_ft_team2: null,
      score_ht_team1: null, score_ht_team2: null,
    });

    if (events.length > 0) {
      await del(`/rest/v1/match_events?match_id=eq.${match.id}`);
      await post("/rest/v1/match_events", events);
    }

    // Now finalize — trigger fires, compute_match_scoring runs with correct predictions + events
    await patch(`/rest/v1/matches?id=eq.${match.id}`, {
      status: "final",
      score_ft_team1: match.ft1,
      score_ft_team2: match.ft2,
      score_ht_team1: Math.min(match.ft1, 1),
      score_ht_team2: Math.min(match.ft2, 1),
      updated_at: new Date().toISOString(),
    });
    process.stdout.write(`  ${match.id}: ${match.ft1}-${match.ft2} ✓\n`);
    await sleep(1200); // let trigger + mat view refresh settle
  }

  // ── 7.5 Populate formations + per-match lineups on two finalised matches ──
  // Lets the Teams tab render a real lineup roster out-of-the-box on those
  // two matches; every other match keeps NULL formations so the
  // "Lineups available about 45 minutes before kickoff" placeholder is
  // also exercisable. The first two FINAL_MATCHES are convenient picks.
  //
  // Writes:
  //   • matches.formation_team1 / formation_team2 (string label, e.g. "4-3-3")
  //   • match_lineups rows: first 11 players by id ascending = starters,
  //     next 7 = substitutes (so the Teams tab shows 11 + 7 = 18, matching
  //     a typical matchday squad — never the entire 25-35 reserve roster).
  console.log("\nStep 7.5: Populating formations + match_lineups on sample matches...");
  const FORMATION_PRESETS = [
    { id: FINAL_MATCHES[0].id, f1: "4-3-3",   f2: "4-2-3-1" },
    { id: FINAL_MATCHES[1].id, f1: "3-5-2",   f2: "4-4-2"   },
  ];
  const STARTERS_PER_TEAM = 11;
  const SUBS_PER_TEAM = 7;
  for (const preset of FORMATION_PRESETS) {
    await patch(`/rest/v1/matches?id=eq.${preset.id}`, {
      formation_team1: preset.f1,
      formation_team2: preset.f2,
    });

    const match = FINAL_MATCHES.find((m) => m.id === preset.id);
    if (!match) continue;

    // Replace any prior match_lineups rows for this fixture so re-runs
    // are idempotent (delete-then-insert mirrors poll_lineups exactly).
    await del(`/rest/v1/match_lineups?match_id=eq.${preset.id}`);

    const lineupRows = [];
    for (const teamId of [match.t1, match.t2]) {
      const { body: roster } = await req(
        "GET",
        `/rest/v1/players?team_id=eq.${teamId}&select=id&order=id.asc&limit=${STARTERS_PER_TEAM + SUBS_PER_TEAM}`,
      );
      const ids = (roster || []).map((r) => r.id);
      for (let i = 0; i < ids.length; i++) {
        lineupRows.push({
          match_id: preset.id,
          team_id: teamId,
          player_id: ids[i],
          is_starter: i < STARTERS_PER_TEAM,
          grid: i < STARTERS_PER_TEAM ? "1:1" : null,
        });
      }
    }
    if (lineupRows.length > 0) {
      const r = await post("/rest/v1/match_lineups", lineupRows);
      if (r.status !== 201) {
        console.error(`  match_lineups insert failed for ${preset.id}:`, r.status, r.body);
      }
    }
  }
  console.log(`  Set formations + lineups on ${FORMATION_PRESETS.length} matches`);

  // ── 8. Lock predictions for finalized matches ──────────────────────────────
  console.log("\nStep 8: Locking predictions for finalized matches...");
  const finalIds = FINAL_MATCHES.map((m) => m.id);
  await patch(
    `/rest/v1/predictions?match_id=in.(${finalIds.join(",")})&locked_at=is.null`,
    { locked_at: new Date().toISOString() }
  );
  console.log("  Locked");

  // ── 9. Print expected standings ────────────────────────────────────────────
  await sleep(2000);
  console.log("\nStep 9: Verifying standings...");
  const s = await (async (gid) => {
    const r = await req("GET", `/rest/v1/group_standings?group_id=eq.${gid}`
      + `&select=display_name,total_points&order=total_points.desc`);
    return r.body;
  })(groupFriends.id);

  console.log("\n  Leaderboard — WC Friends:");
  (s || []).forEach((r, i) =>
    console.log(`   ${i + 1}. ${r.display_name} — ${r.total_points} pts`)
  );

  // ── 9. Seed one reminder log entry ─────────────────────────────────────────
  // Demonstrates the prediction_reminders_sent schema. Uses Danijel + the
  // first finalised match so the FK cascade trail (auth.users → match → log)
  // is obvious during local debugging.
  console.log("\nStep 9.5: Inserting sample reminder log row...");
  await del(
    `/rest/v1/prediction_reminders_sent?user_id=eq.${users.danijel}` +
      `&match_id=eq.${FINAL_MATCHES[0].id}`,
  );
  await post("/rest/v1/prediction_reminders_sent", [{
    user_id: users.danijel,
    match_id: FINAL_MATCHES[0].id,
  }]);
  console.log(`  Inserted reminder log: (danijel, ${FINAL_MATCHES[0].id})`);

  console.log("\n=== Seed complete ===");
  console.log(`  Login: danijel/alice/bob/charlie @${DEV_DOMAIN} / ${DEV_PASSWORD}`);
}

main().catch(console.error);
