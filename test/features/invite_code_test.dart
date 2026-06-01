// Locks down the invite-code generator + the create/regenerate/join
// length contract. An earlier version of the app shipped a regression
// where regenerate produced 8-char codes that the join field truncated
// to 6 — making regenerated codes un-typeable. This test fails fast if
// the constant or the generator drift again.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/features/groups/invite_code.dart';

void main() {
  group('invite code generator', () {
    test('every code is exactly kInviteCodeLength chars (8)', () {
      expect(kInviteCodeLength, 8,
          reason: 'create / regenerate / join input maxLength all read '
              'kInviteCodeLength — changing it must be deliberate.');
      // Sample a healthy number so we'd catch any off-by-one in substring().
      for (var i = 0; i < 200; i++) {
        final code = generateInviteCode();
        expect(code.length, kInviteCodeLength,
            reason: 'iteration $i produced "$code" (len=${code.length})');
      }
    });

    test('code is uppercase hex (alphanumeric, no dashes)', () {
      final code = generateInviteCode();
      expect(code, matches(RegExp(r'^[0-9A-F]{8}$')),
          reason: 'codes are derived from v4 UUID hex with dashes stripped');
    });

    test('two consecutive codes differ with overwhelming probability', () {
      // v4 UUID-derived → ~32 bits of entropy in 8 hex chars. Collision
      // odds are 1 / 2^32 per pair — astronomically unlikely in a unit test.
      final a = generateInviteCode();
      final b = generateInviteCode();
      expect(a, isNot(equals(b)));
    });

    test('codes are unique across a small batch (no obvious determinism)', () {
      // Tighter check against accidental sequential / time-based sources
      // like the old microsecond-base36 algorithm.
      final batch = List.generate(100, (_) => generateInviteCode()).toSet();
      expect(batch.length, 100, reason: 'expected 100 unique codes');
    });
  });
}
