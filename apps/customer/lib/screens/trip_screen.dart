import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';

/// Polls the trip status and, once a rider is assigned, shows the rider moving
/// toward you on a live map with distance + ETA — Bolt/Uber style.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.trip});
  final Trip trip;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late Trip _trip;
  Timer? _poll;
  int _rating = 5;
  Map<String, dynamic>? _riderLoc;

  static const _trackStatuses = {'rider_assigned', 'arrived', 'in_progress'};

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = context.read<TripRepository>();
    try {
      final t = await repo.getTrip(_trip.id);
      if (mounted) setState(() => _trip = t);
      if (_trackStatuses.contains(t.status)) {
        final loc = await repo.riderLocation(_trip.id);
        if (mounted) setState(() => _riderLoc = loc);
      }
      if (t.status == 'completed' || t.status == 'cancelled') _poll?.cancel();
    } catch (_) {
      // transient; keep polling
    }
  }

  Future<void> _cancel() async {
    await context.read<TripRepository>().cancelTrip(_trip.id, reason: 'customer_cancel');
    await _refresh();
  }

  Future<void> _submitRating() async {
    await context.read<TripRepository>().rate(_trip.id, _rating);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _trackStatuses.contains(_trip.status) && _riderLoc != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Your Trip')),
      body: SafeArea(
        child: tracking ? _trackingView() : Padding(padding: const EdgeInsets.all(20), child: _body()),
      ),
    );
  }

  // -------- Live tracking --------
  Widget _trackingView() {
    final loc = _riderLoc!;
    final riderLat = (loc['riderLat'] as num?)?.toDouble();
    final riderLng = (loc['riderLng'] as num?)?.toDouble();
    final pickupLat = (loc['pickupLat'] as num?)?.toDouble() ?? -0.0463;
    final pickupLng = (loc['pickupLng'] as num?)?.toDouble() ?? 37.6559;
    final dropLat = (loc['dropoffLat'] as num?)?.toDouble();
    final dropLng = (loc['dropoffLng'] as num?)?.toDouble();
    final inProgress = _trip.status == 'in_progress';

    // Target the rider is heading to, for distance/ETA.
    final targetLat = inProgress ? (dropLat ?? pickupLat) : pickupLat;
    final targetLng = inProgress ? (dropLng ?? pickupLng) : pickupLng;

    double? km;
    if (riderLat != null && riderLng != null) {
      km = _haversine(riderLat, riderLng, targetLat, targetLng);
    }
    final etaMin = km != null ? math.max(1, (km / 22 * 60).round()) : null;

    final markers = <MapMarker>[
      if (dropLat != null && dropLng != null) MapMarker(LatLng(dropLat, dropLng), color: AppTheme.accent, icon: Icons.location_pin),
      if (riderLat != null && riderLng != null) MapMarker(LatLng(riderLat, riderLng), color: AppTheme.accent, icon: Icons.navigation),
    ];
    final center = (riderLat != null && riderLng != null)
        ? LatLng((riderLat + targetLat) / 2, (riderLng + targetLng) / 2)
        : LatLng(pickupLat, pickupLng);

    final name = loc['riderName'] as String? ?? 'Your rider';
    final rating = (loc['rating'] as num?)?.toDouble() ?? 5.0;

    return Column(
      children: [
        Expanded(
          child: AppMap(
            center: center,
            zoom: 13.5,
            myLocation: LatLng(pickupLat, pickupLng),
            markers: markers,
          ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, -4))],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _trip.status == 'arrived'
                    ? 'Your rider has arrived'
                    : inProgress
                        ? 'On the way to your destination'
                        : 'Your rider is on the way',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.ink),
              ),
              const SizedBox(height: 4),
              if (km != null)
                Text('${km.toStringAsFixed(1)} km away  ·  ~$etaMin min',
                    style: const TextStyle(color: AppTheme.muted))
              else
                const Text('Locating your rider…', style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const CircleAvatar(radius: 22, backgroundColor: AppTheme.surface, child: Icon(Icons.person, color: AppTheme.primary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                        Row(children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(rating.toStringAsFixed(1), style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                        ]),
                      ],
                    ),
                  ),
                  Text('KES ${_trip.fare}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
                ],
              ),
              if (_trip.status != 'in_progress') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel (full refund before start)')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -------- Non-tracking states --------
  Widget _body() {
    switch (_trip.status) {
      case 'pending_payment':
        return _statusBlock(Icons.lock_clock, 'Confirming your payment…');
      case 'searching':
        return _statusBlock(Icons.search, 'Finding you the closest rider…', showCancel: true);
      case 'rider_assigned':
      case 'arrived':
        return _statusBlock(Icons.directions_bike, 'Rider assigned — loading live map…', showCancel: true);
      case 'in_progress':
        return _statusBlock(Icons.navigation, 'Trip in progress — enjoy the ride');
      case 'completed':
        return _ratingBlock();
      case 'cancelled':
        return _statusBlock(Icons.cancel, 'Trip cancelled. Refund issued to your wallet.');
      default:
        return _statusBlock(Icons.info, 'Status: ${_trip.status}');
    }
  }

  Widget _statusBlock(IconData icon, String text, {bool showCancel = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppTheme.ink)),
        const SizedBox(height: 8),
        Text('Fare: KES ${_trip.fare}', style: const TextStyle(color: AppTheme.muted)),
        const Spacer(),
        if (showCancel)
          OutlinedButton(onPressed: _cancel, child: const Text('Cancel (full refund before start)')),
      ],
    );
  }

  Widget _ratingBlock() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 64, color: AppTheme.accent),
        const SizedBox(height: 12),
        const Text('Trip completed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Balance due: KES ${_trip.balance}', style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 20),
        const Text('Rate your rider'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            return IconButton(
              icon: Icon(i < _rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36),
              onPressed: () => setState(() => _rating = i + 1),
            );
          }),
        ),
        const Spacer(),
        FilledButton(onPressed: _submitRating, child: const Text('Submit & Finish')),
      ],
    );
  }

  static double _haversine(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLng = (bLng - aLng) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(aLat * math.pi / 180) * math.cos(bLat * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}
