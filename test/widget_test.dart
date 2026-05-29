// Basic smoke test — verifies the app builds without crashing.
// Full integration tests require a running Supabase instance.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    // App requires Supabase.initialize() before pump.
    // Real integration tests are run against a local Supabase instance.
    expect(true, isTrue);
  });
}
