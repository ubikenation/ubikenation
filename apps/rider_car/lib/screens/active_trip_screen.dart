import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';

/// The accepted-trip workflow: adjust fare (≤30%, approved reason) → arrived →
/// start → complete. Reinforces the "stay online during the trip" rule.
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key, required this.tripId});
  final String tripId;

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Map<String, dynamic>? _trip;
  Timer? _poll;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  RiderRepository get _repo => context.read<RiderRepository>();

  Future<void> _refresh() async {
    try {
      final t = await _repo.trip(widget.tripId);
      if (mounted) setState(() => _trip = t);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _adjustFare() async {
    final trip = _trip!;
    final baseFare = (trip['base_fare'] as num).toInt();
    final maxFare = (baseFare * 1.30).round();
    final amountCtrl = TextEditingController(text: baseFare.toString());
    String reason = AdjustmentReasons.all.first.value;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Adjust Fare'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Original: KES $baseFare  •  Max (+30%): KES $maxFare',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: AdjustmentReasons.all
                    .map((r) => DropdownMenuItem(value: r.value, child: Text(r.label)))
                    .toList(),
                onChanged: (v) => setLocal(() => reason = v ?? reason),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'New fare (KES)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final proposed = int.tryParse(amountCtrl.text) ?? baseFare;
    await _run(() async {
      final res = await _repo.adjustFare(widget.tripId, proposed, reason);
      if (!mounted) return;
      final approved = res['approved'] == true;
      final capped = (res['cappedFare'] as num?)?.toInt() ?? proposed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved
            ? 'Sent KES $capped to customer for approval'
            : 'Capped to KES $capped (+30% limit)'),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(title: const Text('Active Trip')),
      body: SafeArea(
        child: trip == null
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : Padding(padding: const EdgeInsets.all(20), child: _content(trip)),
      ),
    );
  }

  Widget _content(Map<String, dynamic> trip) {
    final status = trip['status'] as String;
    final fare = (trip['final_fare'] as num?)?.toInt() ?? (trip['base_fare'] as num).toInt();

    final pLat = (trip['pickup_lat'] as num?)?.toDouble() ?? -1.2921;
    final pLng = (trip['pickup_lng'] as num?)?.toDouble() ?? 36.8219;
    final dLat = (trip['dropoff_lat'] as num?)?.toDouble() ?? pLat;
    final dLng = (trip['dropoff_lng'] as num?)?.toDouble() ?? pLng;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 180,
            child: AppMap(
              center: LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
              zoom: 12,
              interactive: false,
              markers: [
                MapMarker(LatLng(pLat, pLng), color: AppTheme.primary, icon: Icons.my_location),
                MapMarker(LatLng(dLat, dLng), color: AppTheme.green, icon: Icons.location_pin),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fare: KES $fare', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _line(Icons.my_location, trip['pickup_address'] as String? ?? 'Pickup'),
              _line(Icons.location_on, trip['dropoff_address'] as String? ?? 'Destination'),
              const SizedBox(height: 6),
              Text('Status: ${_pretty(status)}', style: const TextStyle(color: AppTheme.primaryDark)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              Icon(Icons.gpp_good, color: Color(0xFFB8860B)),
              SizedBox(width: 8),
              Expanded(child: Text('Stay online with GPS on for the whole trip.', style: TextStyle(fontSize: 13))),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppTheme.red)),
          ),
        const Spacer(),
        ..._actions(status),
      ],
    );
  }

  List<Widget> _actions(String status) {
    switch (status) {
      case 'rider_assigned':
        return [
          OutlinedButton(onPressed: _adjustFare, child: const Text('Adjust Fare (reason required)')),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => _run(() => _repo.markArrived(widget.tripId)), child: const Text('I have arrived')),
        ];
      case 'arrived':
        return [
          FilledButton(onPressed: () => _run(() => _repo.startTrip(widget.tripId)), child: const Text('Start Trip')),
        ];
      case 'in_progress':
        return [
          FilledButton(onPressed: () => _run(() => _repo.completeTrip(widget.tripId)), child: const Text('Complete Trip')),
        ];
      case 'completed':
        return [
          const Center(child: Text('Trip completed. 80% credited to your wallet.', style: TextStyle(color: AppTheme.green))),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to Home')),
        ];
      default:
        return [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        ];
    }
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );

  String _pretty(String s) => s.replaceAll('_', ' ');
}
