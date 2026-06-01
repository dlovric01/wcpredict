class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Domain hosting the AASA / assetlinks.json and the /auth/callback page.
  /// e.g. "wcpredict.vercel.app" — no scheme, no trailing slash.
  static const appLinkDomain = String.fromEnvironment('APP_LINK_DOMAIN');
}
