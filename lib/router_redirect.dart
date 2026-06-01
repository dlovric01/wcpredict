// Pure redirect logic for `appRouter`. Extracted so it can be unit-tested
// without spinning up GoRouter or Supabase auth.
//
// Truth table (driven entirely by [loggedIn] and [location]):
//
//   logged in?  location              -> redirect
//   no          /sign-in              -> null  (already there)
//   no          /auth/callback        -> null  (callback completes auth)
//   no          any other             -> /sign-in
//   yes         /sign-in              -> /matches
//   yes         /auth/callback        -> /matches
//   yes         /                     -> /matches
//   no          /                     -> /sign-in
//   any         anything else logged-in-friendly  -> null

/// Routes that are reachable without an authenticated session.
const publicRoutes = <String>{'/sign-in', '/auth/callback'};

/// Returns the path to redirect to, or `null` to allow the navigation.
///
/// [loggedIn] reflects the current Supabase session (call site reads
/// `supabase.auth.currentUser != null`). [location] is the matched
/// location string GoRouter has resolved (e.g. `/groups/abc`).
String? computeAuthRedirect({
  required bool loggedIn,
  required String location,
}) {
  if (!loggedIn && !publicRoutes.contains(location)) return '/sign-in';
  if (loggedIn && publicRoutes.contains(location)) return '/matches';
  if (location == '/') return loggedIn ? '/matches' : '/sign-in';
  return null;
}
