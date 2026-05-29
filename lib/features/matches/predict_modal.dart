import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/player_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';

// ---------------------------------------------------------------------------
// Public helper — show the modal
// ---------------------------------------------------------------------------
Future<void> showPredictModal(
  BuildContext context, {
  required MatchModel match,
  PredictionModel? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PredictModal(match: match, existing: existing),
  );
}

// ---------------------------------------------------------------------------
// Modal widget
// ---------------------------------------------------------------------------
class PredictModal extends ConsumerStatefulWidget {
  const PredictModal({super.key, required this.match, this.existing});

  final MatchModel match;
  final PredictionModel? existing;

  @override
  ConsumerState<PredictModal> createState() => _PredictModalState();
}

class _PredictModalState extends ConsumerState<PredictModal> {
  late int _score1;
  late int _score2;
  int? _firstTeamId;
  int? _scorerId;
  bool _saving = false;
  String _playerSearch = '';

  bool get _isZeroZero => _score1 == 0 && _score2 == 0;
  bool get _locked => widget.match.isLocked;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _score1 = p?.predictedTeam1 ?? 0;
    _score2 = p?.predictedTeam2 ?? 0;
    _firstTeamId = p?.predictedFirstTeamId;
    _scorerId = p?.predictedScorerId;
  }

  void _setScore1(int v) {
    setState(() {
      _score1 = v.clamp(0, 20);
      _clearConditionalIfNeeded();
    });
  }

  void _setScore2(int v) {
    setState(() {
      _score2 = v.clamp(0, 20);
      _clearConditionalIfNeeded();
    });
  }

  void _clearConditionalIfNeeded() {
    if (_isZeroZero) {
      _firstTeamId = null;
      _scorerId = null;
    }
  }

  List<PlayerModel> get _allPlayers {
    final t1 = widget.match.team1?.players ?? [];
    final t2 = widget.match.team2?.players ?? [];
    return [...t1, ...t2];
  }

  List<PlayerModel> get _filteredPlayers {
    if (_playerSearch.isEmpty) return _allPlayers;
    final q = _playerSearch.toLowerCase();
    return _allPlayers
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _save() async {
    if (_locked) return;
    setState(() => _saving = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      await supabase.from('predictions').upsert(
        {
          'user_id': user.id,
          'match_id': widget.match.id,
          'predicted_team1': _score1,
          'predicted_team2': _score2,
          'predicted_first_team_id': _isZeroZero ? null : _firstTeamId,
          'predicted_scorer_id': _isZeroZero ? null : _scorerId,
        },
        onConflict: 'user_id,match_id',
      );

      // Invalidate cached prediction so parent refreshes
      ref.invalidate(myPredictionProvider(widget.match.id));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prediction saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t1 = widget.match.team1;
    final t2 = widget.match.team2;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Your Prediction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (_locked)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Text(
                    'Match has started — predictions are locked.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // ── Section 1: Score pickers ────────────────────────────
                _SectionHeader(title: 'Score'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            t1?.code ?? 'T1',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _ScorePicker(
                            value: _score1,
                            onChanged: _locked ? null : _setScore1,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '—',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            t2?.code ?? 'T2',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _ScorePicker(
                            value: _score2,
                            onChanged: _locked ? null : _setScore2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Sections 2 & 3: only when score != 0-0 ─────────────
                if (!_isZeroZero) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  _SectionHeader(title: 'First team to score'),
                  const SizedBox(height: 4),
                  RadioGroup<int>(
                    groupValue: _firstTeamId ?? 0,
                    onChanged: _locked
                        ? (_) {}
                        : (v) => setState(() => _firstTeamId = v),
                    child: Column(
                      children: [
                        RadioListTile<int>(
                          value: t1?.id ?? 0,
                          title: Text(t1?.name ?? 'Team 1'),
                          dense: true,
                        ),
                        RadioListTile<int>(
                          value: t2?.id ?? 0,
                          title: Text(t2?.name ?? 'Team 2'),
                          dense: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  _SectionHeader(title: 'Goalscorer (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search player…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _playerSearch = v),
                    enabled: !_locked,
                  ),
                  const SizedBox(height: 8),
                  // Group by team
                  if (t1 != null)
                    _PlayerGroup(
                      teamName: t1.name,
                      players: _filteredPlayers
                          .where((p) => p.teamId == t1.id)
                          .toList(),
                      selectedId: _scorerId,
                      onSelect: _locked
                          ? null
                          : (id) => setState(() {
                                _scorerId = _scorerId == id ? null : id;
                              }),
                    ),
                  if (t2 != null)
                    _PlayerGroup(
                      teamName: t2.name,
                      players: _filteredPlayers
                          .where((p) => p.teamId == t2.id)
                          .toList(),
                      selectedId: _scorerId,
                      onSelect: _locked
                          ? null
                          : (id) => setState(() {
                                _scorerId = _scorerId == id ? null : id;
                              }),
                    ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
          // ── Save button ───────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_locked || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_locked ? 'Locked' : 'Save Prediction'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Colors.grey[600]),
    );
  }
}

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({required this.value, required this.onChanged});

  final int value;
  final void Function(int)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onChanged == null || value <= 0
              ? null
              : () => onChanged!(value - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onChanged == null || value >= 20
              ? null
              : () => onChanged!(value + 1),
        ),
      ],
    );
  }
}

class _PlayerGroup extends StatelessWidget {
  const _PlayerGroup({
    required this.teamName,
    required this.players,
    required this.selectedId,
    required this.onSelect,
  });

  final String teamName;
  final List<PlayerModel> players;
  final int? selectedId;
  final void Function(int)? onSelect;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            teamName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...players.map((p) => ListTile(
              dense: true,
              selected: p.id == selectedId,
              selectedTileColor:
                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
              leading: _PositionBadge(position: p.position),
              title: Text(p.name),
              trailing: p.jerseyNumber != null
                  ? Text('#${p.jerseyNumber}',
                      style: const TextStyle(color: Colors.grey))
                  : null,
              onTap: onSelect == null ? null : () => onSelect!(p.id),
            )),
      ],
    );
  }
}

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({this.position});
  final String? position;

  @override
  Widget build(BuildContext context) {
    final label = switch (position) {
      'GK' => 'GK',
      'DEF' || 'DF' || 'CB' || 'LB' || 'RB' || 'LWB' || 'RWB' => 'DEF',
      'MID' || 'MF' || 'CM' || 'DM' || 'AM' || 'LM' || 'RM' => 'MID',
      'FWD' || 'FW' || 'ST' || 'LW' || 'RW' || 'CF' || 'SS' => 'FWD',
      _ => '—',
    };
    final color = switch (label) {
      'GK' => Colors.yellow.shade700,
      'DEF' => Colors.blue.shade600,
      'MID' => Colors.green.shade600,
      'FWD' => Colors.red.shade600,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
