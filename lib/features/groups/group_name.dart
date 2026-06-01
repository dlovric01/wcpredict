// Shared validation for group names. Used by create + rename so the two
// flows can't drift apart (an earlier version of the app allowed creating
// a group with a 1-char name but blocked renaming to one).
//
// Rules:
//   * Trimmed.
//   * At least [kGroupNameMinLength] chars after trim — guards against
//     empty / single-character names that look like typos in the UI.
//   * At most [kGroupNameMaxLength] chars — must match the TextField
//     maxLength to avoid silent truncation surprises.

const int kGroupNameMinLength = 2;
const int kGroupNameMaxLength = 40;

/// Returns `null` when [raw] is a valid group name, or a user-facing
/// error string explaining why it's not.
String? validateGroupName(String raw) {
  final name = raw.trim();
  if (name.length < kGroupNameMinLength) {
    return 'Group name must be at least $kGroupNameMinLength characters';
  }
  if (name.length > kGroupNameMaxLength) {
    return 'Group name must be $kGroupNameMaxLength characters or fewer';
  }
  return null;
}
