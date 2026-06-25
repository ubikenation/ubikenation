import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'active_trip_screen.dart';
import 'earnings_screen.dart';

/// Bolt-driver-style home. The rider is automatically ONLINE whenever the app is
/// open and connected (enforced app-wide by the connectivity gate) — there is no
/// manual offline switch. Losing data/Wi-Fi during a trip is a bannable offence,
/// handled on the active-trip screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _map = MapController();
  static const LatLng _nairobi = LatLng(0.0463, 37.6559);
  LatLng _me = _nairobi;

  bool _ready = false;
  String? _error;
  List<AvailableTrip> _trips = [];
  Timer? _poll;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _locate();
    _goOnline();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  void _moveToMe() {
    try {
      _map.move(_me, 15);
    } catch (_) {}
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
      _moveToMe();
    } catch (_) {}
  }

  /// Automatically goes online and starts receiving requests + pushing location.
  Future<void> _goOnline() async {
    try {
      final repo = context.read<RiderRepository>();
      await repo.setOnline(true);
      if (!mounted) return;
      setState(() => _ready = true);
      await _pushLocation();
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => _loadTrips());
      _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocation());
      await _loadTrips();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pushLocation() async {
    final repo = context.read<RiderRepository>();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _me = LatLng(pos.latitude, pos.longitude));
      await repo.pushLocation(pos.latitude, pos.longitude);
    } catch (_) {}
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
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActiveTripScreen(tripId: trip.id)));
      await _loadTrips();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Rider passes on a request (explicit decline, or the offer countdown expired):
  /// hide it locally and tell the backend so it's offered to a different rider.
  Future<void> _decline(AvailableTrip trip) async {
    setState(() => _trips = _trips.where((t) => t.id != trip.id).toList());
    try {
      await context.read<RiderRepository>().decline(trip.id);
    } catch (_) {/* best-effort; it just won't be hidden server-side */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const _Menu(),
      body: Stack(
        children: [
          AppMap(
            center: _nairobi,
            zoom: 14,
            controller: _map,
            markers: [MapMarker(_me, color: AppTheme.primary, icon: Icons.my_location)],
            onMapReady: _moveToMe,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _circle(Icons.menu, () => _scaffoldKey.currentState?.openDrawer()),
                  const Spacer(),
                  _onlinePill(),
                  const Spacer(),
                  _circle(Icons.account_balance_wallet_outlined, () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EarningsScreen()));
                  }),
                ],
              ),
            ),
          ),
          Positioned(right: 16, bottom: 280, child: _circle(Icons.my_location, _locate)),
          Align(alignment: Alignment.bottomCenter, child: _sheet()),
        ],
      ),
    );
  }

  Widget _onlinePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.green,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 16, color: Colors.white),
          SizedBox(width: 6),
          Text('Online', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, color: AppTheme.ink)),
      ),
    );
  }

  Widget _sheet() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42, height: 4,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Icon(Icons.bolt, color: AppTheme.green, size: 20),
              SizedBox(width: 6),
              Expanded(
                child: Text("You're online — receiving requests",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Keep data or Wi-Fi on. Stay online for the whole trip.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 13)),
            ),
          const SizedBox(height: 8),
          Flexible(child: _tripList()),
        ],
      ),
    );
  }

  Widget _tripList() {
    if (!_ready || _trips.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 14),
            Text('Waiting for nearby trips…', style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 4),
      itemCount: _trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _TripCard(
        key: ValueKey(_trips[i].id),
        trip: _trips[i],
        onAccept: () => _accept(_trips[i]),
        onDecline: () => _decline(_trips[i]),
        onExpire: () => _decline(_trips[i]),
      ),
    );
  }
}

/// A request offer with a countdown (Bolt-style). If the rider doesn't accept
/// before the timer runs out, the offer expires and passes to another rider.
class _TripCard extends StatefulWidget {
  const _TripCard({super.key, required this.trip, required this.onAccept, required this.onDecline, required this.onExpire});
  final AvailableTrip trip;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onExpire;

  @override
  State<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<_TripCard> {
  static const _seconds = 30;
  int _left = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        widget.onExpire();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('KES ${trip.fare}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.green)),
              if (trip.pickupDistanceKm != null)
                Text('${trip.pickupDistanceKm!.toStringAsFixed(1)} km away', style: const TextStyle(color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 8),
          // Offer countdown bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _left / _seconds,
              minHeight: 5,
              backgroundColor: Colors.black12,
              color: _left <= 8 ? AppTheme.red : AppTheme.green,
            ),
          ),
          const SizedBox(height: 4),
          Text('Respond in ${_left}s', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          const SizedBox(height: 6),
          _line(Icons.my_location, trip.pickupAddress ?? 'Pickup'),
          _line(Icons.location_on, trip.dropoffAddress ?? 'Destination'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: widget.onDecline, child: const Text('Decline')),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(onPressed: widget.onAccept, child: const Text('Accept')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _Menu extends StatelessWidget {
  const _Menu();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final name = auth.currentUser?.userMetadata?['full_name'] as String? ?? 'Rider';
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/logo.png', height: 30),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.ink)),
                  Text(auth.currentUser?.email ?? '', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Earnings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EarningsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Support'),
              onTap: () {
                Navigator.pop(context);
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Rider Support'),
                    content: const Text(
                      'Need help?\n\n'
                      '• Keep data/Wi-Fi and GPS on for the whole trip — going offline mid-trip is a violation.\n'
                      '• You keep 80% of every trip (75% if you adjust the fare); payouts hit your M-Pesa in 24–48h.\n'
                      '• You may adjust a fare up to 30% — no reason needed.\n\n'
                      'Contact: support@ubike.co.ke',
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                  ),
                );
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.muted),
              title: const Text('Log out'),
              onTap: () => auth.signOut(),
            ),
          ],
        ),
      ),
    );
  }
}
