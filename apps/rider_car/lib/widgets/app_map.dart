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
  });

  final LatLng center;
  final double zoom;
  final List<MapMarker> markers;
  final MapController? controller;
  final bool interactive;
  final VoidCallback? onMapReady;

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
      ],
    );
  }
}
