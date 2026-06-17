import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rider_repository.dart';
import '../theme/app_theme.dart';

/// Bike rider registration, mirroring the prototype:
/// Personal Info → Documents → Vehicle Info → Pay Registration Fee → Submit & Review.
/// Founding riders (first 10) see KES 0 and skip the payment step.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  FeeQuote? _fee;

  // Personal
  final _address = TextEditingController();
  final _city = TextEditingController();
  // Vehicle
  final _plate = TextEditingController();
  final _vehicleType = ValueNotifier<String>('Economy');

  // Documents captured (placeholder storage paths; real upload via Supabase Storage).
  // Car rider required documents (matches backend REQUIRED_DOCS['car']).
  final Map<String, bool> _docs = {
    'national_id_url': false,
    'driving_license_url': false,
    'selfie_url': false,
    'logbook_url': false,
    'insurance_url': false,
    'inspection_url': false,
    'vehicle_photo_url': false,
  };

  @override
  void initState() {
    super.initState();
    _claimSlot();
  }

  @override
  void dispose() {
    _address.dispose();
    _city.dispose();
    _plate.dispose();
    _vehicleType.dispose();
    super.dispose();
  }

  Future<void> _claimSlot() async {
    setState(() => _busy = true);
    try {
      final fee = await context.read<RiderRepository>().register();
      setState(() => _fee = fee);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _allDocsCaptured => _docs.values.every((v) => v);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<RiderRepository>();
      final payload = {for (final k in _docs.keys) k: 'uploads/$k.jpg'};
      await repo.submitDocuments(payload);
      widget.onDone();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = _fee;
    final needsPayment = fee?.paymentRequired ?? false;

    final steps = <Step>[
      Step(
        title: const Text('Personal Info'),
        isActive: _step >= 0,
        content: Column(
          children: [
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 10),
            TextField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
          ],
        ),
      ),
      Step(
        title: const Text('Documents'),
        isActive: _step >= 1,
        content: Column(children: _docs.keys.map(_docTile).toList()),
      ),
      Step(
        title: const Text('Vehicle Info'),
        isActive: _step >= 2,
        content: Column(
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _vehicleType,
              builder: (_, value, _) => DropdownButtonFormField<String>(
                initialValue: value,
                decoration: const InputDecoration(labelText: 'Vehicle Type'),
                items: const [
                  DropdownMenuItem(value: 'Economy', child: Text('Economy')),
                  DropdownMenuItem(value: 'Comfort', child: Text('Comfort')),
                  DropdownMenuItem(value: 'SUV', child: Text('SUV')),
                ],
                onChanged: (v) => _vehicleType.value = v ?? 'Economy',
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Plate Number')),
          ],
        ),
      ),
      Step(
        title: const Text('Registration Fee'),
        isActive: _step >= 3,
        content: _feeContent(fee, needsPayment),
      ),
      Step(
        title: const Text('Submit & Review'),
        isActive: _step >= 4,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _check('Documents captured', _allDocsCaptured),
            _check('Registration fee', !needsPayment || (fee?.registrationFee == 0)),
            const SizedBox(height: 8),
            const Text('On submit your application moves to Under Review.',
                style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Rider Registration')),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFDECEA),
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: AppTheme.red)),
            ),
          Expanded(
            child: Stepper(
              currentStep: _step,
              type: StepperType.vertical,
              onStepContinue: _busy ? null : _onContinue,
              onStepCancel: _step == 0 ? null : () => setState(() => _step -= 1),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: details.onStepContinue,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_step == steps.length - 1 ? 'Submit' : 'Next'),
                    ),
                    if (_step > 0)
                      TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
                  ],
                ),
              ),
              steps: steps,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onContinue() async {
    if (_step == 1 && !_allDocsCaptured) {
      setState(() => _error = 'Please capture all required documents');
      return;
    }
    if (_step == 3 && (_fee?.paymentRequired ?? false) && (_fee?.registrationFee ?? 0) > 0) {
      await _payFee();
      return;
    }
    if (_step == 4) {
      await _submit();
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  Future<void> _payFee() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await context.read<RiderRepository>().payRegistration(_fee!.registrationFee);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Pay Registration Fee'),
          content: Text('Complete payment via Paystack:\n\n$url'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
      setState(() => _step += 1);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _feeContent(FeeQuote? fee, bool needsPayment) {
    if (fee == null) return const Text('Calculating your registration fee…');
    if (fee.isFounding || fee.registrationFee == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F7EE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.celebration, color: AppTheme.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Founding Rider 🎉 — Registration is FREE (KES 0).\n${fee.slotsRemaining} free slots remaining.',
                style: const TextStyle(color: AppTheme.ink),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registration Fee: KES ${fee.registrationFee}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Pay via Paystack to submit your application.', style: TextStyle(color: AppTheme.muted)),
      ],
    );
  }

  Widget _docTile(String key) {
    final captured = _docs[key]!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(captured ? Icons.check_circle : Icons.upload_file,
          color: captured ? AppTheme.green : AppTheme.muted),
      title: Text(_label(key)),
      trailing: TextButton(
        onPressed: () => setState(() => _docs[key] = true),
        child: Text(captured ? 'Re-capture' : 'Capture'),
      ),
    );
  }

  Widget _check(String label, bool ok) => Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
              color: ok ? AppTheme.green : AppTheme.muted, size: 20),
          const SizedBox(width: 8),
          Text(label),
        ],
      );

  String _label(String key) => switch (key) {
        'national_id_url' => 'National ID',
        'driving_license_url' => 'Driving License',
        'selfie_url' => 'Selfie Verification',
        'logbook_url' => 'Vehicle Logbook',
        'insurance_url' => 'Insurance',
        'inspection_url' => 'Inspection Certificate',
        'vehicle_photo_url' => 'Vehicle Photo',
        _ => key,
      };
}
