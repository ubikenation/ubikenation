import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';

/// Shows the upfront-payment step, then polls the trip status through its
/// lifecycle (searching → assigned → in progress → completed → rate).
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.trip, required this.paymentUrl});
  final Trip trip;
  final String paymentUrl;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late Trip _trip;
  Timer? _poll;
  int _rating = 5;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final t = await context.read<TripRepository>().getTrip(_trip.id);
      if (mounted) setState(() => _trip = t);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Your Trip')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_trip.status) {
      case 'pending_payment':
        return _PaymentStep(url: widget.paymentUrl, upfront: _trip.upfront, onPaid: _refresh);
      case 'searching':
        return _statusBlock(Icons.search, 'Finding you a nearby rider…', showCancel: true);
      case 'rider_assigned':
      case 'arrived':
        return _statusBlock(Icons.directions_bike, 'Rider assigned and on the way', showCancel: true);
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
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({required this.url, required this.upfront, required this.onPaid});
  final String url;
  final int upfront;
  final Future<void> Function() onPaid;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock, size: 56, color: AppTheme.primary),
        const SizedBox(height: 12),
        Text('Pay KES $upfront (50%) to confirm',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Secure checkout via Paystack', style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 24),
        SelectableText(url, style: const TextStyle(fontSize: 12, color: AppTheme.primaryDark)),
        const Spacer(),
        FilledButton(
          onPressed: onPaid,
          child: const Text("I've paid — continue"),
        ),
      ],
    );
  }
}
