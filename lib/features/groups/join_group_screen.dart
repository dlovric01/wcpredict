import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/features/groups/invite_code.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';

Future<void> showJoinGroupSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _JoinGroupSheet(ref: ref),
  );
}

class _JoinGroupSheet extends ConsumerStatefulWidget {
  const _JoinGroupSheet({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends ConsumerState<_JoinGroupSheet> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = 'Enter a valid invite code');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await supabase
          .rpc('find_group_by_invite', params: {'p_code': code}) as List;
      if (result.isEmpty) {
        setState(() {
          _submitting = false;
          _error = 'Group not found';
        });
        return;
      }
      final group = result.first as Map<String, dynamic>;
      final user = supabase.auth.currentUser!;
      await supabase.from('group_members').upsert(
        {'group_id': group['id'], 'user_id': user.id},
        onConflict: 'group_id,user_id',
      );
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
      title: 'Join Group',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _codeCtrl,
            maxLength: kInviteCodeLength,
            decoration: InputDecoration(
              labelText: 'Invite code',
              errorText: _error,
            ),
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              letterSpacing: 4,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            onChanged: (v) {
              final upper = v.toUpperCase();
              if (upper != v) {
                _codeCtrl.value = _codeCtrl.value.copyWith(text: upper);
              }
            },
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
                : const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// Stub for backward compatibility if router still references this class.
class JoinGroupScreen extends StatelessWidget {
  const JoinGroupScreen({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
