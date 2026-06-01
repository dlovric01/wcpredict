import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/features/groups/create_group_screen.dart';
import 'package:wcpredict/features/groups/join_group_screen.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';

class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGroups = ref.watch(
      myGroupsProvider.select((a) => a.valueOrNull?.isNotEmpty ?? false),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          if (hasGroups)
            IconButton(
              icon: const Icon(Symbols.add),
              onPressed: () => _showGroupActions(context, ref),
            ),
        ],
      ),
      body: _GroupsList(),
    );
  }
}

void _showGroupActions(BuildContext parentContext, WidgetRef ref) {
  // The action sheet itself is a modal — opening another modal from
  // inside its ListTile onTap fires AFTER Navigator.pop(sheetContext),
  // which deactivates the sheet's BuildContext. Using that stale
  // context for `showModalBottomSheet` produces a "black screen" sheet
  // (no theme / MediaQuery inheritance). Capture the screen's context
  // here and pass it to the nested sheet instead.
  showAppSheet<void>(
    context: parentContext,
    builder: (sheetContext) => AppSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Symbols.group_add, color: AppColors.primary),
            title: const Text('Create new group'),
            onTap: () {
              Navigator.pop(sheetContext);
              showCreateGroupSheet(parentContext, ref);
            },
          ),
          ListTile(
            leading: Icon(Symbols.login, color: AppColors.tertiary),
            title: const Text('Join with invite code'),
            onTap: () {
              Navigator.pop(sheetContext);
              showJoinGroupSheet(parentContext, ref);
            },
          ),
        ],
      ),
    ),
  );
}

class _GroupsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: AppColors.error),
        ),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.groups,
                      size: 72, color: AppColors.onSurfaceMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No groups yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join or create a group to compete with friends',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => showCreateGroupSheet(context, ref),
                    child: const Text('Create a group'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    onPressed: () => showJoinGroupSheet(context, ref),
                    child: const Text('Join with code'),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myGroupsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              return _GroupTile(
                name: group.name,
                initial:
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                onTap: () => context.push('/groups/${group.id}'),
              )
                  .animate(delay: Duration(milliseconds: i * 60))
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.1, end: 0, duration: 280.ms);
            },
          ),
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.name,
    required this.initial,
    required this.onTap,
  });

  final String name;
  final String initial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryContainer,
              child: Text(
                initial,
                style: TextStyle(
                  color: AppColors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(name),
            subtitle: Text(
              'Your group',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
