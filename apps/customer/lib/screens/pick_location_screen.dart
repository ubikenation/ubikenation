import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';

/// Bolt-style location picker: drag the map under a fixed centre pin to set the
/// exact point, or search for a place. Returns the chosen [Place] via Navigator.pop.
class PickLocationScreen extends StatefulWidget {
  const PickLocationScreen({super.key, required this.initial, this.title = 'Set pickup'});
  final Place initial;
  final String title;

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  final _geo = GeocodingService();
  final _map = MapController();
  final _searchCtrl = TextEditingController();

  late LatLng _center = LatLng(widget.initial.lat, widget.initial.lng);
  Timer? _debounce;
  List<Place> _suggestions = [];
  bool _searching = false;
  bool _confirming = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _geo.search(value, nearLat: _center.latitude, nearLng: _center.longitude);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  void _pickSuggestion(Place p) {
    FocusScope.of(context).unfocus();
    _searchCtrl.clear();
    setState(() {
      _suggestions = [];
      _center = LatLng(p.lat, p.lng);
    });
    _map.move(_center, 16);
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    final name = await _geo.reverse(_center.latitude, _center.longitude);
    if (!mounted) return;
    final label = name ?? 'Pinned location';
    Navigator.of(context).pop(Place(
      name: label,
      shortName: label.split(',').first.trim(),
      lat: _center.latitude,
      lng: _center.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          AppMap(
            center: LatLng(widget.initial.lat, widget.initial.lng),
            zoom: 16,
            controller: _map,
            onCenterChanged: (c) => _center = c,
          ),

          // Fixed centre pin (stays put while the map moves underneath).
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40), // tip points at the centre
                child: Icon(Icons.location_pin, size: 48, color: AppTheme.accent),
              ),
            ),
          ),

          // Search bar + suggestions.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search a place, or drag the map…',
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      ),
                    ),
                  ),
                  if (_searching) const LinearProgressIndicator(),
                  if (_suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      margin: const EdgeInsets.only(top: 6),
                      child: ListView(
                        shrinkWrap: true,
                        children: _suggestions
                            .map((p) => ListTile(
                                  leading: const Icon(Icons.place_outlined, color: AppTheme.muted),
                                  title: Text(p.shortName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => _pickSuggestion(p),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Confirm button.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _confirming ? null : _confirm,
                    child: _confirming
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Confirm ${widget.title.toLowerCase()}'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
