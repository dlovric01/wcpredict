import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/group_model.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';

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
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.red))),
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
      const SnackBar(content: Text('Invite code copied!')),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _OwnerSettingsSheet(group: widget.group, ref: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name),
            GestureDetector(
              onTap: () => _copyCode(context),
              child: Chip(
                label: Text(
                  group.inviteCode ?? 'No code',
                  style: const TextStyle(fontSize: 11),
                ),
                avatar: const Icon(Icons.copy, size: 14),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
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
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _LeaderboardTab(groupId: group.id),
          _MembersTab(groupId: group.id),
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
      error: (e, _) =>
          Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (standings) {
        if (standings.isEmpty) {
          return const Center(child: Text('No standings yet.'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupStandingsProvider(groupId)),
          child: ListView.builder(
            itemCount: standings.length,
            itemBuilder: (context, i) =>
                _StandingRow(rank: i + 1, standing: standings[i]),
          ),
        );
      },
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.rank, required this.standing});
  final int rank;
  final GroupStandingModel standing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: rank == 1
            ? Colors.amber
            : rank == 2
                ? Colors.grey.shade400
                : rank == 3
                    ? Colors.brown.shade300
                    : cs.surfaceContainerHighest,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: rank <= 3 ? Colors.white : cs.onSurface,
          ),
        ),
      ),
      title: Text(standing.displayName ?? 'Anonymous'),
      subtitle: Text(
          '${standing.exactCount} exact · ${standing.correctResultCount} result'),
      trailing: Text(
        '${standing.totalPoints} pts',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: cs.primary),
      ),
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
      error: (e, _) =>
          Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (members) {
        if (members.isEmpty) {
          return const Center(child: Text('No members found.'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupMembersProvider(groupId)),
          child: ListView.builder(
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
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: profile.avatarUrl != null
            ? NetworkImage(profile.avatarUrl!)
            : null,
        child: profile.avatarUrl == null
            ? Text((profile.displayName?.isNotEmpty ?? false)
                ? profile.displayName![0].toUpperCase()
                : '?')
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
    if (newName.length < 2) return;
    setState(() => _loading = true);
    try {
      await supabase
          .from('groups')
          .update({'name': newName})
          .eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerateCode() async {
    setState(() => _loading = true);
    try {
      final newCode = DateTime.now()
          .microsecondsSinceEpoch
          .toRadixString(36)
          .toUpperCase()
          .padRight(8, '0')
          .substring(0, 8);
      await supabase
          .from('groups')
          .update({'invite_code': newCode})
          .eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New code: $newCode')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
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
      await supabase
          .from('groups')
          .delete()
          .eq('id', widget.group.id);
      ref.invalidate(myGroupsProvider);
      if (mounted) {
        Navigator.pop(context); // close sheet
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Group Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
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
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Delete Group',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
