# Privacy & Production Launch TODO

Tasks required before submitting to App Store / Google Play and before public release.

---

## 1. Privacy Policy & Terms of Service

**Required by**: Apple App Store, Google Play, Google OAuth verification, GDPR (EU users), CCPA (California users).

### Generate the documents

Use one of:
- https://www.freeprivacypolicy.com/ (free, simple)
- https://www.termsfeed.com/ (free tier)
- https://app-privacy-policy-generator.firebaseapp.com/ (free, mobile-focused)

### What to disclose in the privacy policy

- **Data collected**: email, display name, profile picture (from Apple/Google sign-in)
- **Authentication providers**: Apple Sign-In, Google Sign-In
- **Backend**: Supabase (hosted in [your region], e.g. EU)
- **Analytics/logging**: Talker (in-app only, no third-party telemetry currently)
- **API providers**: api-sports.io (match data only, no user data sent)
- **Data retention**: until user deletes account
- **User rights**: access, deletion, export
- **Contact email** for data requests
- **Age requirement**: 13+ (or 16+ for EU under GDPR)

### Host them

Add `/privacy` and `/terms` routes to the existing `wcpredict-auth.vercel.app` project. Final URLs:

- `https://wcpredict-auth.vercel.app/privacy`
- `https://wcpredict-auth.vercel.app/terms`

---

## 2. Account Deletion (Apple requirement)

Apple requires apps with account creation to provide in-app account deletion (App Store Review Guideline 5.1.1(v)).

- [ ] Add "Delete account" button in Profile screen
- [ ] Implement deletion flow:
  - Delete `profiles` row
  - Delete user from `auth.users` (via Supabase admin RPC)
  - Cascade delete predictions, group memberships
- [ ] Sign out and return to sign-in screen
- [ ] Confirmation dialog before deletion

SQL helper to add as an RPC (in a new migration):
```sql
create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Cascade deletes via FK constraints on profiles/predictions/group_members
  delete from auth.users where id = auth.uid();
end;
$$;
```

Call from Flutter: `await supabase.rpc('delete_my_account');`

---

## 3. Apple App Store Submission

### App Store Connect metadata

- [ ] App name, subtitle, description
- [ ] Privacy Policy URL → `https://wcpredict-auth.vercel.app/privacy`
- [ ] Support URL (can reuse the auth site or a contact email page)
- [ ] Marketing URL (optional)
- [ ] Screenshots: 6.7" iPhone (mandatory), 6.5" iPhone, iPad if supported
- [ ] App icon: 1024×1024 PNG, no alpha (you have this in `assets/icon/`)
- [ ] Age rating: complete the questionnaire

### App Privacy section (App Store Connect → App Privacy)

Declare collected data:
- **Contact Info → Email Address** — linked to identity, used for App Functionality
- **User Content → Other** (predictions) — linked to identity, used for App Functionality
- **Identifiers → User ID** — linked to identity, used for App Functionality

### Sign in with Apple requirement

Per guideline 4.8: if you offer any third-party login, you **must** also offer Sign in with Apple. ✅ Already done.

### Production signing

- [ ] Apple Developer Account with paid membership ($99/yr)
- [ ] Distribution certificate
- [ ] App Store provisioning profile
- [ ] `Sign in with Apple` capability enabled on provisioning profile
- [ ] Increment version/build in `pubspec.yaml`
- [ ] Build: `flutter build ipa --release --dart-define=...`
- [ ] Upload via Transporter or Xcode

---

## 4. Google Play Submission

### Play Console metadata

- [ ] Privacy Policy URL (same as Apple)
- [ ] Short description (80 chars), full description
- [ ] Screenshots: phone (mandatory), 7" tablet, 10" tablet
- [ ] Feature graphic: 1024×500 PNG
- [ ] App icon: 512×512 PNG
- [ ] Content rating: complete IARC questionnaire
- [ ] Target audience: 13+

### Data safety section (Play Console → App content → Data safety)

Same disclosures as Apple. Declare:
- Email, name, user ID, app activity (predictions)
- All linked to user identity
- Used for App Functionality and Account Management
- Encrypted in transit ✅
- Users can request deletion ✅

