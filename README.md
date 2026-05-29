# WC2026 Predict

Flutter app for a private group of friends to predict World Cup 2026 match results, with real-time live scores, per-group leaderboards, and magic-link authentication. Free-tier infrastructure (Supabase + BALLDONTLIE).

## Prerequisites

- Flutter 3.35+
- Supabase account (free tier)
- BALLDONTLIE API key (free tier at https://balldontlie.io)

## Setup

### 1. Supabase project

1. Create a new project at https://supabase.com
2. Run migrations in order:
   ```
   supabase db push
   ```
   Or apply manually in Supabase SQL editor:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_rls_policies.sql`
   - `supabase/migrations/003_enable_realtime.sql`

3. Seed teams:
   ```sql
   -- Run in Supabase SQL editor
   \i supabase/seed/teams.sql
   ```

4. Enable `pg_cron` and `pg_net` extensions in Supabase dashboard (Database → Extensions).

5. Deploy Edge Functions:
   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   supabase functions deploy poll_fixtures --no-verify-jwt
   supabase functions deploy poll_live_matches --no-verify-jwt
   supabase functions deploy poll_lineups --no-verify-jwt
   supabase functions deploy lock_predictions --no-verify-jwt
   ```

6. Set function secrets:
   ```bash
   supabase secrets set BALLDONTLIE_API_KEY=your_key_here
   ```

7. Schedule cron jobs — edit `supabase/seed/cron_schedule.sql` with your project ref and anon key, then run in SQL editor.

### 2. Flutter app

Build with environment variables injected at compile time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

For release builds:
```bash
# iOS
flutter build ipa \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...

# Android
flutter build appbundle \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

### 3. Deep-link setup

#### iOS
The URL scheme `wcpredict://` is already registered in `ios/Runner/Info.plist`.

In Supabase dashboard → Authentication → URL Configuration:
- Add `wcpredict://auth/callback` to Redirect URLs.

#### Android
The intent filter for `wcpredict://auth/callback` is registered in `AndroidManifest.xml`.

## Architecture

- **Backend**: Supabase (Postgres + Auth + Realtime + Edge Functions)
- **Data source**: BALLDONTLIE FIFA API (free tier, 5 req/min)
- **Polling**: `poll_live_matches` runs every 60s; self-gates to a daily window (T-30min before earliest kickoff → all matches final)
- **Live updates**: Supabase Realtime on `matches` and `match_events` tables; subscriptions opened only while `MatchDetailScreen` is active
- **Scoring**: DB trigger fires `compute_match_scoring()` when `matches.status` transitions to `'final'`

## Scoring rules (v1, fixed)

| Category | Points |
|---|---|
| Exact score (90' FT) | 3 |
| Correct result (win/draw/loss direction) | 1 |
| First team to score | 2 |
| Goalscorer (non-own-goal, minutes 1-120) | 3 |
| **Maximum per match** | **8** |

Own goals, shootout kicks, and VAR-disallowed goals are excluded from goalscorer and first-team-to-score logic.

## Key edge cases handled

- Penalty shootouts: `score_pen_*` columns; scoring uses FT result direction (90')
- Extra time: `score_et_*` columns; FT = 90' for scoring; knockout winner from ET/pens
- Kickoff delays: `lock_predictions` uses `kickoff_time`; update that column in DB if FIFA postpones
- VAR-disallowed goal: deleting a `match_events` row re-triggers `compute_match_scoring`
- 0-0 prediction: DB CHECK constraint prevents non-null first-team/scorer fields
- Knockout bracket resolution: `poll_fixtures` daily upsert resolves placeholder teams

## File structure

```
wcpredict/
├── lib/
│   ├── main.dart               # Entry point; Supabase.initialize()
│   ├── app.dart                # MaterialApp.router
│   ├── router.dart             # go_router; auth-guarded redirects
│   ├── theme.dart              # Material 3 dark-green theme
│   ├── core/
│   │   ├── env.dart            # SUPABASE_URL / SUPABASE_ANON_KEY constants
│   │   ├── supabase_client.dart
│   │   ├── auth_repository.dart
│   │   └── models/             # Dart models matching DB schema
│   ├── features/
│   │   ├── auth/               # MagicLinkScreen, AuthCallbackScreen
│   │   ├── home/               # HomeScreen (upcoming + recent)
│   │   ├── groups/             # GroupsList, GroupDetail, Create, Join
│   │   ├── fixtures/           # FixturesScreen (filterable 104-match list)
│   │   ├── matches/            # MatchDetail, PredictModal, LiveEventsWidget
│   │   ├── bracket/            # BracketScreen (knockout visualization)
│   │   └── profile/            # ProfileScreen (stats + sign out)
│   └── shared/
│       ├── providers/          # Riverpod providers
│       └── widgets/            # MatchCard, TeamFlag
├── supabase/
│   ├── config.toml
│   ├── migrations/             # 001 schema, 002 RLS, 003 realtime
│   ├── seed/                   # teams.sql, cron_schedule.sql
│   └── functions/
│       ├── _shared/            # cors.ts, supabase.ts
│       ├── poll_fixtures/      # Daily fixture sync
│       ├── poll_live_matches/  # Per-minute live score polling
│       ├── poll_lineups/       # T-30min lineup fetch
│       └── lock_predictions/  # Kickoff-time prediction lock
└── README.md
```
