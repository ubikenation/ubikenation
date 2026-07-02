import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'booking_screen.dart';
import 'commuter_plans_screen.dart';
import 'menu_screens.dart';
import 'terms_screen.dart';
import 'upcoming_rides_screen.dart';

/// Bolt-style home: a full-screen map with a floating bottom sheet to pick a
/// service and set a destination.
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

  @override
  void initState() {
    super.initState();
    _locate();
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
    } catch (_) {
      // location unavailable — keep the default city view
    }
  }

  void _moveToMe() {
    try {
      _map.move(_me, 15.5);
    } catch (_) {
      // map not ready yet — onMapReady will recentre
    }
  }

  void _openBooking() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final name = (context.read<AuthService>().currentUser?.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'there';

    return Scaffold(
      key: _scaffoldKey,
      drawer: _Menu(name: name),
      body: Stack(
        children: [
          AppMap(
            center: _nairobi,
            zoom: 14,
            controller: _map,
            myLocation: _me,
            onMapReady: _moveToMe,
          ),

          // Top floating controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _circleButton(Icons.menu, () => _scaffoldKey.currentState?.openDrawer()),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Image.asset('assets/logo.png', height: 22),
                  ),
                ],
              ),
            ),
          ),

          // Locate-me button just above the sheet
          Positioned(
            right: 16,
            bottom: 360,
            child: _circleButton(Icons.my_location, _locate),
          ),

          // Bottom sheet
          Align(alignment: Alignment.bottomCenter, child: _bookingSheet(name)),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppTheme.shadowSm),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: AppTheme.ink, size: 22)),
        ),
      ),
    );
  }

  Widget _bookingSheet(String name) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 28, offset: Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 18),
          Text('Hi $name 👋', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.4)),
          const SizedBox(height: 2),
          const Text('Where are you headed?', style: TextStyle(fontSize: 15, color: AppTheme.muted)),
          const SizedBox(height: 18),

          // Where to? — big tap target; opens destination search, services come after.
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            onTap: _openBooking,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(color: AppTheme.line),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.search, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('Where to?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Service tiles — both lead into the destination → service flow (rides + errands).
          Row(
            children: [
              Expanded(child: _serviceTile(Icons.directions_car_filled, 'Ride', 'Bike, car & more', _openBooking)),
              const SizedBox(width: 12),
              Expanded(child: _serviceTile(Icons.shopping_bag_rounded, 'Errand', 'Send or shop', _openBooking)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppTheme.primary, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                        Text(auth.currentUser?.email ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Trip History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TripHistoryScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Upcoming Rides'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpcomingRidesScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Commuter Plans'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommuterPlansScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Support'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms & Conditions'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsScreen()));
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
