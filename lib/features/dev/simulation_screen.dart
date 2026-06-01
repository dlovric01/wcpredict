import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/mock_bracket.dart';

// ---------------------------------------------------------------------------
// Simulation steps
// ---------------------------------------------------------------------------

enum _SimStep {
  idle,
  setup,       // FRA vs BRA created, lineups inserted
  kickoff,     // live, 0-0
  goal1,       // BRA 0-1 Vinícius Jr. 23'
  card,        // yellow Tchouaméni 31'
  sub,         // Dembélé → Giroud 46'
  goal2,       // FRA 1-1 Mbappé 67'
  goal3,       // FRA 2-1 Mbappé pen 88'
  fullTime,    // final, scoring fired
  done,
}

extension on _SimStep {
  String get nextButtonLabel => switch (this) {
        _SimStep.idle     => 'Create match + insert lineups',
        _SimStep.setup    => 'Kick off',
        _SimStep.kickoff  => 'Brazil score — Vinícius Jr. (23\')',
        _SimStep.goal1    => 'Yellow card — Tchouaméni (31\')',
        _SimStep.card     => 'Sub — Dembélé → Giroud (46\')',
        _SimStep.sub      => 'France equalise — Mbappé (67\')',
        _SimStep.goal2    => 'France winner — Mbappé pen (88\')',
        _SimStep.goal3    => 'Full time  FRA 2–1 BRA',
        _SimStep.fullTime => '',
        _SimStep.done     => '',
      };

  bool get hasNext    => this != _SimStep.fullTime && this != _SimStep.done;
  bool get canCleanup => this != _SimStep.idle && this != _SimStep.done;
  bool get canOpen    => this != _SimStep.idle && this != _SimStep.done;
}


// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SimulationScreen extends ConsumerStatefulWidget {
  const SimulationScreen({super.key});

  @override
  ConsumerState<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends ConsumerState<SimulationScreen> {
  _SimStep _step = _SimStep.idle;
  bool _loading = false;
  String? _error;
  final List<String> _log = [];

  void _addLog(String msg) {
    setState(() => _log.insert(0, '${TimeOfDay.now().format(context)}  $msg'));
  }

  Future<void> _runNext() async {
    setState(() { _loading = true; _error = null; });
    try {
      switch (_step) {
        case _SimStep.idle:
          await _rpc(0, 'FRA vs BRA created — lineups ready, open match detail after kickoff');
          setState(() => _step = _SimStep.setup);
        case _SimStep.setup:
          await _rpc(1, 'Kicked off — 0 : 0  →  check home live strip');
          setState(() => _step = _SimStep.kickoff);
        case _SimStep.kickoff:
          await _rpc(2, 'Goal! Vinícius Jr. 23\'  —  FRA 0 : 1 BRA');
          setState(() => _step = _SimStep.goal1);
        case _SimStep.goal1:
          await _rpc(3, 'Yellow card — Tchouaméni 31\'');
          setState(() => _step = _SimStep.card);
        case _SimStep.card:
          await _rpc(4, 'Sub: Dembélé → Giroud 46\'');
          setState(() => _step = _SimStep.sub);
        case _SimStep.sub:
          await _rpc(5, 'Goal! Mbappé 67\'  —  FRA 1 : 1 BRA');
          setState(() => _step = _SimStep.goal2);
        case _SimStep.goal2:
          await _rpc(6, 'Goal! Mbappé pen 88\'  —  FRA 2 : 1 BRA');
          setState(() => _step = _SimStep.goal3);
        case _SimStep.goal3:
          await _rpc(7, 'Full time! FRA 2-1 BRA — scoring trigger fired');
          setState(() => _step = _SimStep.fullTime);
        default:
          break;
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _rpc(int step, String logMsg) async {
    await supabase.rpc('simulate_live_match', params: {'step_num': step});
    _addLog(logMsg);
  }

  Future<void> _cleanup() async {
    setState(() { _loading = true; _error = null; });
    try {
      await supabase.rpc('simulate_live_match', params: {'step_num': 99});
      setState(() {
        _step = _SimStep.done;
        _log.insert(0, '${TimeOfDay.now().format(context)}  Cleaned up — test data removed');
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        title: const Text('Live Match Simulator'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status card ──────────────────────────────────────────────────
          _StatusCard(step: _step),
          const SizedBox(height: 16),

          // ── Error ────────────────────────────────────────────────────────
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: Text(_error!, style: tt.bodySmall?.copyWith(color: AppColors.error)),
            ),

          // ── Action buttons ───────────────────────────────────────────────
          if (_step.hasNext)
            FilledButton(
              onPressed: _loading ? null : _runNext,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: AppRadii.pillRadius),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : Text(_step.nextButtonLabel),
            ),

          if (_step.canOpen) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/matches/$kSimMatchId'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: AppRadii.pillRadius),
              ),
              child: const Text('Open in Match Detail →'),
            ),
          ],

          if (_step.canCleanup) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : _cleanup,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Cleanup — delete test data'),
            ),
          ],

          const SizedBox(height: 24),

          // ── Log ──────────────────────────────────────────────────────────
          if (_log.isNotEmpty) ...[
            Text('Log', style: tt.labelLarge?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (final entry in _log)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(entry,
                          style: tt.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontFamily: 'monospace')),
                    ),
                  ],
                ),
              ),
          ],

          // ── Hint ─────────────────────────────────────────────────────────
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: AppRadii.cardRadius,
            ),
            child: Text(
              'After Kick off — keep this screen open and tap "Open in Match Detail". '
              'Then press each step here and watch the score and events update in the '
              'match detail screen without touching it.',
              style: tt.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status card
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.step});
  final _SimStep step;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final (score, statusLabel, statusColor) = switch (step) {
      _SimStep.idle     => ('— : —', 'Not started',  AppColors.onSurfaceMuted),
      _SimStep.setup    => ('— : —', 'SCHEDULED',    AppColors.onSurfaceVariant),
      _SimStep.kickoff  => ('0 : 0', 'LIVE',          AppColors.live),
      _SimStep.goal1    => ('0 : 1', 'LIVE',          AppColors.live),
      _SimStep.card     => ('0 : 1', 'LIVE',          AppColors.live),
      _SimStep.sub      => ('0 : 1', 'LIVE',          AppColors.live),
      _SimStep.goal2    => ('1 : 1', 'LIVE',          AppColors.live),
      _SimStep.goal3    => ('2 : 1', 'LIVE',          AppColors.live),
      _SimStep.fullTime => ('2 : 1', 'FT',            AppColors.onSurfaceVariant),
      _SimStep.done     => ('— : —', 'Cleaned up',    AppColors.onSurfaceMuted),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('FRA', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(score,
                  style: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text('BRA', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel,
                style: tt.labelSmall?.copyWith(
                    color: statusColor, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}
