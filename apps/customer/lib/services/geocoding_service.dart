import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// A geocoded place result.
class Place {
  final String name; // full place name, e.g. "Maua, Meru, Kenya"
  final String shortName; // primary text, e.g. "Maua"
  final double lat;
  final double lng;
  const Place({required this.name, required this.shortName, required this.lat, required this.lng});
}

/// Mapbox geocoding restricted to Kenya, biased toward Meru County (launch area).
/// A curated Meru County dataset is searched first so even the smallest towns —
/// which Mapbox sometimes lacks (e.g. Nkubu, Nchiru, Mutuati) — always appear.
class GeocodingService {
  GeocodingService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const String _token = AppConfig.mapboxToken;
  static const String _googleKey = AppConfig.googleMapsApiKey;

  // Bias point: Meru town.
  static const double meruLng = 37.6559;
  static const double meruLat = 0.0463;

  /// Curated Meru County towns, wards, markets and landmarks (lat, lng).
  /// These guarantee local coverage; Mapbox results are appended after.
  static const List<({String name, double lat, double lng})> _meru = [
    (name: 'Meru Town', lat: 0.0474, lng: 37.6556),
    (name: 'Makutano', lat: 0.0520, lng: 37.6440),
    (name: 'Gakoromone Market', lat: 0.0455, lng: 37.6515),
    (name: 'Kaaga', lat: 0.0680, lng: 37.6600),
    (name: 'Gitoro', lat: 0.0760, lng: 37.6720),
    (name: 'Kinoru', lat: 0.0500, lng: 37.6460),
    (name: 'Kithoka', lat: 0.0900, lng: 37.6500),
    (name: 'Kaongo', lat: 0.0300, lng: 37.6500),
    (name: 'Nchiru', lat: 0.1003, lng: 37.5994),
    (name: 'Ruiri', lat: 0.1167, lng: 37.5333),
    (name: 'Kibirichia', lat: 0.0667, lng: 37.4167),
    (name: 'Timau', lat: 0.0772, lng: 37.2419),
    (name: 'Buuri', lat: 0.0500, lng: 37.4500),
    (name: 'Kiirua', lat: 0.0167, lng: 37.5333),
    (name: 'Naari', lat: 0.0833, lng: 37.5167),
    (name: 'Katheri', lat: 0.0400, lng: 37.6200),
    (name: 'Githongo', lat: 0.0331, lng: 37.6997),
    (name: 'Nkubu', lat: -0.0606, lng: 37.6603),
    (name: 'Kanyakine', lat: -0.1000, lng: 37.6486),
    (name: 'Nkuene', lat: -0.1180, lng: 37.6450),
    (name: 'Kionyo', lat: -0.0950, lng: 37.6050),
    (name: 'Kithirune', lat: -0.0300, lng: 37.6250),
    (name: 'Abogeta', lat: -0.0900, lng: 37.6333),
    (name: 'Igoji', lat: -0.1500, lng: 37.6333),
    (name: 'Mitunguu', lat: -0.1500, lng: 37.7167),
    (name: 'Kawiru', lat: 0.0900, lng: 37.7200),
    (name: 'Ntakira', lat: 0.1300, lng: 37.7000),
    (name: 'Tigania', lat: 0.1500, lng: 37.7600),
    (name: 'Miathene', lat: 0.1750, lng: 37.7400),
    (name: 'Athwana', lat: 0.1600, lng: 37.7150),
    (name: 'Kianjai', lat: 0.1808, lng: 37.7350),
    (name: 'Mikinduri', lat: 0.1186, lng: 37.8497),
    (name: 'Muthara', lat: 0.1564, lng: 37.9019),
    (name: 'Maua', lat: 0.2333, lng: 37.9386),
    (name: 'Kangeta', lat: 0.2050, lng: 37.9100),
    (name: 'Antuambui', lat: 0.2500, lng: 37.9000),
    (name: 'Antubetwe Kiongo', lat: 0.2700, lng: 37.9200),
    (name: 'Laare', lat: 0.2667, lng: 37.9667),
    (name: 'Kiengu', lat: 0.2833, lng: 37.8500),
    (name: 'Mutuati', lat: 0.3167, lng: 37.8833),
    (name: "Akirang'ondu", lat: 0.2900, lng: 37.9500),
  ];

