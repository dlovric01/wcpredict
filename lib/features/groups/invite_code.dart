// Single source of truth for invite-code generation.
//
// All three call sites (create group, regenerate code, join input maxLength)
// MUST use [kInviteCodeLength] to stay in sync — earlier versions of this
// app drifted (6 vs 8 chars), so users with a regenerated 8-char code
// couldn't paste it into the join sheet that capped input at 6.

import 'package:uuid/uuid.dart';

/// Length of every invite code the app generates today. Existing groups
/// with shorter codes from older versions still work — `join` accepts up
/// to this many characters with a minimum floor enforced separately.
const int kInviteCodeLength = 8;

/// Generates a fresh invite code from a v4 UUID (cryptographically random).
String generateInviteCode() => const Uuid()
    .v4()
    .replaceAll('-', '')
    .substring(0, kInviteCodeLength)
    .toUpperCase();
