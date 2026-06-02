// ============================================================================
// Frontend-only mock data for the Groups tab.
//
// Enabled by `--dart-define=MOCK_GROUPS=true` (release builds included so the
// switch works for `flutter build --release` App Store screenshots). When the
// flag is on, the three Groups providers in `groups_provider.dart` short-circuit
// to the data below instead of hitting Supabase.
//
// The current user is folded in at runtime: the placeholder UUID for "Danijel"
// in the standings, members, and group owner is replaced with the real signed-in
// user's id so the "YOU" highlight, the owner-only settings button, and any
// other `auth.currentUser` checks light up correctly. Other mocked users keep
// fixed placeholder UUIDs.
// ============================================================================

import 'package:wcpredict/core/models/group_model.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';

const bool kMockGroups = bool.fromEnvironment('MOCK_GROUPS');

// ── IDs ─────────────────────────────────────────────────────────────────────
//
// Real Postgres `groups.id` and `auth.users.id` are UUIDs. We use UUID-shaped
// strings for the mocks so the models and any string-equality checks behave
// identically to production data.

const String mockGroupFriendsId = '00000000-0000-0000-0000-0000000000a1';
const String mockGroupOfficeId  = '00000000-0000-0000-0000-0000000000a2';

const String _aliceId   = '00000000-0000-0000-0000-0000000000b1';
const String _bobId     = '00000000-0000-0000-0000-0000000000b2';
const String _charlieId = '00000000-0000-0000-0000-0000000000b3';
const String _eviId     = '00000000-0000-0000-0000-0000000000b4';
const String _jakubId   = '00000000-0000-0000-0000-0000000000b5';

/// Placeholder for the signed-in user. Whatever value the provider gets from
/// `currentUserIdProvider` is substituted in for this constant at runtime.
const String _mePlaceholder = '00000000-0000-0000-0000-0000000000c0';

String _me(String? currentUserId) => currentUserId ?? _mePlaceholder;

// ── Groups ─────────────────────────────────────────────────────────────────

List<GroupModel> mockGroupsList({required String? currentUserId}) {
  final me = _me(currentUserId);
  return [
    GroupModel(
      id: mockGroupFriendsId,
      name: 'WC Friends',
      ownerId: me,
      inviteCode: 'WCFRIENDS',
      createdAt: DateTime.utc(2026, 5, 28, 14, 30),
    ),
    GroupModel(
      id: mockGroupOfficeId,
      name: 'Office Rivals',
      ownerId: _aliceId, // not owned by current user — settings button hidden
      inviteCode: 'OFFICE26',
      createdAt: DateTime.utc(2026, 5, 30, 9, 15),
    ),
  ];
}

// ── Members ────────────────────────────────────────────────────────────────

List<ProfileModel> mockGroupMembers({
  required String groupId,
  required String? currentUserId,
}) {
  final me = _me(currentUserId);
  final base = [
    ProfileModel(userId: _aliceId,   displayName: 'Alice',   createdAt: DateTime.utc(2026, 5, 20)),
    ProfileModel(userId: me,         displayName: 'Danijel', createdAt: DateTime.utc(2026, 5, 22)),
    ProfileModel(userId: _bobId,     displayName: 'Bob',     createdAt: DateTime.utc(2026, 5, 23)),
    ProfileModel(userId: _charlieId, displayName: 'Charlie', createdAt: DateTime.utc(2026, 5, 25)),
  ];
  if (groupId == mockGroupOfficeId) {
    return [
      ...base,
      ProfileModel(userId: _eviId,   displayName: 'Evi',     createdAt: DateTime.utc(2026, 5, 27)),
      ProfileModel(userId: _jakubId, displayName: 'Jakub',   createdAt: DateTime.utc(2026, 5, 29)),
    ];
  }
  return base;
}

// ── Standings ──────────────────────────────────────────────────────────────