  List<Place> _meruMatches(String q) {
    final lower = q.toLowerCase();
    return _meru
        .where((p) => p.name.toLowerCase().contains(lower))
        .map((p) => Place(name: '${p.name}, Meru, Kenya', shortName: p.name, lat: p.lat, lng: p.lng))
        .toList();
  }

  Future<List<Place>> search(String query, {double? nearLat, double? nearLng}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // 1) Local Meru County matches first (guaranteed coverage for tiny towns).
    final local = _meruMatches(q);

    // 2) Remote search — Google first (most accurate, incl. small towns), then
    //    Mapbox as a free fallback.
    List<Place> remote = await _googleSearch(q, nearLat, nearLng);
    if (remote.isEmpty) remote = await _mapboxSearch(q, nearLat, nearLng);

    // Merge: local first, then remote, de-duplicated by short name.
    final seen = <String>{for (final p in local) p.shortName.toLowerCase()};
    final merged = [...local];
    for (final p in remote) {
      if (seen.add(p.shortName.toLowerCase())) merged.add(p);
    }
    return merged.take(8).toList();
  }

  /// Google Places Autocomplete + per-prediction geocoding, Kenya-restricted and
  /// biased to the user's location. Returns [] if the Places/Geocoding APIs aren't
  /// enabled on the key (so the caller falls back to Mapbox).
  Future<List<Place>> _googleSearch(String q, double? nearLat, double? nearLng) async {
    if (_googleKey.isEmpty) return [];
    final lat = nearLat ?? meruLat, lng = nearLng ?? meruLng;
    final auto = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(q)}&key=$_googleKey&components=country:ke'
      '&location=$lat,$lng&radius=120000&language=en',
    );
    try {
      final res = await _http.get(auto);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return [];
      final preds = ((data['predictions'] as List<dynamic>?) ?? []).take(6).toList();
      // Resolve coordinates for each prediction (Place Details).
      final places = await Future.wait(preds.map((p) => _googleDetails(p as Map<String, dynamic>)));
      return places.whereType<Place>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<Place?> _googleDetails(Map<String, dynamic> pred) async {
    final placeId = pred['place_id'] as String?;
    if (placeId == null) return null;
    final sf = pred['structured_formatting'] as Map<String, dynamic>?;
    final main = sf?['main_text'] as String? ?? (pred['description'] as String? ?? '');
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId&key=$_googleKey&fields=geometry,name,formatted_address',
    );
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final loc = (((data['result'] as Map<String, dynamic>?)?['geometry'] as Map<String, dynamic>?)?['location']) as Map<String, dynamic>?;
      if (loc == null) return null;
      return Place(
        name: pred['description'] as String? ?? main,
        shortName: main,
        lat: (loc['lat'] as num).toDouble(),
        lng: (loc['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Place>> _mapboxSearch(String q, double? nearLat, double? nearLng) async {
    if (_token.isEmpty) return [];
    final prox = '${nearLng ?? meruLng},${nearLat ?? meruLat}';
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json'
      '?access_token=$_token&country=ke&proximity=$prox&autocomplete=true&limit=8&language=en'
      '&types=place,locality,neighborhood,address,poi,district',
    );
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ((data['features'] as List<dynamic>?) ?? []).map(_toPlace).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> reverse(double lat, double lng) async {
    // Google reverse-geocode first, then Mapbox.
    if (_googleKey.isNotEmpty) {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleKey&language=en',
      );
      try {
        final res = await _http.get(uri);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final results = (data['results'] as List<dynamic>?) ?? [];
          if (data['status'] == 'OK' && results.isNotEmpty) {
            return (results.first as Map<String, dynamic>)['formatted_address'] as String?;
          }
        }
      } catch (_) {}
    }
    if (_token.isEmpty) return null;
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
