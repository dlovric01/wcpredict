# Repository Guidelines

## Project Overview

**wcpredict** is a Flutter mobile app for the 2026 FIFA World Cup prediction game. Users submit score predictions before kickoff, earn points for accuracy, and compete in private groups on a shared leaderboard.

**Scoring rules** (canonical source: `rules.md`). Match-result categories are **mutually exclusive** — only the highest matching one is awarded:

| Match-result category | Points |
|---|---|
| Exact score | 5 |
| Correct goal difference (\|GD\| ≥ 2) | 3 |
| Correct outcome (W/D/L) | 2 |
| Wrong / no prediction | 0 |

Two independent additive bonuses:

| Bonus | Points | Condition |
|---|---|---|
| First team to score | 2 | Picked team scores the first regular-time non-OG, non-shootout goal (minute ≤ 90) |
| Goalscorer | 8 | Selected player scored ≥1 non-own-goal in regulation time |

**Max per match (base) = 5 + 2 + 8 = 15.** Knockout rounds apply manual booster multipliers (R32 ×2, R16 ×3, QF ×4, SF ×5) or automatic multipliers (3rd Place ×5, Final ×6). Tournament-level bonuses are added separately: World Cup Winner = 75, Golden Boot = 50 (max +125 across the tournament).
Backend: Supabase (PostgreSQL 17 + Auth + Realtime). Authentication via Apple Sign-In (iOS) and Google Sign-In. Match data is synced from **api-sports.io** (`v3.football.api-sports.io`) via Deno v2 edge functions on cron schedules. Predictions lock automatically at kickoff; scoring fires via a PostgreSQL trigger when a match reaches `final` status.

---

## Architecture & Data Flow

```
api-sports.io
    ↓ (cron → Deno v2 edge functions)
PostgreSQL 17 (Supabase)
  matches, match_events, teams, players
  predictions (locked at kickoff)
  compute_match_scoring() trigger (fires on status → 'final'; re-fires on event delete for VAR)
  group_standings (materialized view, refreshed per final)
    ↓ (Supabase Realtime — WebSocket)
Flutter Client
  flutter_riverpod — state (FutureProvider / StreamProvider)
  go_router — navigation with auth guard + StatefulShellRoute 5-tab nav
  supabase_flutter — queries + social auth (Apple/Google)
  talker_flutter — structured logging
```

### Flutter Layer Separation

| Layer | Path | Responsibility |
|---|---|---|
| Entry / Bootstrap | `lib/main.dart` | Init Supabase, wire Talker error handlers, `ProviderScope` → `runApp` |
| Root Widget | `lib/app.dart` | `MaterialApp.router`, `TalkerWrapper`, `appTheme`, draggable `_LogFab` |
| Routing | `lib/router.dart` | GoRouter + auth redirect guard + `StatefulShellRoute.indexedStack` 5-tab nav |
| Core | `lib/core/` | Models, `AuthRepository` (Apple/Google Sign-In), Supabase singleton, env constants, logger, theme |
| Shared | `lib/shared/` | Cross-feature Riverpod providers and reusable widgets |
| Features | `lib/features/<name>/` | Screen widgets, local providers, modals — scoped to feature |
| Backend | `supabase/` | Migrations, edge functions, seed data |

**Data mutations** bypass providers: call `supabase.from(table).upsert(data)` directly in an event handler, then `ref.invalidate(provider)` to force a re-fetch.

---

## Key Directories