List<GroupStandingModel> mockGroupStandings({
  required String groupId,
  required String? currentUserId,
}) {
  final me = _me(currentUserId);

  if (groupId == mockGroupFriendsId) {
    return [
      GroupStandingModel(
        groupId: groupId,
        userId: _aliceId,
        displayName: 'Alice',
        totalPoints: 138,
        matchPoints: 138,
        tournamentPoints: 0,
        exactCount: 6,
        scorerCount: 4,
        firstTeamCount: 5,
        goalDiffCount: 3,
        outcomeCount: 2,
        earliestSubmission: DateTime.utc(2026, 5, 28, 12, 4),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: me,
        displayName: 'Danijel',
        totalPoints: 124,
        matchPoints: 124,
        tournamentPoints: 0,
        exactCount: 4,
        scorerCount: 3,
        firstTeamCount: 5,
        goalDiffCount: 4,
        outcomeCount: 3,
        earliestSubmission: DateTime.utc(2026, 5, 28, 18, 22),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _bobId,
        displayName: 'Bob',
        totalPoints: 109,
        matchPoints: 109,
        tournamentPoints: 0,
        exactCount: 3,
        scorerCount: 5,
        firstTeamCount: 4,
        goalDiffCount: 2,
        outcomeCount: 4,
        earliestSubmission: DateTime.utc(2026, 5, 29, 9, 12),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _charlieId,
        displayName: 'Charlie',
        totalPoints: 67,
        matchPoints: 67,
        tournamentPoints: 0,
        exactCount: 1,
        scorerCount: 2,
        firstTeamCount: 2,
        goalDiffCount: 3,
        outcomeCount: 5,
        earliestSubmission: DateTime.utc(2026, 5, 30, 21, 47),
      ),
    ];
  }

  if (groupId == mockGroupOfficeId) {
    return [
      GroupStandingModel(
        groupId: groupId,
        userId: me,
        displayName: 'Danijel',
        totalPoints: 124,
        matchPoints: 124,
        tournamentPoints: 0,
        exactCount: 4,
        scorerCount: 3,
        firstTeamCount: 5,
        goalDiffCount: 4,
        outcomeCount: 3,
        earliestSubmission: DateTime.utc(2026, 5, 28, 18, 22),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _jakubId,
        displayName: 'Jakub',
        totalPoints: 118,
        matchPoints: 118,
        tournamentPoints: 0,
        exactCount: 4,
        scorerCount: 4,
        firstTeamCount: 3,
        goalDiffCount: 3,
        outcomeCount: 4,
        earliestSubmission: DateTime.utc(2026, 5, 29, 11, 30),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _aliceId,
        displayName: 'Alice',
        totalPoints: 113,
        matchPoints: 113,
        tournamentPoints: 0,
        exactCount: 5,
        scorerCount: 3,
        firstTeamCount: 3,
        goalDiffCount: 2,
        outcomeCount: 3,
        earliestSubmission: DateTime.utc(2026, 5, 28, 12, 4),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _eviId,
        displayName: 'Evi',
        totalPoints: 88,
        matchPoints: 88,
        tournamentPoints: 0,
        exactCount: 2,
        scorerCount: 3,
        firstTeamCount: 3,
        goalDiffCount: 3,
        outcomeCount: 4,
        earliestSubmission: DateTime.utc(2026, 5, 30, 8, 5),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _bobId,
        displayName: 'Bob',
        totalPoints: 74,
        matchPoints: 74,
        tournamentPoints: 0,
        exactCount: 2,
        scorerCount: 2,
        firstTeamCount: 2,
        goalDiffCount: 2,
        outcomeCount: 5,
        earliestSubmission: DateTime.utc(2026, 5, 29, 9, 12),
      ),
      GroupStandingModel(
        groupId: groupId,
        userId: _charlieId,
        displayName: 'Charlie',
        totalPoints: 41,
        matchPoints: 41,
        tournamentPoints: 0,
        exactCount: 0,
        scorerCount: 1,
        firstTeamCount: 2,
        goalDiffCount: 2,
        outcomeCount: 4,
        earliestSubmission: DateTime.utc(2026, 5, 30, 21, 47),
      ),
    ];
  }

  return const [];
}
