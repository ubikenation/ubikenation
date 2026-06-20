import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/trip_repository.dart';
import '../theme/app_theme.dart';

/// Lists the customer's recurring "commuter plans" (subscription errands) and
/// lets them pause, resume or cancel each one.
class CommuterPlansScreen extends StatefulWidget {
  const CommuterPlansScreen({super.key});

  @override
  State<CommuterPlansScreen> createState() => _CommuterPlansScreenState();
}

class _CommuterPlansScreenState extends State<CommuterPlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await context.read<TripRepository>().myPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _action(String id, String action) async {
    final repo = context.read<TripRepository>();
    try {
      await repo.setPlan(id, action);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  String _freqLabel(String f) => switch (f) {
        'daily' => 'Every day',
        'weekdays' => 'Weekdays',
        'weekly' => 'Weekly',
        _ => f,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commuter plans')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red)))])
                : _plans.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(children: [
                            Icon(Icons.repeat, size: 56, color: AppTheme.muted),
                            SizedBox(height: 12),
                            Text('No commuter plans yet.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
                            SizedBox(height: 6),
                            Text('Create one from an errand to repeat it automatically.',
                                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                          ]),
                        )
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _plans.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _planCard(_plans[i]),
                      ),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> p) {
    final status = p['status'] as String? ?? 'active';
    final fare = (p['fare_estimate'] as num?)?.toInt() ?? 0;
    final type = (p['errand_type'] as String? ?? '').replaceAll('_', ' ');
    final desc = (p['description'] as String? ?? '').split('\n').first;
    final freq = _freqLabel(p['frequency'] as String? ?? '');
    final time = (p['time_of_day'] as String? ?? '').toString();
    final id = p['id'] as String;

    Color badge = switch (status) {
      'active' => AppTheme.accent,
      'paused' => Colors.orange,
      _ => AppTheme.muted,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(type.isEmpty ? 'Errand' : type[0].toUpperCase() + type.substring(1),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: badge.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: badge, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted))),
          const SizedBox(height: 6),
          Text('$freq at ${time.length >= 5 ? time.substring(0, 5) : time}  ·  est. KES $fare/run',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 10),
          if (status != 'cancelled')
            Row(
              children: [
                if (status == 'active')
                  OutlinedButton(onPressed: () => _action(id, 'pause'), child: const Text('Pause'))
                else
                  OutlinedButton(onPressed: () => _action(id, 'resume'), child: const Text('Resume')),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => _action(id, 'cancel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
