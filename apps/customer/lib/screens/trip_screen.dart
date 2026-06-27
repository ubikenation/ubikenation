import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_map.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'paystack_webview.dart';

/// Drives the whole Uber/Bolt-style trip:
///   finding a rider (just a loading state — the customer never sees the rider
///   accept/quote happening) → pay 50% once the price is set → live two-way map
///   tracking with the rider's profile + car + plate, chat & call → arrived →
///   in progress → pay the balance on arrival → rate.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.trip});
  final Trip trip;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late Trip _trip;
  Timer? _poll;
  Timer? _locPush;
  int _rating = 5;
  bool _busy = false;
  final TextEditingController _ratingNote = TextEditingController();
  Map<String, dynamic>? _riderLoc;

  static const _trackStatuses = {'rider_assigned', 'arrived', 'in_progress'};
  // Statuses where a rider is assigned and we can show who's coming (incl. before payment).
  static const _riderKnownStatuses = {'awaiting_payment', 'rider_assigned', 'arrived', 'in_progress', 'awaiting_balance'};

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    // Share our live location so the rider can trace us to the pickup.
    _locPush = Timer.periodic(const Duration(seconds: 8), (_) => _pushMyLocation());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _locPush?.cancel();
    _ratingNote.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = context.read<TripRepository>();
    try {
      final t = await repo.getTrip(_trip.id);
      if (mounted) setState(() => _trip = t);
      if (_riderKnownStatuses.contains(t.status)) {
        final loc = await repo.riderLocation(_trip.id);
        if (mounted) setState(() => _riderLoc = loc);
      }
      if (t.status == 'completed' || t.status == 'cancelled') _poll?.cancel();
    } catch (_) {
      // transient; keep polling
    }
  }

  Future<void> _pushMyLocation() async {
    if (!_trackStatuses.contains(_trip.status)) return;
    final repo = context.read<TripRepository>();
    try {
      final pos = await Geolocator.getCurrentPosition();
      await repo.pushLocation(_trip.id, pos.latitude, pos.longitude);
    } catch (_) {/* ignore */}
  }

  // ---- payments ----
  Future<void> _payUpfront() async => _pay(isBalance: false);
  Future<void> _payBalance() async => _pay(isBalance: true);

  Future<void> _pay({required bool isBalance}) async {
    setState(() => _busy = true);
    final repo = context.read<TripRepository>();
    try {
      final amount = isBalance ? _trip.balance : _trip.upfront;
      final checkout = isBalance ? await repo.initiateBalance(_trip.id, amount) : await repo.initiateUpfront(_trip.id, amount);
      if (!mounted) return;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PaystackWebView(url: checkout.url, callbackUrl: TripRepository.paystackCallbackUrl),
      ));
      if (paid == true) {
        await repo.verifyPayment(checkout.reference);
      }
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- rider / cancellation ----
  Future<void> _findAnotherRider() async {
    final repo = context.read<TripRepository>();
    setState(() => _busy = true);
    try {
      await repo.requery(_trip.id);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _cancelReasons = [
    'Rider isn\'t moving',
    'Waiting too long',
    'Wrong pickup location',
    'Booked by mistake',
    'Found another way',
    'Rider asked to cancel',
    'Other',
  ];

  Future<void> _cancelFlow() async {
    final repo = context.read<TripRepository>();
    final reason = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Why are you cancelling?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            ..._cancelReasons.map((r) => ListTile(
                  title: Text(r),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
                  onTap: () => Navigator.pop(ctx, r),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await repo.cancelTrip(_trip.id, reason: reason);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _problemReasons = [
    'Rider behaved badly',
    'Took the wrong route',
    'Charged incorrectly',
    'Safety concern',
    'Item damaged / wrong (errand)',
    'Other',
  ];

  /// Opens a dispute on an active/finished trip — admin reviews and can refund.
  Future<void> _reportProblem() async {
    final repo = context.read<TripRepository>();
    final reason = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('Report a problem', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ),
            ..._problemReasons.map((r) => ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r))),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await repo.dispute(_trip.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks — our team will review this and get back to you.')),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not report: $e')));
    }
  }

  Future<void> _submitRating() async {
    final nav = Navigator.of(context);
    final note = _ratingNote.text.trim();
    // The rating is non-critical: never trap the user on this screen. We try to
    // save it, but we always finish (return home) afterwards, success or not.
    try {
      await context.read<TripRepository>().rate(_trip.id, _rating, comment: note.isEmpty ? null : note);
    } catch (_) {
      // ignore — the trip is already complete; a rating hiccup shouldn't block exit.
    }
    if (!mounted) return;
    // popUntil(isFirst) is safe even when already at the root route (it pops nothing).
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _trackStatuses.contains(_trip.status) && _riderLoc != null;
    // You can't just back out of a live trip — the only way out is Cancel (so a request
    // isn't silently abandoned). Once it's completed/cancelled, leaving is allowed.
    final canLeave = _trip.status == 'completed' || _trip.status == 'cancelled';
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tap “Cancel” to leave this trip.'), duration: Duration(seconds: 2)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Your Trip'), automaticallyImplyLeading: canLeave),
        body: SafeArea(
          child: tracking ? _trackingView() : Padding(padding: const EdgeInsets.all(20), child: _body()),
        ),
      ),
    );
  }

  // -------- Live tracking (rider en route / arrived / in progress) --------
  Widget _trackingView() {
    final loc = _riderLoc!;
    final riderLat = (loc['riderLat'] as num?)?.toDouble();
    final riderLng = (loc['riderLng'] as num?)?.toDouble();
    final pickupLat = (loc['pickupLat'] as num?)?.toDouble() ?? -0.0463;
    final pickupLng = (loc['pickupLng'] as num?)?.toDouble() ?? 37.6559;
    final dropLat = (loc['dropoffLat'] as num?)?.toDouble();
    final dropLng = (loc['dropoffLng'] as num?)?.toDouble();
    final inProgress = _trip.status == 'in_progress';

    final targetLat = inProgress ? (dropLat ?? pickupLat) : pickupLat;
    final targetLng = inProgress ? (dropLng ?? pickupLng) : pickupLng;

    double? km;
    if (riderLat != null && riderLng != null) {
      km = _haversine(riderLat, riderLng, targetLat, targetLng);
    }
    final etaMin = km != null ? math.max(1, (km / 22 * 60).round()) : null;

    final markers = <MapMarker>[
      if (dropLat != null && dropLng != null) MapMarker(LatLng(dropLat, dropLng), color: AppTheme.accent, icon: Icons.location_pin),
      if (riderLat != null && riderLng != null) MapMarker(LatLng(riderLat, riderLng), color: AppTheme.accent, icon: Icons.navigation),
    ];
    final center = (riderLat != null && riderLng != null)
        ? LatLng((riderLat + targetLat) / 2, (riderLng + targetLng) / 2)
        : LatLng(pickupLat, pickupLng);

    return Column(
      children: [
        Expanded(
          child: AppMap(
            center: center,
            zoom: 13.5,
            follow: true,
            myLocation: inProgress ? null : LatLng(pickupLat, pickupLng),
            markers: markers,
          ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, -4))],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _trip.status == 'arrived'
                    ? 'Your rider has arrived'
                    : inProgress
                        ? 'On the way to your destination'
                        : 'Your rider is on the way',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.ink),
              ),
              const SizedBox(height: 4),
              if (km != null)
                Text('${km.toStringAsFixed(1)} km away  ·  ~$etaMin min', style: const TextStyle(color: AppTheme.muted))
              else
                const Text('Locating your rider…', style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 14),
              _riderCard(loc),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _placeCall(loc['riderName'] as String? ?? 'your rider'),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                    ),
                  ),
                ],
              ),
              // You can cancel only while the rider is still on the way. Once they've
              // arrived or the ride has started, it's "Report a problem" instead.
              if (_trip.status == 'rider_assigned') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy ? null : _cancelFlow,
                    child: const Text('Cancel ride'),
                  ),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _reportProblem,
                    child: const Text('Report a problem'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Rider identity card: photo, name, rating, and the car make/model/colour +
  /// plate so the customer recognises who's coming (Bolt-style).
  Widget _riderCard(Map<String, dynamic> loc) {
    final name = loc['riderName'] as String? ?? 'Your rider';
    final rating = (loc['rating'] as num?)?.toDouble() ?? 5.0;
    final photo = loc['riderPhoto'] as String?;
    final make = loc['vehicleMake'] as String?;
    final model = loc['vehicleModel'] as String?;
    final color = loc['vehicleColor'] as String?;
    final plate = loc['plateNumber'] as String?;
    final carParts = [color, make, model].where((s) => s != null && s.isNotEmpty).join(' ');

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.surface,
          backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
          child: (photo == null || photo.isEmpty) ? const Icon(Icons.person, color: AppTheme.primary) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
              Row(children: [
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 3),
                Text(rating.toStringAsFixed(1), style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ]),
              if (carParts.isNotEmpty)
                Text(carParts, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (plate != null && plate.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(plate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            const SizedBox(height: 4),
            Text('KES ${_trip.fare}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
          ],
        ),
      ],
    );
  }

  void _openChat() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(tripId: _trip.id)));
  }

  void _placeCall(String name) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(tripId: _trip.id, peerName: name)));
  }

  // -------- Non-tracking states --------
  Widget _body() {
    switch (_trip.status) {
      case 'scheduled':
        return _statusBlock(Icons.schedule, 'Ride scheduled. We\'ll match you a rider at the set time.');
      case 'searching':
      case 'quote_pending':
        return _findingBlock();
      case 'awaiting_payment':
        return _riderFoundBlock();
      case 'rider_assigned':
      case 'arrived':
        return _statusBlock(Icons.directions_bike, 'Rider assigned — loading live map…');
      case 'in_progress':
        return _statusBlock(Icons.navigation, 'Trip in progress — enjoy the ride');
      case 'awaiting_balance':
        return _payBlock(
          title: 'You\'ve arrived',
          subtitle: 'Pay the remaining balance to finish your trip.',
          amount: _trip.balance,
          onPay: _payBalance,
        );
      case 'completed':
        return _ratingBlock();
      case 'cancelled':
        return _statusBlock(Icons.cancel, 'Trip cancelled. Any payment is refunded to your wallet.');
      default:
        return _statusBlock(Icons.info, 'Status: ${_trip.status}');
    }
  }

  /// Fancy "finding a rider" loading — an animated radar pulse so the wait feels
  /// alive. The customer never sees the rider accept/quote; it just feels like search.
  Widget _findingBlock() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        const _SearchingRadar(),
        const SizedBox(height: 28),
        const Text('Finding you the closest rider…',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        const SizedBox(height: 8),
        const Text('Matching you with a nearby rider. Hang tight…',
            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
        const Spacer(),
        TextButton(
          onPressed: _busy ? null : _findAnotherRider,
          child: const Text('Taking too long? Find another rider'),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: _busy ? null : _cancelFlow, child: const Text('Cancel')),
        ),
      ],
    );
  }

  /// Prominent, professional "Rider found" card (Bolt/Uber style) — the rider is
  /// what matters most here, so it takes centre stage, with price + pay + cancel.
  Widget _riderFoundBlock() {
    final loc = _riderLoc;
    final name = loc?['riderName'] as String? ?? 'Your rider';
    final rating = (loc?['rating'] as num?)?.toDouble() ?? 5.0;
    final ratingCount = (loc?['ratingCount'] as num?)?.toInt() ?? 0;
    final photo = loc?['riderPhoto'] as String?;
    final make = loc?['vehicleMake'] as String?;
    final model = loc?['vehicleModel'] as String?;
    final color = loc?['vehicleColor'] as String?;
    final plate = loc?['plateNumber'] as String?;
    final carParts = [color, make, model].where((s) => s != null && s.isNotEmpty).join(' ');

    return Column(
      children: [
        const SizedBox(height: 6),
        const Text('Rider found!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.ink)),
        const SizedBox(height: 16),
        // Big rider card.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black12),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: AppTheme.surface,
                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo == null || photo.isEmpty) ? const Icon(Icons.person, color: AppTheme.primary, size: 48) : null,
              ),
              const SizedBox(height: 12),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.ink)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 18, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  Text(ratingCount > 0 ? '  ·  $ratingCount trips' : '  ·  New rider', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ),
              if (carParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.two_wheeler, size: 18, color: AppTheme.muted),
                    const SizedBox(width: 6),
                    Text(carParts, style: const TextStyle(color: AppTheme.ink, fontSize: 14)),
                  ],
                ),
              ],
              if (plate != null && plate.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.ink, borderRadius: BorderRadius.circular(8)),
                  child: Text(plate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Pay 50% now to confirm. The other half is paid when you reach your destination.',
            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 14),
        Text('KES ${_trip.upfront}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.ink)),
        Text('Total fare: KES ${_trip.fare}', style: const TextStyle(color: AppTheme.muted)),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _payUpfront,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Pay KES ${_trip.upfront}'),
          ),
        ),
        TextButton(onPressed: _busy ? null : _cancelFlow, child: const Text('Cancel')),
      ],
    );
  }

  Widget _payBlock({required String title, required String subtitle, required int amount, required VoidCallback onPay}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.account_balance_wallet, size: 60, color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 18),
        Text('KES $amount', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.ink)),
        Text('Total fare: KES ${_trip.fare}', style: const TextStyle(color: AppTheme.muted)),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : onPay,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Pay KES $amount'),
          ),
        ),
      ],
    );
  }

  Widget _statusBlock(IconData icon, String text) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppTheme.ink)),
        const SizedBox(height: 8),
        Text('Fare: KES ${_trip.fare}', style: const TextStyle(color: AppTheme.muted)),
      ],
    );
  }

  Widget _ratingBlock() {
    // Scroll-safe so the optional note's keyboard never overflows the column.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _ratingColumn()),
        ),
      ),
    );
  }

  Widget _ratingColumn() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.check_circle, size: 64, color: AppTheme.accent),
        const SizedBox(height: 12),
        const Text('Trip completed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Paid in full: KES ${_trip.fare}', style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 20),
        const Text('Rate your rider'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            return IconButton(
              icon: Icon(i < _rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36),
              onPressed: () => setState(() => _rating = i + 1),
            );
          }),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _ratingNote,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Add a note (optional) — how was your trip?',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _submitRating, child: const Text('Submit & Finish')),
          ),
        ),
        TextButton(onPressed: _reportProblem, child: const Text('Report a problem')),
      ],
    );
  }

  static double _haversine(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLng = (bLng - aLng) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(aLat * math.pi / 180) * math.cos(bLat * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}

/// Animated radar: concentric expanding/fading rings around a bike icon — a lively
/// "searching for a rider" indicator while the customer waits.
class _SearchingRadar extends StatefulWidget {
  const _SearchingRadar();
  @override
  State<_SearchingRadar> createState() => _SearchingRadarState();
}

class _SearchingRadarState extends State<_SearchingRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // three staggered expanding rings
              for (var i = 0; i < 3; i++) _ring((t + i / 3) % 1.0),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary,
                  boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 16)],
                ),
                child: const Icon(Icons.two_wheeler, color: Colors.white, size: 38),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double p) {
    final size = 72 + p * 108;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primary.withValues(alpha: (1 - p) * 0.5), width: 2),
      ),
    );
  }
}