```
lib/
  main.dart                  — entry: init Supabase + Talker, ProviderScope, runApp
  app.dart                   — MaterialApp.router; TalkerWrapper; draggable log FAB
  router.dart                — GoRouter: auth guard, StatefulShellRoute (5 tabs),
                               detail routes /matches/:matchId /groups/:groupId
                               /members/:userId /dev/simulate
  core/
    env.dart                 — Env.supabaseUrl / Env.supabaseAnonKey (--dart-define)
    supabase_client.dart     — initSupabase(), global `supabase` getter
    auth_repository.dart     — sendMagicLink, signOut, updateDisplayName, authStateChanges
    logger.dart              — global `talker` (TalkerFlutter, 500-item ring buffer)
    models/                  — data models (fromJson/toJson, const constructors)
    theme/
      app_colors.dart        — "Stadium Night" dark palette + ColorScheme + forPosition()
      app_theme.dart         — ThemeData (Material3 dark) built from AppColors + Google Fonts
      app_typography.dart    — text styles
      app_spacing.dart       — spacing constants
      app_radii.dart         — border radius constants
      app_motion.dart        — animation durations/curves
  shared/
    providers/               — auth_provider, matches_provider, match_detail_provider,
                               predictions_provider, groups_provider, mock_bracket
    widgets/                 — match_card, team_flag, app_shell, app_logo,
                               countdown_pill, verdict_pill
  features/
    auth/                    — social_sign_in_screen, auth_callback_screen
    groups/                  — groups_list, group_detail, create_group, join_group,
                               user_predictions_screen,
                               invite_code.dart  (kInviteCodeLength + generateInviteCode),
                               group_name.dart   (validateGroupName helper)
    matches/                 — match_detail_screen, live_events_widget,
                               matches_list_screen, tournament_achievement_banner,
                               predict_logic.dart (predictTabLocked + sanitisePredictionPicks)
    tournament/              — tournament_predictions_screen
    live/                    — live_screen (live tab; uses Realtime stream)
    profile/                 — profile_screen
    dev/                     — simulation_screen (/dev/simulate — dev-only)

supabase/
  migrations/                — 001–022 ordered SQL migrations (latest: first-team-to-score)
  functions/                 — Deno v2 edge functions
    poll_fixtures/           — daily sync of all fixtures + teams (api-sports.io)
    poll_live_matches/       — every 1 min; updates scores + events
    poll_lineups/            — self-gates 25–35 min before kickoff
    lock_predictions/        — every 30 min; locks predictions at kickoff
    compute_scoring/         — manual scoring trigger (edge function wrapper)
    test_api/                — api-sports.io connectivity test
    _shared/                 — cors.ts, supabase.ts helpers
  seed/
    teams.sql                — 48 teams
    cron_schedule.sql        — cron schedule template
    dev_seed.js              — dev data seeding (Node/Deno compatible)
    simulate_live.sql        — live-match simulation SQL
  config.toml                — local dev config (ports, PostgreSQL 17, Deno v2)
```

---

## Development Commands

### Running the App

The app requires Supabase credentials injected at build time via `--dart-define`. Use `run.sh` which reads from `.env`:

```bash
# .env:
# SUPABASE_URL=https://<ref>.supabase.co
# SUPABASE_ANON_KEY=<anon-key>

./run.sh                     # debug on connected device
./run.sh --release           # release build
./run.sh --profile           # profile mode
./run.sh -d <device-id>      # target specific device
```

Manual equivalent:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://... \
  --dart-define=SUPABASE_ANON_KEY=...
```

### Build

```bash
flutter build apk  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build ios  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Tests & Lint

```bash
flutter test                 # smoke test (test/widget_test.dart)
flutter analyze              # static analysis via flutter_lints

# Regression suite (requires live Supabase instance; credentials in test/regression/helpers.ts)
cd test/regression
bun install                  # first time only
bun test                     # 51 tests across 8 suites
```

### Supabase Local Dev

```bash
supabase start                                       # API :54321, DB :54322, Studio :54323
supabase db reset                                    # reset + all migrations + seed teams.sql
supabase db push                                     # apply pending migrations to remote
supabase functions deploy <name> --no-verify-jwt
supabase secrets set APISPORTS_KEY=<key>
```

### Dependencies

```bash
flutter pub get
flutter pub upgrade
```

Code generation (staged, not active — no `@riverpod` sources):

```bash
dart run build_runner build
dart run build_runner watch
```

---

## Code Conventions & Common Patterns

### Naming

| Construct | Convention | Example |
|---|---|---|
| Classes | PascalCase | `MatchModel`, `HomeScreen`, `AuthRepository` |
| Files | snake_case | `match_model.dart`, `social_sign_in_screen.dart` |
| Private widgets (in-file) | `_ClassName` | `_TeamSide`, `_ScorePicker` |
| Providers | camelCase + `Provider` suffix | `allMatchesProvider`, `myPredictionProvider` |
| Methods | camelCase | `signInWithApple`, `signInWithGoogle` |
| JSON → Dart | snake_case → camelCase | `team1_id` → `team1Id` |

### Models (`lib/core/models/`)

