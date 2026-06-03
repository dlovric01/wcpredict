library;

/// Player-name display helpers shared across the match-detail screen.
///
/// The convention mirrors broadcast graphics and most other football
/// apps: drop the first name to an initial when the full name has at
/// least two tokens and is "long enough" to risk overflowing a chip
/// or pill — "Christian Pulisic" → "C. Pulisic", "Lyle Foster" stays
/// "Lyle Foster". Single-token names ("Pulisic", "Ronaldinho") and
/// already-abbreviated names ("C. Pulisic") are returned unchanged.

const int _kAbbreviateThreshold = 14;

/// Returns the abbreviated form of [fullName] (first name → single
/// initial) when the full string is longer than [threshold] characters.
/// Otherwise returns [fullName] unchanged.
///
/// Idempotent: calling on an already-abbreviated name is a no-op.
String abbreviateFullName(String fullName, {int threshold = _kAbbreviateThreshold}) {
  if (fullName.length <= threshold) return fullName;
  final tokens = fullName.split(RegExp(r'\s+'));
  if (tokens.length < 2) return fullName;
  final first = tokens.first;
  if (first.length <= 1 || first.endsWith('.')) return fullName;
  return '${first[0]}. ${tokens.skip(1).join(' ')}';
}
