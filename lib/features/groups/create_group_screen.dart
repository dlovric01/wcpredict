import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/features/groups/group_name.dart';
import 'package:wcpredict/features/groups/invite_code.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';

Future<void> showCreateGroupSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _CreateGroupSheet(ref: ref),
  );
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final invalid = validateGroupName(name);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = supabase.auth.currentUser!;
      final code = generateInviteCode();
      final res = await supabase
          .from('groups')
          .insert({
            'name': name,
            'owner_id': user.id,
            'invite_code': code,
          })
          .select()
          .single();
      await supabase.from('group_members').insert({
        'group_id': res['id'],
        'user_id': user.id,
      });
      widget.ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: 'Create Group',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: kGroupNameMaxLength,
            decoration: InputDecoration(
              labelText: 'Group name',
              errorText: _error,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// Stub for backward compatibility if router still references this class.
class CreateGroupScreen extends StatelessWidget {
  const CreateGroupScreen({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
