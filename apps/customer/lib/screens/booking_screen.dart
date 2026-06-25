import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/geocoding_service.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'errands_screen.dart';
import 'pick_location_screen.dart';
import 'trip_screen.dart';

/// Booking flow: confirm pickup (your current location, named) → search and pick
/// a destination → THEN choose a service (with its fare) → pay 50% → request.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _geo = GeocodingService();
  final _destCtrl = TextEditingController();

  Place? _pickup;
  Place? _dropoff;
  bool _locating = true;

  Timer? _debounce;
  List<Place> _suggestions = [];
  bool _searching = false;

  // Fares per vehicle class once a destination is set.
  Map<String, int> _fares = {};
  bool _loadingFares = false;
  String? _error;
  bool _busy = false;

  // Schedule-for-later (Uber/Bolt style).
  bool _scheduled = false;
  DateTime? _scheduleAt;

  @override
  void initState() {
    super.initState();
    _initPickup();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _initPickup() async {
    // Default to Meru town; replace with the device's real, named location.
    double lat = GeocodingService.meruLat, lng = GeocodingService.meruLng;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}
    final name = await _geo.reverse(lat, lng);
    if (!mounted) return;
    setState(() {
      _pickup = Place(name: name ?? 'Current location', shortName: name ?? 'Current location', lat: lat, lng: lng);
      _locating = false;
    });
  }

  void _onDestChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _geo.search(value, nearLat: _pickup?.lat, nearLng: _pickup?.lng);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  /// Lets the customer set their own pickup (search a place or drag the map under a
  /// pin), in addition to the auto-detected location — Bolt-style.
  Future<void> _pickPickup() async {
    final start = _pickup ??
        const Place(
          name: 'Current location',
          shortName: 'Current location',
          lat: GeocodingService.meruLat,
          lng: GeocodingService.meruLng,
        );
    final result = await Navigator.of(context).push<Place>(
      MaterialPageRoute(builder: (_) => PickLocationScreen(initial: start, title: 'Set pickup')),
    );
    if (result == null || !mounted) return;
    setState(() => _pickup = result);
    if (_dropoff != null) await _loadFares();
  }

  Future<void> _pickDestination(Place place) async {
    FocusScope.of(context).unfocus();
    _destCtrl.text = place.shortName;
    setState(() {
      _dropoff = place;
      _suggestions = [];
      _loadingFares = true;
      _fares = {};
      _error = null;
    });
    await _loadFares();
  }

  double get _distanceKm {
    if (_pickup == null || _dropoff == null) return 0;
    return _haversine(_pickup!.lat, _pickup!.lng, _dropoff!.lat, _dropoff!.lng);
  }

  double get _durationMin => _distanceKm / 22 * 60;

  Future<void> _loadFares() async {
    try {
      final repo = context.read<TripRepository>();
      final d = double.parse(_distanceKm.toStringAsFixed(2));
      final t = double.parse(_durationMin.toStringAsFixed(1));
      final entries = await Future.wait(ServiceCategory.all.map((c) async {
        final q = await repo.estimateFare(vehicleClass: c.id, distanceKm: d, durationMin: t);
        return MapEntry(c.id, q.fare);
      }));
      if (!mounted) return;
      setState(() {
        _fares = Map.fromEntries(entries);
        _loadingFares = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingFares = false;
      });
    }
  }

  void _onServiceTap(ServiceCategory category) {
    if (_pickup == null || _dropoff == null) return;
    if (category.id == 'errands') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ErrandsScreen(
          pickup: _pickup!,
          dropoff: _dropoff!,
          distanceKm: _distanceKm,
          durationMin: _durationMin,
        ),
      ));
      return;
    }
    _book(category);
  }

  /// Requests the ride (Uber/Bolt order): create the trip → it goes straight to
  /// matching a nearby rider. No payment yet — the customer pays 50% only after a
  /// rider accepts and confirms the price (handled on the trip screen).
  Future<void> _book(ServiceCategory category) async {
    if (_pickup == null || _dropoff == null) return;
    final repo = context.read<TripRepository>();
    if (_scheduled && _scheduleAt == null) {
      await _pickScheduleTime();
      if (_scheduleAt == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = double.parse(_distanceKm.toStringAsFixed(2));
      final t = double.parse(_durationMin.toStringAsFixed(1));
      final trip = _scheduled
          ? await repo.scheduleTrip(
              tripType: category.tripType,
              vehicleClass: category.id,
              pickupLat: _pickup!.lat,
              pickupLng: _pickup!.lng,
              pickupAddress: _pickup!.name,
              dropoffLat: _dropoff!.lat,
              dropoffLng: _dropoff!.lng,
              dropoffAddress: _dropoff!.name,
              distanceKm: d,
              durationMin: t,
              scheduledFor: _scheduleAt!,
            )
          : await repo.createTrip(
              tripType: category.tripType,
              vehicleClass: category.id,
              pickupLat: _pickup!.lat,
              pickupLng: _pickup!.lng,
              pickupAddress: _pickup!.name,
              dropoffLat: _dropoff!.lat,
              dropoffLng: _dropoff!.lng,
              dropoffAddress: _dropoff!.name,
              distanceKm: d,
              durationMin: t,
            );
      if (!mounted) return;
      if (_scheduled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride scheduled. We\'ll find you a rider at the set time.')),
        );
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TripScreen(trip: trip)));
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _pickScheduleTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _scheduleAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final center = _dropoff != null
        ? LatLng((_pickup!.lat + _dropoff!.lat) / 2, (_pickup!.lng + _dropoff!.lng) / 2)
        : LatLng(_pickup?.lat ?? GeocodingService.meruLat, _pickup?.lng ?? GeocodingService.meruLng);

    return Scaffold(
      appBar: AppBar(title: const Text('Where to?')),
      body: Column(
        children: [
          SizedBox(
            height: 200,
            child: AppMap(
              center: center,
              zoom: _dropoff != null ? 12 : 14,
              myLocation: _pickup != null ? LatLng(_pickup!.lat, _pickup!.lng) : null,
              markers: [
                if (_dropoff != null) MapMarker(LatLng(_dropoff!.lat, _dropoff!.lng), color: AppTheme.accent, icon: Icons.location_pin),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Pickup — auto-detected, but tap to set your own (search / drag map).
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _locating ? null : _pickPickup,
                  child: _fieldRow(
                    icon: Icons.my_location,
                    iconColor: AppTheme.primary,
                    child: Row(
                      children: [
                        Expanded(
                          child: _locating
                              ? const Text('Locating you…', style: TextStyle(color: AppTheme.muted))
                              : Text(_pickup?.name ?? 'Set pickup location',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w500)),
                        ),
                        const Icon(Icons.edit_location_alt_outlined, size: 18, color: AppTheme.muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Destination search
                _fieldRow(
                  icon: Icons.location_on,
                  iconColor: AppTheme.accent,
                  child: TextField(
                    controller: _destCtrl,
                    onChanged: _onDestChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search destination (e.g. Maua, Meru)…',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),

                if (_searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),

                // Suggestions
                ..._suggestions.map((p) => ListTile(
                      leading: const Icon(Icons.place_outlined, color: AppTheme.muted),
                      title: Text(p.shortName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _pickDestination(p),
                    )),

                if (_error != null)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),

                // Services appear only AFTER a destination is chosen
                if (_dropoff != null) ...[
                  const SizedBox(height: 8),
                  Text('Choose a service  ·  ${_distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _scheduled,
                    onChanged: (v) => setState(() {
                      _scheduled = v;
                      if (!v) _scheduleAt = null;
                    }),
                    title: const Text('Schedule for later', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _scheduled
                          ? (_scheduleAt == null
                              ? 'Pick a date & time when you choose a service'
                              : 'For ${_scheduleAt!.day}/${_scheduleAt!.month} at ${TimeOfDay.fromDateTime(_scheduleAt!).format(context)}')
                          : 'Request now',
                      style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                    secondary: const Icon(Icons.schedule, color: AppTheme.primary),
                  ),
                  if (_scheduled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _pickScheduleTime,
                        icon: const Icon(Icons.edit_calendar, size: 18),
                        label: Text(_scheduleAt == null ? 'Set date & time' : 'Change date & time'),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_loadingFares)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppTheme.primary)))
                  else
                    ...ServiceCategory.all.map(_serviceTile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow({required IconData icon, required Color iconColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [Icon(icon, color: iconColor), const SizedBox(width: 12), Expanded(child: child)]),
    );
  }

  Widget _serviceTile(ServiceCategory c) {
    final fare = _fares[c.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy || fare == null ? null : () => _onServiceTap(c),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Image.asset(c.asset, width: 40, height: 40, fit: BoxFit.contain),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 13, color: AppTheme.muted),
                        const SizedBox(width: 3),
                        Text('${_etaMin(c)} min  ·  Pay 50% once matched',
                            style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                      ],
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fare != null ? 'KES $fare' : '—',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.ink)),
                    const Text('total', style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rough per-service ETA in minutes (bikes weave through traffic faster).
  int _etaMin(ServiceCategory c) {
    const factor = {
      'standard_bike': 0.85,
      'electric_bike': 0.80,
      'economy': 1.0,
      'comfort': 1.0,
      'suv': 1.08,
      'errands': 1.10,
    };
    final m = (_durationMin * (factor[c.id] ?? 1.0)).round();
    return m < 2 ? 2 : m;
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