```dart
class MatchModel {
  const MatchModel({required this.id, this.status, ...});

  final int id;
  final String? status;

  factory MatchModel.fromJson(Map<String, dynamic> json) => MatchModel(
        id: (json['id'] as num).toInt(),
        status: json['status'] as String?,
        // DateTime: DateTime.parse(json['kickoff_time'] as String)
        // Nested: TeamModel.fromJson(json['team1'] as Map<String, dynamic>)
      );

  Map<String, dynamic> toJson() => {'id': id, 'status': status};

  // Computed getter (not serialized):
  bool get isLocked => status == 'live' || status == 'final' || DateTime.now().isAfter(kickoffTime);
}
```

- `const` constructors throughout.
- `fromJson`: nullable fields with `as Type?`, numerics with `.toInt()`.
- `toJson`: excludes nested objects (they come from joins; written separately).
- Computed getters (e.g., `isLocked`) belong on models, not in UI.

Key models: `MatchModel` (nested `team1`/`team2`, `isLocked` getter combining status + wall-clock kickoff), `PredictionModel` (score + `predictedFirstTeamId` + `predictedScorerId`; per-category `pointsMatch` / `pointsFirstTeam` / `pointsGoalscorer`; computed `basePoints` = 0..15, `isExact`/`isGoalDiff`/`isOutcome`, `firstTeamHit`, `goalscorerHit`), `TeamModel` (id, name, code, flagUrl, groupLetter, optional players join), `GroupModel` + `GroupMemberModel`, `GroupStandingModel` (leaderboard view; tiebreaker counts `exactCount`/`goalDiffCount`/`outcomeCount`/`scorerCount` and `earliestSubmission`), `PlayerModel` (grid `'row:col'`, isStarter, position, jerseyNumber), `MatchEventModel` (minute, minuteExtra, type goal/card/sub/shootout_kick, teamId, playerId, detail; `minuteLabel` getter for "90+3'" formatting), `ProfileModel`, `RoundBoosterModel` (one per user per knockout round), `TournamentPredictionModel` (WC winner + Golden Boot), `TournamentResultsModel` (single-row admin table; `hasWinner`/`hasGoldenBoot`/`isFinalised` flags).

### State Management (Riverpod)

Shared providers live in `lib/shared/providers/`; feature-local providers are private (inline in the screen file).

```dart
// Shared provider
final allMatchesProvider = FutureProvider<List<MatchModel>>((ref) async {
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!matches_team1_id_fkey(*), team2:teams!matches_team2_id_fkey(*)')
      .order('kickoff_time');
  return data.map(MatchModel.fromJson).toList();
});

// Parameterized (family)
final matchByIdProvider = FutureProvider.family<MatchModel, int>((ref, id) async { ... });

// Widget consumption
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(allMatchesProvider);
    return matches.when(
      loading: () => const _ShimmerList(),
      error: (e, _) => _ErrorTile(e),
      data: (list) => _MatchList(list),
    );
  }
}
```

- `ref.watch()` to subscribe; `ref.invalidate(provider)` to force re-fetch after mutation.
- Riverpod code generation (`@riverpod`, `riverpod_generator`) is **staged but not active** — all providers are defined manually. Do not add generated providers without activating `build_runner`.

### Async / Error Handling

```dart
Future<void> _submit() async {
  setState(() => _loading = true);
  try {
    await supabase.from('predictions').upsert({...}, onConflict: 'user_id,match_id');
    ref.invalidate(myPredictionProvider(widget.matchId));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(...);
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: theme.colorScheme.error),
    );
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```

- Always guard `setState`/`ScaffoldMessenger` with `if (mounted)`.
- Disable submit buttons while `_loading` to prevent double-submission.
- Use Shimmer as loading placeholder; empty-state widget for no-data; error widget with retry for failures.

### Widget Composition

Large screens decompose into private helper widgets in the same file:

```dart
class MatchCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(children: [
    _TeamSide(team: match.team1),
    _CentreScore(match: match),
    _TeamSide(team: match.team2),
  ]);
}
class _TeamSide extends StatelessWidget { ... }
class _CentreScore extends StatelessWidget { ... }
```

### Theme

Dark-only "Stadium Night" palette defined in `lib/core/theme/app_colors.dart`. **Never use `Colors.X` hardcoded values outside that file.**

| Token | Value | Usage |
|---|---|---|
| `primary` | `#00C566` (Pitch Emerald) | CTAs, active states |
| `secondary` | `#FFB627` (Goal Amber) | highlights, badges |
| `tertiary` | `#5A8DFF` (Sky Cobalt) | info, links |
| `surfaceBase` | `#0A0E1A` | app background |
| `surfaceHighest` | `#232C49` | modal sheets |

