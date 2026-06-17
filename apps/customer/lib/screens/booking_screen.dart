import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import 'trip_screen.dart';

/// Collects pickup + destination, gets a fare estimate, then creates the trip
/// and launches the 50% upfront payment.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.category});
  final ServiceCategory category;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  // Defaults around Nairobi CBD so the flow is testable without a map picker.
  final double _pickupLat = -1.2921, _pickupLng = 36.8219;
  final double _dropLat = -1.3000, _dropLng = 36.7800;
  final _pickupCtrl = TextEditingController(text: 'Current location');
  final _dropCtrl = TextEditingController(text: 'Destination');

  FareQuote? _quote;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    super.dispose();
  }

  double get _distanceKm =>
      _haversine(_pickupLat, _pickupLng, _dropLat, _dropLng);

  // Rough duration estimate; backend recomputes fare authoritatively on create.
  double get _durationMin => _distanceKm / 22 * 60; // ~22 km/h urban avg

  Future<void> _estimate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<TripRepository>();
      final q = await repo.estimateFare(
        vehicleClass: widget.category.id,
        distanceKm: double.parse(_distanceKm.toStringAsFixed(2)),
        durationMin: double.parse(_durationMin.toStringAsFixed(1)),
      );
      setState(() => _quote = q);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bookAndPay() async {
    final quote = _quote;
    if (quote == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<TripRepository>();
      final trip = await repo.createTrip(
        tripType: widget.category.tripType,
        vehicleClass: widget.category.id,
        pickupLat: _pickupLat,
        pickupLng: _pickupLng,
        pickupAddress: _pickupCtrl.text,
        dropoffLat: _dropLat,
        dropoffLng: _dropLng,
        dropoffAddress: _dropCtrl.text,
        distanceKm: double.parse(_distanceKm.toStringAsFixed(2)),
        durationMin: double.parse(_durationMin.toStringAsFixed(1)),
      );
      final payUrl = await repo.initiateUpfront(trip.id, trip.upfront);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripScreen(trip: trip, paymentUrl: payUrl)),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _LocationField(controller: _pickupCtrl, icon: Icons.my_location, label: 'Pickup'),
            const SizedBox(height: 12),
            _LocationField(controller: _dropCtrl, icon: Icons.location_on, label: 'Destination'),
            const SizedBox(height: 16),
            Text('Estimated distance: ${_distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            if (q != null) _FareCard(quote: q),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            if (q == null)
              FilledButton(
                onPressed: _busy ? null : _estimate,
                child: _busy ? const _Loader() : const Text('Get Fare Estimate'),
              )
            else
              FilledButton(
                onPressed: _busy ? null : _bookAndPay,
                child: _busy ? const _Loader() : Text('Pay KES ${q.upfront} (50%) & Request'),
              ),
          ],
        ),
      ),
    );
  }

  static double _haversine(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = _rad(bLat - aLat);
    final dLng = _rad(bLng - aLng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(aLat)) * math.cos(_rad(bLat)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _rad(double d) => d * math.pi / 180;
}

class _LocationField extends StatelessWidget {
  const _LocationField({required this.controller, required this.icon, required this.label});
  final TextEditingController controller;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: AppTheme.primary)),
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.quote});
  final FareQuote quote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          _row('Total fare', 'KES ${quote.fare}', bold: true),
          const Divider(),
          _row('Pay now (50%)', 'KES ${quote.upfront}'),
          _row('Pay after trip (50%)', 'KES ${quote.balance}'),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 18 : 14,
      color: AppTheme.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
}
