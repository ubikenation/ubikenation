import 'dart:convert';
import 'package:http/http.dart' as http;

/// A geocoded place result.
class Place {
  final String name; // full place name, e.g. "Maua, Meru, Kenya"
  final String shortName; // primary text, e.g. "Maua"
  final double lat;
  final double lng;
  const Place({required this.name, required this.shortName, required this.lat, required this.lng});
}

/// Mapbox geocoding restricted to Kenya, biased toward Meru County (launch area).
/// Handles place search suggestions (forward) and current-location naming (reverse).
class GeocodingService {
  GeocodingService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const String _token = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

  // Bias point: Meru town.
  static const double meruLng = 37.6559;
  static const double meruLat = 0.0463;

  Future<List<Place>> search(String query, {double? nearLat, double? nearLng}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final prox = '${nearLng ?? meruLng},${nearLat ?? meruLat}';
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json'
      '?access_token=$_token&country=ke&proximity=$prox&autocomplete=true&limit=6&language=en'
      '&types=place,locality,neighborhood,address,poi,district',
    );
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List<dynamic>?) ?? [];
      return features.map(_toPlace).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> reverse(double lat, double lng) async {
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
      '?access_token=$_token&country=ke&limit=1&language=en'
      '&types=place,locality,neighborhood,address,poi',
    );
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List<dynamic>?) ?? [];
      if (features.isEmpty) return null;
      return (features.first as Map<String, dynamic>)['place_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Place _toPlace(dynamic f) {
    final m = f as Map<String, dynamic>;
    final center = (m['center'] as List).cast<num>();
    return Place(
      name: m['place_name'] as String? ?? m['text'] as String? ?? '',
      shortName: m['text'] as String? ?? '',
      lng: center[0].toDouble(),
      lat: center[1].toDouble(),
    );
  }
}