`AppColors.forPosition(position)` returns a color for GK/DEF/MID/FWD player indicators.

### Routing (GoRouter)

- Auth redirect in `router.dart`: unauthenticated → `/sign-in`; authenticated at `/sign-in` → `/home`.
- `_publicRoutes = {'/sign-in', '/auth/callback'}`.
- Bottom nav: `StatefulShellRoute.indexedStack` — home, fixtures, groups, bracket, profile.
- Navigate: `context.go('/home')`, `context.push('/matches/:matchId')`.

### Supabase Queries

```dart
supabase
  .from('matches')
  .select('*, team1:teams!matches_team1_id_fkey(*), team2:teams!matches_team2_id_fkey(*)')
  .eq('status', 'scheduled')
  .order('kickoff_time')
```

- `.maybeSingle()` when result may be null; `.single()` only when row is guaranteed.
- Upsert predictions: `.upsert({...}, onConflict: 'user_id,match_id')`.

### Logging

Global `talker` (500-item ring buffer) from `lib/core/logger.dart`. `app.dart` wraps the widget tree in `TalkerWrapper`; `FlutterError.onError` and `runZonedGuarded` route all errors through it. The draggable `_LogFab` opens `TalkerScreen` in-app (dev builds).

### Dev / Mock Toggle

`kUseMockData` flag gates mock data paths. `/dev/simulate` (`features/dev/simulation_screen.dart`) drives the `simulate_live_match(step_num int)` SECURITY DEFINER RPC (migration 009) for UI testing without a live match.

---

## Important Files

| File | Purpose |
|---|---|
| `lib/main.dart` | Entry: init Supabase + Talker → `ProviderScope` → `runApp` |
| `lib/app.dart` | `MaterialApp.router` + `TalkerWrapper` + `appTheme` + log FAB |
| `lib/router.dart` | All routes + auth redirect guard + 5-tab `StatefulShellRoute` |
| `lib/core/env.dart` | `Env.supabaseUrl` / `Env.supabaseAnonKey` (build-time `--dart-define`) |
| `lib/core/supabase_client.dart` | `initSupabase()`, global `supabase` getter |
| `lib/core/auth_repository.dart` | Apple Sign-In, Google Sign-In, display name update, `authStateChanges` |
| `lib/core/logger.dart` | Global `talker` instance (TalkerFlutter, 500-item ring buffer) |
| `lib/core/models/match_model.dart` | Central match model; `isLocked` computed getter |
| `lib/core/models/prediction_model.dart` | Prediction with full points breakdown |
| `lib/core/theme/app_colors.dart` | "Stadium Night" dark palette + `ColorScheme` + `forPosition()` |
| `lib/core/theme/app_theme.dart` | `appTheme` — Material3 dark, Google Fonts |
| `lib/shared/providers/auth_provider.dart` | `authRepositoryProvider`, `currentUserProvider` |
| `lib/shared/widgets/match_card.dart` | Primary match display widget (live/final/scheduled states) |
| `lib/features/matches/predict_logic.dart` | Pure helpers: `predictTabLocked` + `sanitisePredictionPicks` (unit-tested) |
| `lib/features/groups/invite_code.dart` | `kInviteCodeLength = 8` + `generateInviteCode()` — single source of truth for create/regenerate/join |
| `lib/features/groups/group_name.dart` | `validateGroupName` shared between create + rename (min 2, max 40 chars after trim) |
| `lib/features/dev/simulation_screen.dart` | Dev tool driving `simulate_live_match()` RPC step-by-step |
| `lib/features/auth/social_sign_in_screen.dart` | Social authentication screen with Apple/Google Sign-In buttons |
| `supabase/migrations/001_initial_schema.sql` | Full DB schema, triggers, `compute_match_scoring()` |
| `supabase/migrations/006_fix_rls_recursion.sql` | `is_group_member()` SECURITY DEFINER (breaks RLS recursion) |
| `supabase/migrations/009_simulation_rpc.sql` | `simulate_live_match(step_num int)` dev RPC |
| `supabase/migrations/017_rules_md_scoring.sql` | Mutually-exclusive match scoring (5/3/2) + goalscorer 8; reshapes `predictions` columns |
| `supabase/migrations/018_tournament_predictions.sql` | WC winner + Golden Boot picks + `tournament_results` mirror |
| `supabase/migrations/019_group_standings_v3.sql` | Materialised leaderboard view including tournament bonus |
| `supabase/migrations/022_first_team_to_score.sql` | Adds `predicted_first_team_id` + `points_first_team`; validation + lock triggers; recomputes all finalized matches |
| `supabase/functions/poll_live_matches/index.ts` | Match result + event sync (every 1 min) |
| `test/regression/regression.test.ts` | 91-test Bun regression suite (10 blocks including First Team scoring + validation) |
| `test/regression/helpers.ts` | adminClient/anonClient/userClient, fixture helpers, teardown |
| `pubspec.yaml` | Dart SDK `>=3.0.0 <4.0.0`; all Flutter deps |
| `run.sh` | Dev run script — reads `.env`, passes `--dart-define` flags |
| `SOCIAL_AUTH_SETUP.md` | Complete setup guide for Apple Sign-In and Google Sign-In configuration |
| `analysis_options.yaml` | Lint config (flutter_lints defaults, no overrides) |

