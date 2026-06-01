// Locks down group-name validation. Earlier versions of the app drifted
// between create (`isEmpty` check, allowing 1-char names) and rename
// (`length < 2`, blocking 1-char names). One source of truth now.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/features/groups/group_name.dart';

void main() {
  group('validateGroupName', () {
    test('empty string rejected', () {
      expect(validateGroupName(''), isNotNull);
    });

    test('single character rejected (min is 2)', () {
      expect(validateGroupName('X'), isNotNull);
      expect(validateGroupName('X'), contains('at least 2'));
    });

    test('whitespace-only rejected (trimmed)', () {
      expect(validateGroupName('   '), isNotNull);
    });

    test('exactly 2 chars accepted', () {
      expect(validateGroupName('OK'), isNull);
    });

    test('exactly kGroupNameMaxLength chars accepted', () {
      final name = 'a' * kGroupNameMaxLength;
      expect(name.length, kGroupNameMaxLength);
      expect(validateGroupName(name), isNull);
    });

    test('one over max rejected', () {
      final name = 'a' * (kGroupNameMaxLength + 1);
      expect(validateGroupName(name), isNotNull);
      expect(validateGroupName(name), contains('or fewer'));
    });

    test('trims whitespace before checking length', () {
      // " OK " → "OK" → valid (length 2)
      expect(validateGroupName(' OK '), isNull);
      // " X " → "X" → invalid (length 1)
      expect(validateGroupName(' X '), isNotNull);
    });

    test('min and max constants are sane', () {
      expect(kGroupNameMinLength, greaterThan(0));
      expect(kGroupNameMaxLength, greaterThan(kGroupNameMinLength));
    });
  });
}
