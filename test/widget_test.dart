// App-wide smoke test entry point.
//
// Real coverage lives in:
//   * test/models/      — pure-Dart model unit tests (no Supabase)
//   * test/widgets/     — widget tests for shared UI components
//   * test/regression/  — Bun + supabase-js end-to-end suite (DB triggers,
//                        RLS, scoring engine, validation rules)
//
// The full app widget (lib/app.dart) needs `Supabase.initialize` to have
// run before pump, so it is not exercised here. Sub-trees that don't depend
// on a Supabase client should get their own focused test file under
// test/widgets/.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test harness loads', () {
    expect(1 + 1, 2);
  });
}
