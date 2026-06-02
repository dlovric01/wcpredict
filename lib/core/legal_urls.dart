/// Public URLs for the static legal pages served from GitHub Pages
/// (repo `dlovric01/wcpredict`, source: `master` branch / `/docs` folder).
///
/// Single source of truth — these strings are also what gets pasted into
/// App Store Connect's Support / Privacy / Marketing fields. If the
/// hosting ever moves to a custom domain, update here only.
library;

const String kLegalSiteUrl       = 'https://dlovric01.github.io/wcpredict/';
const String kPrivacyPolicyUrl   = '${kLegalSiteUrl}privacy.html';
const String kTermsOfUseUrl      = '${kLegalSiteUrl}terms.html';
const String kSupportUrl         = '${kLegalSiteUrl}support.html';