### Production signing

- [ ] Generate release keystore (NOT the debug one):
  ```bash
  keytool -genkey -v -keystore ~/wcpredict-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias wcpredict
  ```
- [ ] Store keystore + passwords securely (1Password, etc.) — **losing this means you can never update the app**
- [ ] Create `android/key.properties` (gitignored):
  ```
  storePassword=...
  keyPassword=...
  keyAlias=wcpredict
  storeFile=/Users/danijellovric/wcpredict-release.jks
  ```
- [ ] Update `android/app/build.gradle.kts` release signingConfig to use `key.properties`
- [ ] Get release SHA-1:
  ```bash
  keytool -list -v -keystore ~/wcpredict-release.jks -alias wcpredict
  ```
- [ ] Add release SHA-1 to Google Cloud Console → Android OAuth client (alongside debug SHA-1)
- [ ] Build: `flutter build appbundle --release --dart-define=...`

---

## 5. Google OAuth Verification

Required to move from "Testing" to "Production" so any Google account can sign in.

- [ ] Privacy policy URL filled in Google Auth Platform → Branding
- [ ] Terms of Service URL filled in Branding
- [ ] Application home page URL filled in Branding
- [ ] Authorized domains added (e.g. `vercel.app` or your own domain)
- [ ] Audience page → submit for verification

**Note**: You're only using non-sensitive scopes (`email`, `profile`, `openid`), so verification is typically **fast (hours to a few days)**, not weeks. Sensitive/restricted scopes are what take 4-6 weeks.

Until verified: max 100 test users, refresh tokens expire after 7 days, users see "unverified app" warning.

---

## 6. Supabase Production Hardening

- [ ] Review RLS policies on all tables (verify `regression.test.ts` passes)
- [ ] Rotate `SUPABASE_SERVICE_ROLE_KEY` if it's ever been committed/leaked
- [ ] Enable email confirmations? (currently off — fine since we use social-only)
- [ ] Set up DB backups schedule
- [ ] Review rate limits (Authentication → Rate Limits)
- [ ] Set redirect URLs whitelist:
  - `com.dlovric.wcpredict2026://` (iOS + Android — same bundle ID)
- [ ] Set Site URL to something sane (used for email templates, even if unused)
- [ ] Disable email/password sign-in if not used (Authentication → Providers → Email → off)

---

## 7. Edge Functions / Cron

- [ ] Verify all edge functions deployed: `poll_fixtures`, `poll_live_matches`, `poll_lineups`, `lock_predictions`, `compute_scoring`
- [ ] `APISPORTS_KEY` set in Supabase Vault
- [ ] Cron schedules from `supabase/seed/cron_schedule.sql` applied to prod DB
- [ ] Monitor edge function logs for the first week post-launch

---

## 8. App Hardening

- [ ] Strip dev-only routes from release builds (`/dev/simulate` should be gated by `kDebugMode` or `kReleaseMode == false`)
- [ ] Remove `print()` calls (already done — Talker only)
- [ ] Disable `_LogFab` in release builds (or hide behind a hidden gesture)
- [ ] Verify `kUseMockData = false` for production
- [ ] Crash reporting? (Sentry/Crashlytics — currently none, Talker is in-app only)

---

## 9. Pre-submission smoke test

On a real device, release build:

- [ ] Apple Sign-In works first-time
- [ ] Google Sign-In works first-time
- [ ] Profile created with correct display name
- [ ] Sign out → sign back in works
- [ ] Predictions submit before kickoff
- [ ] Predictions lock at kickoff
- [ ] Live match shows updating scores
- [ ] Final match shows points breakdown
- [ ] Group create / join / leaderboard works
- [ ] Account deletion works end-to-end
- [ ] No `/dev/simulate` accessible

---

## Order of operations

1. **Today**: Privacy policy + Terms hosted, account deletion implemented
2. **Today**: Submit Google for OAuth verification (non-sensitive scopes → fast)
3. **This week**: TestFlight build with closed testers
4. **Once Google verified + TestFlight stable**: Submit to App Store + Play Store
