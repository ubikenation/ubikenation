import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';
import 'active_trip_screen.dart';
import 'earnings_screen.dart';

/// Rider home: online toggle + live list of nearby trips to accept.
/// Enforces the "must stay online during a trip" rule via the active trip screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _online = false;
  bool _busy = false;
  String? _error;
  List<AvailableTrip> _trips = [];
  Timer? _poll;
  Timer? _locationTimer;

  @override
  void dispose() {
    _poll?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<RiderRepository>();
      await repo.setOnline(value);
      setState(() => _online = value);
      if (value) {
        await _pushLocation();
        _poll = Timer.periodic(const Duration(seconds: 6), (_) => _loadTrips());
        _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocation());
        await _loadTrips();
      } else {
        _poll?.cancel();
        _locationTimer?.cancel();
        setState(() => _trips = []);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pushLocation() async {
    final repo = context.read<RiderRepository>();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      await repo.pushLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // location unavailable; skip this ping
    }
  }

  Future<void> _loadTrips() async {
    try {
      final trips = await context.read<RiderRepository>().availableTrips();
      if (mounted) setState(() => _trips = trips);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _accept(AvailableTrip trip) async {
    try {
      await context.read<RiderRepository>().accept(trip.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActiveTripScreen(tripId: trip.id)),
      );
      await _loadTrips();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('U-Bike Rider'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EarningsScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthService>().signOut()),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _onlineBar(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: AppTheme.red)),
              ),
            Expanded(child: _online ? _tripList() : _offlinePlaceholder()),
          ],
        ),
      ),
    );
  }

  Widget _onlineBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _online ? const Color(0xFFE9F7EE) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _online ? AppTheme.green : Colors.black12),
      ),
      child: Row(
        children: [
          Icon(_online ? Icons.bolt : Icons.power_settings_new,
              color: _online ? AppTheme.green : AppTheme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_online ? "You're online — receiving trips" : "You're offline",
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
          ),
          if (_busy)
            const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(value: _online, activeThumbColor: AppTheme.green, onChanged: _toggleOnline),
        ],
      ),
    );
  }

  Widget _offlinePlaceholder() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car, size: 64, color: AppTheme.muted),
            SizedBox(height: 12),
            Text('Go online to start receiving trip requests',
                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }

  Widget _tripList() {
    if (_trips.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Waiting for nearby trips…', style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _TripCard(trip: _trips[i], onAccept: () => _accept(_trips[i])),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onAccept});
  final AvailableTrip trip;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('KES ${trip.fare}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.green)),
              if (trip.pickupDistanceKm != null)
                Text('${trip.pickupDistanceKm!.toStringAsFixed(1)} km away',
                    style: const TextStyle(color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.my_location, trip.pickupAddress ?? 'Pickup'),
          _line(Icons.location_on, trip.dropoffAddress ?? 'Destination'),
          const SizedBox(height: 4),
          Text('${trip.distanceKm.toStringAsFixed(1)} km • ${trip.durationMin.toStringAsFixed(0)} min',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onAccept, child: const Text('Accept'))),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
