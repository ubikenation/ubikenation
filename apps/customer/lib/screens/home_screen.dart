import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'booking_screen.dart';

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
  static const LatLng _nairobi = LatLng(-1.2921, 36.8219);
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

  void _openBooking(ServiceCategory category) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingScreen(category: category)));
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
            markers: [MapMarker(_me, color: AppTheme.primary, icon: Icons.my_location)],
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
            bottom: 300,
            child: _circleButton(Icons.my_location, _locate),
          ),

          // Bottom sheet
          Align(alignment: Alignment.bottomCenter, child: _bookingSheet(name)),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
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

  Widget _bookingSheet(String name) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Hi $name 👋', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.ink)),
          const SizedBox(height: 14),

          // Where to? search bar
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openBooking(ServiceCategory.all.first),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: const [
                  Icon(Icons.search, color: AppTheme.primary),
                  SizedBox(width: 12),
                  Text('Where to?', style: TextStyle(fontSize: 16, color: AppTheme.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          const Text('Choose a service', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ServiceCategory.all.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _serviceCard(ServiceCategory.all[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(ServiceCategory c) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openBooking(c),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(c.icon, color: AppTheme.primary, size: 30),
            const SizedBox(height: 8),
            Text(c.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            Text('KES ${c.minFare}+', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/logo.png', height: 32),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.ink)),
                  Text(auth.currentUser?.email ?? '', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ),
            ),
            const Divider(),
            const ListTile(leading: Icon(Icons.history), title: Text('Trip History')),
            const ListTile(leading: Icon(Icons.account_balance_wallet_outlined), title: Text('Wallet')),
            const ListTile(leading: Icon(Icons.help_outline), title: Text('Support')),
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
