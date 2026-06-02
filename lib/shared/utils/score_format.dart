/// Score-formatting helpers.
///
/// Renders the dash with non-breaking spaces on either side so the digits
/// never visually glue to the en-dash at large display sizes (the default
/// en-dash glyph has tight side-bearings — at displaySmall/Medium "0–1"
/// reads as a single token). NBSP keeps the whole score on one line.
///
/// Tests in `test/shared/score_format_test.dart` lock the separator.
library;

/// Non-breaking space + en-dash + non-breaking space.
///
/// `\u00A0` (NBSP) is visually identical to a regular space but won't wrap;
/// `\u2013` is the en-dash codepoint, which is the conventional scoreboard
/// separator (narrower than a minus, wider than a hyphen).
const String kScoreSeparator = '\u00A0\u2013\u00A0';

/// Formats a score pair as `"a – b"`, defaulting null to 0.
///
/// Use in any place that previously interpolated `'${a}–${b}'` so every
/// score on the screen shares the same separator and side-bearings.
String formatScore(int? a, int? b) =>
    '${a ?? 0}$kScoreSeparator${b ?? 0}';

/// Same as [formatScore] but prefixed with a leading label such as
/// `"HT"`, `"ET"`, or `"PEN"`. The label is separated by a regular space
/// (it may wrap independently of the score if the parent is narrow).
String formatLabeledScore(String label, int? a, int? b) =>
    '$label ${formatScore(a, b)}';