---

## Runtime / Tooling Preferences

- **Flutter**: stable channel. Dart SDK `>=3.0.0 <4.0.0`.
- **iOS**: deployment target **13.0**; CocoaPods 1.16.2.
- **Android**: Java 11 / Kotlin 2.1.0; AGP 8.9.1. `compileSdk`/`minSdk` from Flutter defaults. Release signing uses debug key — configure before production. Gradle `-Xmx8G`.
- **Supabase CLI**: required for local dev and migrations.
- **Deno v2**: runtime for edge functions (managed by Supabase, `per_worker` mode).
- **Bun**: used for the regression test suite (`test/regression/`). No Bun tooling elsewhere.
- **No Node in edge functions**: edge functions are TypeScript/Deno only.
- **Credentials**: never hardcoded. Flutter: `--dart-define` at build time from `.env` via `run.sh`. Edge functions: `SUPABASE_SERVICE_ROLE_KEY` + `APISPORTS_KEY` from Supabase Vault.

### Key Dependencies

**Runtime:** `supabase_flutter ^2.8.4`, `flutter_riverpod ^2.6.1`, `go_router ^14.6.3`, `talker_flutter ^5.1.16`, `google_fonts ^6.2.1`, `flutter_animate ^4.5.2`, `cached_network_image ^3.4.1`, `shimmer ^3.0.0`, `intl ^0.20.2`, `uuid ^4.5.1`, `material_symbols_icons ^4.2784.0`.

**Dev:** `build_runner ^2.4.15`, `riverpod_generator ^2.6.5`, `custom_lint ^0.7.5`, `riverpod_lint ^2.6.5`, `flutter_lints ^5.0.0`. No `mockito`/`mocktail`, no coverage tooling.

### Required Environment Variables

| Variable | Where | Purpose |
|---|---|---|
| `SUPABASE_URL` | `.env` → `--dart-define` | Project API URL |
| `SUPABASE_ANON_KEY` | `.env` → `--dart-define` | Public client key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Vault | Edge function admin access |
| `APISPORTS_KEY` | Supabase Vault | api-sports.io football data |
| `GOOGLE_SERVER_CLIENT_ID` | `.env` → `--dart-define` | Google OAuth Web Client ID |
| `IOS_REVERSED_CLIENT_ID` | `.env` → `--dart-define` | Reversed iOS Client ID for URL scheme |

### Supabase Local Config (config.toml)

- API: `:54321`, DB: `:54322`, shadow: `:54320`, Studio: `:54323`, Inbucket (email): `:54324`, Analytics: `:54327`.
- PostgreSQL 17. Auth: JWT 3600s, signup enabled, email confirmations off, refresh token rotation on. Storage: 50 MiB. Edge runtime: Deno v2 `per_worker`, inspector `:8083`. Max API rows: 1000.

---

## Testing & QA

### Flutter tests (`flutter test`, ~5s, 132 tests)

No Supabase / network dependencies — runs as pure Dart unit + widget tests.

