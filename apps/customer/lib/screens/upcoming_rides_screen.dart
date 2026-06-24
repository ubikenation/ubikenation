import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/trip_repository.dart';
import '../theme/app_theme.dart';

final _fmt = DateFormat('EEE d MMM, h:mm a');

/// Lists the customer's scheduled (not-yet-started) rides and lets them cancel
/// one before it goes out to matching.
class UpcomingRidesScreen extends StatefulWidget {
  const UpcomingRidesScreen({super.key});

  @override
  State<UpcomingRidesScreen> createState() => _UpcomingRidesScreenState();
}

class _UpcomingRidesScreenState extends State<UpcomingRidesScreen> {
  List<Map<String, dynamic>> _rides = [];
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
      final all = await context.read<TripRepository>().myTrips();
      if (!mounted) return;
      setState(() {
        _rides = all.where((t) => t['status'] == 'scheduled').toList();
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

  Future<void> _cancel(String id) async {
    final repo = context.read<TripRepository>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scheduled ride?'),
        content: const Text('This upcoming ride will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel ride')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await repo.cancelTrip(id, reason: 'scheduled_cancelled');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming rides')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red)))])
                : _rides.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(children: [
                            Icon(Icons.event_available, size: 56, color: AppTheme.muted),
                            SizedBox(height: 12),
                            Text('No upcoming scheduled rides.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
                          ]),
                        )
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rides.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _rideCard(_rides[i]),
                      ),
      ),
    );
  }

  Widget _rideCard(Map<String, dynamic> t) {
    final when = t['scheduled_for'] != null ? _fmt.format(DateTime.parse(t['scheduled_for'] as String).toLocal()) : 'Scheduled';
    final fare = (t['final_fare'] as num?)?.toInt() ?? (t['base_fare'] as num?)?.toInt() ?? 0;
    final dest = t['dropoff_address'] as String? ?? t['errand_type'] as String? ?? 'Destination';
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
              const Icon(Icons.schedule, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(when, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink))),
              Text('~KES $fare', style: const TextStyle(color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(dest, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _cancel(t['id'] as String),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}
