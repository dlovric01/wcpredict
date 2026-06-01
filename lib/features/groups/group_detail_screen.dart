import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/features/groups/invite_code.dart';
import 'package:wcpredict/features/groups/group_name.dart';
import 'package:wcpredict/core/models/group_model.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';
import 'package:go_router/go_router.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return groupsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text('Error: $e', style: TextStyle(color: AppColors.error)),
        ),
      ),
      data: (groups) {
        final group = groups.cast<GroupModel?>().firstWhere(
              (g) => g?.id == groupId,
              orElse: () => null,
            );
        if (group == null) {
          return const Scaffold(
            body: Center(child: Text('Group not found.')),
          );
        }
        return _GroupDetailBody(group: group);
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _GroupDetailBody extends ConsumerStatefulWidget {
  const _GroupDetailBody({required this.group});
  final GroupModel group;

  @override
  ConsumerState<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends ConsumerState<_GroupDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner {
    final user = supabase.auth.currentUser;
    return user != null && user.id == widget.group.ownerId;
  }

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.group.inviteCode ?? ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied!')),
    );
  }

  void _showSettings(BuildContext context) {
    showAppSheet<void>(
      context: context,
      builder: (_) => _OwnerSettingsSheet(group: widget.group, ref: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _showSettings(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Leaderboard'),
            Tab(text: 'Members'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppRadii.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      if (_isOwner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryContainer,
                            borderRadius: AppRadii.pillRadius,
                          ),
                          child: Text(
                            'Owner',
                            style: textTheme.labelSmall?.copyWith(
                              color: AppColors.onSecondaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _copyCode(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHighest,
                        borderRadius: AppRadii.pillRadius,
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy,
                              size: 14, color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            group.inviteCode ?? '—',
                            style: textTheme.labelLarge?.copyWith(
                              letterSpacing: 4,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _LeaderboardTab(groupId: group.id),
                _MembersTab(groupId: group.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LeaderboardTab extends ConsumerWidget {
  const _LeaderboardTab({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standingsAsync = ref.watch(groupStandingsProvider(groupId));

    return standingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: AppColors.error)),
      ),
      data: (standings) {
        if (standings.isEmpty) {
          return Center(
            child: Text(
              'No standings yet.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(groupStandingsProvider(groupId)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: standings.length,
            itemBuilder: (context, i) =>
                _StandingRow(rank: i + 1, standing: standings[i]),
          ),
        );
      },
    );
  }
}

class _StandingRow extends ConsumerWidget {
  const _StandingRow({required this.rank, required this.standing});
  final int rank;
  final GroupStandingModel standing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final currentUserId = supabase.auth.currentUser?.id;
    final isMe = standing.userId == currentUserId;

    Widget rankWidget;
    if (rank <= 3) {
      final medalColor = rank == 1
          ? AppColors.gold
          : rank == 2
              ? AppColors.silver
              : AppColors.bronze;
      rankWidget = CircleAvatar(
        backgroundColor: medalColor,
        radius: 18,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.onPrimary,
            fontSize: 13,
          ),
        ),
      );
    } else {
      rankWidget = SizedBox(
        width: 36,
        child: Center(
          child: Text(
            '$rank',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ),
      );
    }

    Widget trailing = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${standing.totalPoints}',
          style: textTheme.titleMedium?.copyWith(
            color: AppColors.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isMe)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadii.pillRadius,
            ),
            child: Text(
              'YOU',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 9,
              ),
            ),
          ),
      ],
    );

    final tile = ListTile(
      leading: rankWidget,
      title: Text(standing.displayName ?? 'Anonymous'),
      subtitle: Text(
        '${standing.exactCount} exact · ${standing.scorerCount} scorer · '
        '${standing.firstTeamCount} 1st · ${standing.goalDiffCount} GD'
        '${standing.tournamentPoints > 0 ? " · +${standing.tournamentPoints} bonus" : ""}',
        style:
            textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
      ),
      trailing: trailing,
      onTap: () => context.push(
        '/members/${standing.userId}',
        extra: {
          'displayName': standing.displayName ?? 'Anonymous',
          'totalPoints': standing.totalPoints,
          'exactCount': standing.exactCount,
          'outcomeCount': standing.outcomeCount,
          'goalDiffCount': standing.goalDiffCount,
          'scorerCount': standing.scorerCount,
          'firstTeamCount': standing.firstTeamCount,
        },
      ),
    );

    if (isMe) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withValues(alpha: 0.12),
          borderRadius: AppRadii.cardRadius,
          border: Border(
            left: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        child: tile,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: tile,
    );
  }
}

// ---------------------------------------------------------------------------

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: AppColors.error)),
      ),
      data: (members) {
        if (members.isEmpty) {
          return Center(
            child: Text(
              'No members found.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupMembersProvider(groupId)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: members.length,
            itemBuilder: (context, i) => _MemberRow(profile: members[i]),
          ),
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.profile});
  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    final initial = (profile.displayName?.isNotEmpty ?? false)
        ? profile.displayName![0].toUpperCase()
        : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceHighest,
        backgroundImage:
            profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
        child: profile.avatarUrl == null
            ? Text(initial, style: TextStyle(color: AppColors.onSurfaceVariant))
            : null,
      ),
      title: Text(profile.displayName ?? 'Anonymous'),
    );
  }
}

// ---------------------------------------------------------------------------

class _OwnerSettingsSheet extends ConsumerStatefulWidget {
  const _OwnerSettingsSheet({required this.group, required this.ref});
  final GroupModel group;
  final WidgetRef ref;

  @override
  ConsumerState<_OwnerSettingsSheet> createState() =>
      _OwnerSettingsSheetState();
}

class _OwnerSettingsSheetState extends ConsumerState<_OwnerSettingsSheet> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.group.name;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final newName = _nameCtrl.text.trim();
    if (validateGroupName(newName) != null) return;
    setState(() => _loading = true);
    try {
      await supabase
          .from('groups')
          .update({'name': newName}).eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerateCode() async {
    setState(() => _loading = true);
    try {
      final newCode = generateInviteCode();
      await supabase
          .from('groups')
          .update({'invite_code': newCode}).eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('New code: $newCode')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete group?'),
        content: const Text(
            'This will remove the group and all members. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await supabase
          .from('group_members')
          .delete()
          .eq('group_id', widget.group.id);
      await supabase.from('groups').delete().eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: 'Group Settings',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: kGroupNameMaxLength,
            decoration: const InputDecoration(
              labelText: 'Group name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _loading ? null : _rename,
            child: const Text('Save Name'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _regenerateCode,
            icon: const Icon(Icons.refresh),
            label: const Text('Regenerate Invite Code'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loading ? null : _deleteGroup,
            icon: Icon(Icons.delete_outline, color: AppColors.error),
            label:
                Text('Delete Group', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