```
test/
  models/                 — JSON round-trip + computed-getter tests for every model
    prediction_model_test.dart   (7)
    match_model_test.dart        (15 — incl. kickoff boundary, multipliers)
    team_model_test.dart         (4)
    player_model_test.dart       (5)
    group_model_test.dart        (4 — GroupModel + GroupMemberModel)
    group_standing_model_test.dart (4)
    match_event_model_test.dart  (10 — incl. minuteLabel branches)
    profile_model_test.dart      (2)
    round_booster_model_test.dart (4)
    tournament_prediction_model_test.dart (4)
    tournament_results_model_test.dart   (7)
  widgets/                — focused widget tests for shared UI components
    verdict_pill_test.dart       (16 — every label/branch combination)
    match_card_test.dart         (8 — live / final / locked / scheduled state machine)
    countdown_pill_test.dart     (5)
    team_flag_test.dart          (6 — TBD / code / flagUrl modes)
  features/               — pure-logic helpers extracted from feature screens
    predict_logic_test.dart      (18 — lock decision × Realtime override; bonus-pick sanitisation)
    invite_code_test.dart        (4 — length + uniqueness + format)
    group_name_test.dart         (8 — min/max/trim)
  widget_test.dart        — harness placeholder
  generate_icon.dart      — NOT a test (intentionally lacks `_test` suffix); icon-generation tool
```

### Regression suite (`test/regression/`, ~66s, 91 tests)

**Bun** + `bun:test` + `@supabase/supabase-js` 2.106.2, strict TypeScript 5. Runs against a **live Supabase instance** (URL/anon/service-role keys in `helpers.ts`). Use a local stack (`supabase start`) for everyday development — pointing the suite at the production project is destructive.

| Suite | Tests | Covers |
|---|---|---|
| Auth & Profiles | 5 | profile creation, display-name updates |
| Groups | 9 | create/join/leave/delete + RLS |
| Predictions CRUD | 8 | INSERT/UPDATE/DELETE through anon + user clients |
| Lock Predictions | 5 | DB trigger + `lock_predictions` edge function |
| Scoring Engine | 11 | mutually-exclusive match awards + goalscorer + multiplier + own-goal/ET exclusion |
| **First Team to Score** | 7 | correct pick = 2pts, stacks with match/GS, own goals + ET ignored |
| **First Team Validation** | 4 | triggers reject 0-0 pick, 0-side pick, off-match pick; accept valid |
| Edge Cases | 5 | ET/pens stored, no scoring impact |
| Leaderboard | 2 | `group_standings` reflects totals + tiebreakers |
| RLS | 6 | cross-user visibility on every table |
| **Total** | **91** | |

`helpers.ts` exports `adminClient`/`anonClient`/`userClient`, `insertTestFixtures` (48 teams + players + 5 fixtures), `teardownTestData`. Test users alice/bob/charlie created in `beforeAll`, torn down in `afterAll`. Stable test IDs in the `99_000+` range avoid collisions with real data.

```bash
cd test/regression
bun install      # first time
bun test
```

To run against a local stack, swap `SUPABASE_URL` + `ANON_KEY` + `SERVICE_KEY` in `helpers.ts` for the values printed by `supabase status -o env`. Note: CLI v2.75+ uses ES256-signed JWTs for the auth admin endpoint — the legacy HS256 keys from `supabase status` work for PostgREST but not for `auth.admin.createUser`. Sign tokens with the JWK private key in `supabase_auth_<project>` env (see `test/regression/README` if present, or look at `GOTRUE_JWT_KEYS` in the auth container).

### Constraints

- Real integration tests require a running Supabase instance. `supabase start` spins up a local stack.
- No mocking libraries installed. Add `mockito`/`mocktail` to `dev_dependencies` before writing mock-based unit tests.
- `riverpod_generator`/`build_runner` are staged but no `@riverpod` code exists. Running `build_runner` with no annotated sources is a no-op.
- iOS: empty `RunnerTests.swift` stub. Android: no test sources.
- **Private widget access**: prefer extracting pure logic (e.g. `predict_logic.dart`) into a top-level public helper and testing that, rather than exposing `_PredictTab` / similar private classes for testability.

### Testing Priorities (when adding coverage)

1. **Cross-file invariants first**: any constant or rule referenced from multiple files (`kInviteCodeLength`, `kGroupNameMaxLength`, scoring point values) MUST have a test that fails if any single site drifts.
2. Model `fromJson`/`toJson` round-trips — pure Dart, no Flutter deps.
3. Pure logic helpers extracted from screen widgets — see `predict_logic.dart` pattern.
4. `isLocked` + `predictTabLocked` boundary cases.
5. Auth redirect logic in `router.dart` (currently uncovered — requires injectable auth state).
6. `compute_match_scoring` SQL function — covered by the regression suite (`Scoring Engine` + `First Team` blocks).