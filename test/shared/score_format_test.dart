// Locks the canonical score-formatting contract.
//
// Every score on the screen — hero score, match cards, fixtures list,
// half-time / extra-time / penalties sub-labels, predictions vs actual
// — funnels through `formatScore` / `formatLabeledScore`. If anyone ever
// reverts to a bare `'$a–$b'` interpolation the visual cramp returns.
// These tests make that regression noisy.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/shared/utils/score_format.dart';

void main() {
  group('formatScore', () {
    test('renders score with NBSP around en-dash (no glyph cramp)', () {
      // Hard-codes the exact bytes so a "tidy-up" PR that swaps NBSP for
      // a regular space or replaces the en-dash will fail loudly.
      expect(formatScore(0, 1), '0\u00A0\u2013\u00A01');
      expect(formatScore(2, 1), '2\u00A0\u2013\u00A01');
    });

    test('renders the agreed canonical separator', () {
      expect(kScoreSeparator, '\u00A0\u2013\u00A0');
      expect(formatScore(3, 2), '3${kScoreSeparator}2');
    });

    test('nulls default to 0 (matches DB null-safety convention)', () {
      expect(formatScore(null, null), '0\u00A0\u2013\u00A00');
      expect(formatScore(null, 1), '0\u00A0\u2013\u00A01');
      expect(formatScore(1, null), '1\u00A0\u2013\u00A00');
    });

    test('handles double-digit scores (e.g. friendlies that go wild)', () {
      expect(formatScore(10, 0), '10\u00A0\u2013\u00A00');
    });
  });

  group('formatLabeledScore', () {
    test('prefixes label with a regular space, score keeps NBSP separator',
        () {
      expect(
        formatLabeledScore('HT', 1, 0),
        'HT 1\u00A0\u2013\u00A00',
      );
      expect(
        formatLabeledScore('ET', 2, 2),
        'ET 2\u00A0\u2013\u00A02',
      );
      expect(
        formatLabeledScore('PEN', 5, 4),
        'PEN 5\u00A0\u2013\u00A04',
      );
    });

    test('label is verbatim, no transformation', () {
      expect(formatLabeledScore('(p)', 4, 3), '(p) 4\u00A0\u2013\u00A03');
    });
  });
}
