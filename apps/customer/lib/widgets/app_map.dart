import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A marker to drop on [AppMap].
class MapMarker {
  const MapMarker(this.point, {this.color = const Color(0xFF12A0D7), this.icon = Icons.location_pin});
  final LatLng point;
  final Color color;
  final IconData icon;
}

/// Mapbox-backed map (raster tiles via flutter_map — no native SDK / API-key
/// gymnastics). Works with the public Mapbox access token.
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.center,
    this.zoom = 14,
    this.markers = const [],
    this.controller,
    this.interactive = true,
    this.onMapReady,
    this.myLocation,
    this.onCenterChanged,
  });

  final LatLng center;
  final double zoom;
  final List<MapMarker> markers;
  final MapController? controller;
  final bool interactive;
  final VoidCallback? onMapReady;

  /// Called with the map's centre whenever the user pans/zooms — used to pick a
  /// pickup point by dragging the map under a fixed pin (Bolt-style).
  final void Function(LatLng center)? onCenterChanged;

  /// When set, draws a fancy pulsing blue "you are here" dot.
  final LatLng? myLocation;

  // Provided at build time: --dart-define=MAPBOX_ACCESS_TOKEN=pk....
  static const String _token = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onMapReady: onMapReady,
        onPositionChanged: onCenterChanged == null ? null : (camera, _) => onCenterChanged!(camera.center),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$_token',
          userAgentPackageName: 'com.ubike',
        ),
        if (markers.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final m in markers)
                Marker(
                  point: m.point,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: Icon(m.icon, color: m.color, size: 40),
                ),
            ],
          ),
        if (myLocation != null)
          MarkerLayer(
            markers: [
              Marker(point: myLocation!, width: 90, height: 90, child: const _PulsingDot()),
            ],
          ),
      ],
    );
  }
}

/// Animated "current location" indicator: a solid blue dot with a white ring and
/// an expanding, fading halo (Uber/Bolt style).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1E88E5);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // expanding halo
            Container(
              width: 24 + t * 60,
              height: 24 + t * 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: blue.withValues(alpha: (1 - t) * 0.25),
              ),
            ),
            // white ring
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: blue.withValues(alpha: 0.4), blurRadius: 8)],
              ),
            ),
            // solid dot
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: blue),
            ),
          ],
        );
      },
    );
  }
}
