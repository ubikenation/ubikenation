import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/rider_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'call_screen.dart';
import 'chat_screen.dart';

/// The accepted-trip workflow: confirm the price (accept the auto fare, or nudge it
/// up to +30% — no reason needed) → the customer pays 50% → trace the customer to
/// the pickup → arrived → start → reach destination → customer pays the balance →
/// complete. Reinforces the "stay online during the trip" rule.
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key, required this.tripId});
  final String tripId;

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Map<String, dynamic>? _trip;
  Map<String, dynamic>? _custLoc;
  Timer? _poll;
  String? _error;

  // Connectivity watchdog: going offline during a trip is a bannable offence.
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _wasOffline = false;
  bool _violationReported = false;

  // Push GPS frequently during the trip so the customer can track the rider.
  Timer? _locTimer;
  double? _myLat; // rider's own live position (shown + followed on the map)
  double? _myLng;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _pushLocation();
    _locTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pushLocation());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _connSub?.cancel();
    _locTimer?.cancel();
    super.dispose();
  }

  Future<void> _pushLocation() async {
    final repo = context.read<RiderRepository>();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() { _myLat = pos.latitude; _myLng = pos.longitude; });
      await repo.pushLocation(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  bool get _tripActive {
    final s = _trip?['status'] as String?;
    return s == 'rider_assigned' || s == 'arrived' || s == 'in_progress';
  }

  void _onConnectivity(List<ConnectivityResult> result) {
    final offline = result.every((r) => r == ConnectivityResult.none);
    if (offline && _tripActive) {
      _wasOffline = true;
    } else if (!offline && _wasOffline && !_violationReported) {
      // Came back online after dropping out mid-trip → record the violation.
      _violationReported = true;
      _repo.reportViolation('offline_during_trip', tripId: widget.tripId).catchError((_) {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AppTheme.red,
          content: Text('You went offline during a trip. This is a violation and has been logged.'),
        ));
      }
    }
  }

  RiderRepository get _repo => context.read<RiderRepository>();

  Future<void> _refresh() async {
    try {
      final t = await _repo.trip(widget.tripId);
      if (mounted) setState(() => _trip = t);
      // Trace the customer once they're being picked up.
      if (_tripActive) {
        final c = await _repo.customerLocation(widget.tripId);
        if (mounted) setState(() => _custLoc = c);
      }
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

  /// Accept the auto fare as-is (no adjustment → company keeps 20%).
  Future<void> _acceptAutoFare() => _run(() async {
        await _repo.quote(widget.tripId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fare confirmed. Waiting for the customer to pay.')),
          );
        }
      });

  /// Adjust the fare up to +30% (no reason). Adjusting at all → company keeps 25%.
  Future<void> _adjustFare() async {
    final trip = _trip!;
    final baseFare = (trip['base_fare'] as num).toInt();
    final maxFare = (baseFare * 1.30).round();
    double value = baseFare.toDouble();

    final proposed = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Adjust fare'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Auto fare: KES $baseFare   •   Max (+30%): KES $maxFare',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Text('KES ${value.round()}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Slider(
                value: value,
                min: baseFare.toDouble(),
                max: maxFare.toDouble(),
                divisions: (maxFare - baseFare).clamp(1, 100),
                label: 'KES ${value.round()}',
                onChanged: (v) => setLocal(() => value = v),
              ),
              const Text('Adjusting raises the company commission to 25% (you keep 75%).',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, value.round()), child: const Text('Confirm')),
          ],
        ),
      ),
    );

    if (proposed == null) return;
    await _run(() async {
      final res = await _repo.quote(widget.tripId, proposedFare: proposed);
      if (!mounted) return;
      final fare = (res['finalFare'] as num?)?.toInt() ?? proposed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fare set to KES $fare. Waiting for the customer to pay.')),
      );
    });
  }

  static const _problemReasons = [
    'Customer not at pickup',
    'Customer behaved badly',
    'Wrong/unsafe destination',
    'Payment issue',
    'Other',
  ];

  /// Opens a dispute on the active trip — admin reviews and resolves.
  Future<void> _reportProblem() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('Report a problem', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ),
            ..._problemReasons.map((r) => ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r))),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await _repo.dispute(widget.tripId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported. Our team will review this.')),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _errandDescription(Map<String, dynamic> trip) {
    if (trip['vehicle_class'] != 'errands') return '';
    final details = trip['errand_details'];
    if (details is Map && details['description'] is String) return details['description'] as String;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    // A rider can't just back out of a live trip — they must see it through (or it
    // ends via complete/dispute). Leaving is allowed once it's finished/cancelled.
    final status = trip?['status'] as String?;
    final canLeave = trip == null || ['completed', 'cancelled', 'disputed'].contains(status);
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Finish or report the trip before leaving.'), duration: Duration(seconds: 2)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Active Trip'), automaticallyImplyLeading: canLeave),
        body: SafeArea(
          child: trip == null
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Padding(padding: const EdgeInsets.all(20), child: _content(trip)),
        ),
      ),
    );
  }

  Widget _content(Map<String, dynamic> trip) {
    final status = trip['status'] as String;
    final fare = (trip['final_fare'] as num?)?.toInt() ?? (trip['base_fare'] as num).toInt();
    final adjusted = trip['adjusted'] == true;

    final pLat = (trip['pickup_lat'] as num?)?.toDouble() ?? -1.2921;
    final pLng = (trip['pickup_lng'] as num?)?.toDouble() ?? 36.8219;
    final dLat = (trip['dropoff_lat'] as num?)?.toDouble() ?? pLat;
    final dLng = (trip['dropoff_lng'] as num?)?.toDouble() ?? pLng;
    final custLat = (_custLoc?['customerLat'] as num?)?.toDouble();
    final custLng = (_custLoc?['customerLng'] as num?)?.toDouble();
    final custName = _custLoc?['customerName'] as String?;
    final inProgress = status == 'in_progress';

    // While the trip runs, follow the rider's own live position (Bolt-style) and
    // keep the relevant target (customer/pickup before start, destination after)
    // in frame. Before any GPS fix, fall back to the pickup/dropoff midpoint.
    final mapCenter = (_myLat != null && _myLng != null)
        ? LatLng(_myLat!, _myLng!)
        : LatLng((pLat + dLat) / 2, (pLng + dLng) / 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: AppMap(
              center: mapCenter,
              zoom: 14,
              follow: _tripActive,
              myLocation: (_myLat != null && _myLng != null) ? LatLng(_myLat!, _myLng!) : null,
              markers: [
                MapMarker(LatLng(pLat, pLng), color: AppTheme.primary, icon: Icons.my_location),
                MapMarker(LatLng(dLat, dLng), color: AppTheme.green, icon: Icons.location_pin),
                if (!inProgress && custLat != null && custLng != null)
                  MapMarker(LatLng(custLat, custLng), color: AppTheme.red, icon: Icons.person_pin_circle),
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
              Text('You keep ${adjusted ? '75%' : '80%'}  ·  KES ${(fare * (adjusted ? 0.75 : 0.80)).round()}',
                  style: const TextStyle(color: AppTheme.green, fontSize: 13)),
              if (custName != null && _tripActive) ...[
                const SizedBox(height: 6),
                _line(Icons.person, 'Customer: $custName'),
              ],
              const SizedBox(height: 6),
              _line(Icons.my_location, trip['pickup_address'] as String? ?? 'Pickup'),
              _line(Icons.location_on, trip['dropoff_address'] as String? ?? 'Destination'),
              if (_errandDescription(trip).isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.shopping_bag_outlined, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text('What to do: ${(trip['errand_type'] as String? ?? 'Errand').replaceAll('_', ' ')}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                      const SizedBox(height: 4),
                      Text(_errandDescription(trip), style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text('Status: ${_pretty(status)}', style: const TextStyle(color: AppTheme.primaryDark)),
            ],
          ),
        ),
        if (_tripActive) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(tripId: widget.tripId))),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Chat'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CallScreen(tripId: widget.tripId, peerName: (_custLoc?['customerName'] as String?) ?? 'Customer'),
                  )),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
              ),
            ],
          ),
        ],
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
      case 'quote_pending':
        return [
          const Text('Confirm the price to send to the customer', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _adjustFare, child: const Text('Adjust fare (up to +30%)')),
          const SizedBox(height: 10),
          FilledButton(onPressed: _acceptAutoFare, child: const Text('Accept fare')),
        ];
      case 'awaiting_payment':
        return [
          const Center(child: Text('Waiting for the customer to pay the 50% deposit…', style: TextStyle(color: AppTheme.muted))),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _refresh, child: const Text('Refresh')),
        ];
      case 'rider_assigned':
        return [
          FilledButton(onPressed: () => _run(() => _repo.markArrived(widget.tripId)), child: const Text('I have arrived')),
        ];
      case 'arrived':
        return [
          FilledButton(onPressed: () => _run(() => _repo.startTrip(widget.tripId)), child: const Text('Start Trip')),
        ];
      case 'in_progress':
        return [
          FilledButton(onPressed: () => _run(() => _repo.completeTrip(widget.tripId)), child: const Text('Reached destination')),
          const SizedBox(height: 8),
          TextButton(onPressed: _reportProblem, child: const Text('Report a problem')),
        ];
      case 'awaiting_balance':
        return [
          const Center(child: Text('Waiting for the customer to pay the balance…', style: TextStyle(color: AppTheme.muted))),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _refresh, child: const Text('Refresh')),
        ];
      case 'completed':
        return [
          const Center(child: Text('Trip completed. Your share is credited to your wallet.', style: TextStyle(color: AppTheme.green))),
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
