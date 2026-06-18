import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/geocoding_service.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import 'paystack_webview.dart';
import 'trip_screen.dart';

const _errandTypes = <({String value, String label, IconData icon})>[
  (value: 'grocery_shopping', label: 'Grocery Shopping', icon: Icons.local_grocery_store),
  (value: 'food_pickup', label: 'Food Pickup', icon: Icons.fastfood),
  (value: 'parcel_delivery', label: 'Parcel Delivery', icon: Icons.inventory_2),
  (value: 'document_delivery', label: 'Document Delivery', icon: Icons.description),
  (value: 'pharmacy_pickup', label: 'Pharmacy Pickup', icon: Icons.medical_services),
  (value: 'gift_delivery', label: 'Gift Delivery', icon: Icons.card_giftcard),
  (value: 'business_delivery', label: 'Business Delivery', icon: Icons.business_center),
  (value: 'office_delivery', label: 'Office Delivery', icon: Icons.work),
  (value: 'shopping_assistance', label: 'Shopping Assistance', icon: Icons.shopping_bag),
  (value: 'utility_payment', label: 'Utility Payment', icon: Icons.receipt_long),
  (value: 'personal_assistant', label: 'Personal Assistant', icon: Icons.person_pin),
  (value: 'custom', label: 'Custom Errand', icon: Icons.handyman),
];

/// Errands: pick a type, describe the task thoroughly, and the system auto-scans
/// the listed items into a KES fare estimate. The rider may then adjust ≤30%.
class ErrandsScreen extends StatefulWidget {
  const ErrandsScreen({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMin,
  });

  final Place pickup;
  final Place dropoff;
  final double distanceKm;
  final double durationMin;

  @override
  State<ErrandsScreen> createState() => _ErrandsScreenState();
}

class _ErrandsScreenState extends State<ErrandsScreen> {
  String _type = _errandTypes.first.value;
  final _desc = TextEditingController();

  int? _fare;
  int? _upfront;
  int? _itemCount;
  bool _estimating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _estimate() async {
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Please describe the errand and list what you need.');
      return;
    }
    setState(() {
      _estimating = true;
      _error = null;
    });
    try {
      final est = await context.read<TripRepository>().estimateErrand(
            errandType: _type,
            description: _desc.text.trim(),
            distanceKm: double.parse(widget.distanceKm.toStringAsFixed(2)),
            durationMin: double.parse(widget.durationMin.toStringAsFixed(1)),
          );
      if (!mounted) return;
      setState(() {
        _fare = est.fare;
        _upfront = est.upfront;
        _itemCount = est.itemCount;
        _estimating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _estimating = false;
      });
    }
  }

  Future<void> _payAndRequest() async {
    if (_fare == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<TripRepository>();
      final trip = await repo.createTrip(
        tripType: 'errands',
        vehicleClass: 'errands',
        pickupLat: widget.pickup.lat,
        pickupLng: widget.pickup.lng,
        pickupAddress: widget.pickup.name,
        dropoffLat: widget.dropoff.lat,
        dropoffLng: widget.dropoff.lng,
        dropoffAddress: widget.dropoff.name,
        distanceKm: double.parse(widget.distanceKm.toStringAsFixed(2)),
        durationMin: double.parse(widget.durationMin.toStringAsFixed(1)),
        errandType: _type,
        errandDescription: _desc.text.trim(),
      );
      final checkout = await repo.initiateUpfront(trip.id, trip.upfront);
      if (!mounted) return;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PaystackWebView(url: checkout.url, callbackUrl: TripRepository.paystackCallbackUrl),
      ));
      if (paid == true) {
        await repo.verifyPayment(checkout.reference);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TripScreen(trip: trip)));
      } else {
        setState(() {
          _error = 'Payment was not completed. You can try again.';
          _busy = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Errand details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('What do you need done?', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _errandTypes.map((e) {
              final sel = e.value == _type;
              return ChoiceChip(
                selected: sel,
                onSelected: (_) => setState(() {
                  _type = e.value;
                  _fare = null; // re-estimate after changing type
                }),
                avatar: Icon(e.icon, size: 18, color: sel ? Colors.white : AppTheme.primary),
                label: Text(e.label),
                selectedColor: AppTheme.primary,
                labelStyle: TextStyle(color: sel ? Colors.white : AppTheme.ink, fontSize: 12),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text('Describe it thoroughly', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
          const SizedBox(height: 6),
          const Text('List everything you need — one item per line. The more detail, the more accurate the fare.',
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            maxLines: 7,
            onChanged: (_) => setState(() => _fare = null),
            decoration: InputDecoration(
              hintText: 'e.g.\n2kg sugar\n1 loaf of bread\n500g rice\nPay KPLC token KES 500\nDeliver to gate B',
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Text('Route: ${widget.pickup.shortName} → ${widget.dropoff.shortName}  ·  ${widget.distanceKm.toStringAsFixed(1)} km',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 16),

          if (_fare != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Estimated fare', style: TextStyle(color: AppTheme.muted)),
                      Text('KES $_fare', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.ink)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Scanned $_itemCount item(s). Pay KES $_upfront (50%) now. A rider may adjust this by up to 30% with a valid reason.',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ),
                ],
              ),
            ),

          if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),

          const SizedBox(height: 12),
          if (_fare == null)
            FilledButton(
              onPressed: _estimating ? null : _estimate,
              child: _estimating
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Get Fare Estimate'),
            )
          else
            FilledButton(
              onPressed: _busy ? null : _payAndRequest,
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Pay KES $_upfront (50%) & Request'),
            ),
        ],
      ),
    );
  }
}
