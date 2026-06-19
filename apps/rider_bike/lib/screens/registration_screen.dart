import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rider_repository.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Detailed, validated rider registration:
/// Personal Info → Documents (incl. profile photo) → Vehicle Info →
/// Registration Fee (free KES 0 or Paystack) → Submit & Review.
/// Each step validates before you can continue; nothing can be left blank.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  String get _kind => RiderRepository.kind;

  int _step = 0;
  bool _busy = false;
  bool _feePaid = false;
  String? _uploading;
  String? _error;
  FeeQuote? _fee;

  final _personalForm = GlobalKey<FormState>();
  final _vehicleForm = GlobalKey<FormState>();
  final _storage = StorageService();

  // Personal
  final _fullName = TextEditingController();
  final _idNumber = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _town = TextEditingController(text: 'Meru');
  final _county = TextEditingController(text: 'Meru');
  final _kinName = TextEditingController();
  final _kinPhone = TextEditingController();
  DateTime? _dob;
  String _gender = 'Male';

  // Vehicle
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _insuranceCo = TextEditingController();
  late String _vehicleType = _vehicleTypes.first.value;

  late final Map<String, String?> _docs = {for (final k in _docKeys) k: null};

  @override
  void initState() {
    super.initState();
    _claimSlot();
  }

  @override
  void dispose() {
    for (final c in [_fullName, _idNumber, _phone, _address, _town, _county, _kinName, _kinPhone, _make, _model, _year, _plate, _color, _insuranceCo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _claimSlot() async {
    setState(() => _busy = true);
    try {
      final fee = await context.read<RiderRepository>().register();
      if (mounted) setState(() => _fee = fee);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- per-kind config ----
  List<String> get _docKeys => switch (_kind) {
        'car' => ['profile_photo_url', 'national_id_url', 'driving_license_url', 'selfie_url', 'logbook_url', 'insurance_url', 'inspection_url', 'vehicle_photo_url'],
        // errands riders register exactly like bike riders (full docs + vehicle).
        _ => ['profile_photo_url', 'national_id_url', 'driving_license_url', 'selfie_url', 'vehicle_photo_url', 'ownership_proof_url', 'insurance_url', 'inspection_url'],
      };

  List<({String label, String value})> get _vehicleTypes => switch (_kind) {
        'car' => const [(label: 'Economy', value: 'economy'), (label: 'Comfort', value: 'comfort'), (label: 'SUV', value: 'suv')],
        _ => const [(label: 'Standard Bike', value: 'standard_bike'), (label: 'Electric Bike', value: 'electric_bike')],
      };

  bool get _hasVehicleStep => true;
  bool get _allDocsCaptured => _docs.values.every((v) => v != null);

  // ---- actions ----
  Future<void> _capture(String key) async {
    setState(() {
      _uploading = key;
      _error = null;
    });
    try {
      final path = await _storage.pickAndUploadDoc(key);
      if (path != null && mounted) setState(() => _docs[key] = path);
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18),
      helpText: 'Date of birth (must be 18+)',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Map<String, dynamic> get _details => {
        'fullName': _fullName.text.trim(),
        'idNumber': _idNumber.text.trim(),
        'phone': _phone.text.trim(),
        'mpesa': _phone.text.trim(),
        'dob': _dob?.toIso8601String(),
        'gender': _gender,
        'address': _address.text.trim(),
        'town': _town.text.trim(),
        'county': _county.text.trim(),
        'nextOfKinName': _kinName.text.trim(),
        'nextOfKinPhone': _kinPhone.text.trim(),
        if (_hasVehicleStep) ...{
          'vehicleType': _vehicleType,
          'make': _make.text.trim(),
          'model': _model.text.trim(),
          'year': _year.text.trim(),
          'plate': _plate.text.trim(),
          'color': _color.text.trim(),
          'insuranceCompany': _insuranceCo.text.trim(),
        },
      };

  Future<void> _payFee() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = context.read<RiderRepository>();
    try {
      if ((_fee?.registrationFee ?? 0) == 0) {
        await repo.confirmFreeRegistration();
        setState(() {
          _feePaid = true;
          _step += 1;
        });
      } else {
        final url = await repo.payRegistration(_fee!.registrationFee);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Pay KES ${_fee!.registrationFee}'),
            content: Text('Complete your registration payment via Paystack:\n\n$url'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
          ),
        );
        setState(() {
          _feePaid = true;
          _step += 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<RiderRepository>();
      await repo.submitDetails(
        _details,
        _hasVehicleStep
            ? {'vehicleClass': _vehicleType, 'plate': _plate.text.trim(), 'make': _make.text.trim(), 'model': _model.text.trim(), 'color': _color.text.trim()}
            : null,
      );
      await repo.submitDocuments({for (final e in _docs.entries) e.key: e.value!});
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _onContinue(int lastStep) async {
    setState(() => _error = null);
    // Step 0: personal info validation
    if (_step == 0) {
      if (!_personalForm.currentState!.validate()) return;
      if (_dob == null) {
        setState(() => _error = 'Please select your date of birth');
        return;
      }
    }
    // Documents step
    if (_step == 1 && !_allDocsCaptured) {
      setState(() => _error = 'Please upload all required documents (including your profile photo)');
      return;
    }
    // Vehicle step
    if (_step == 2 && _hasVehicleStep) {
      if (!_vehicleForm.currentState!.validate()) return;
    }
    // Fee step → pay/confirm before advancing
    final feeStepIndex = _hasVehicleStep ? 3 : 2;
    if (_step == feeStepIndex && !_feePaid) {
      await _payFee();
      return;
    }
    if (_step == lastStep) {
      await _submit();
      return;
    }
    setState(() => _step += 1);
  }

  @override
  Widget build(BuildContext context) {
    final fee = _fee;
    final steps = <Step>[
      Step(title: const Text('Personal Info'), isActive: _step >= 0, content: _personalStep()),
      Step(title: const Text('Documents'), isActive: _step >= 1, content: Column(children: _docKeys.map(_docTile).toList())),
      if (_hasVehicleStep) Step(title: const Text('Vehicle Info'), isActive: _step >= 2, content: _vehicleStep()),
      Step(title: const Text('Registration Fee'), isActive: _step >= (_hasVehicleStep ? 3 : 2), content: _feeStep(fee)),
      Step(title: const Text('Submit & Review'), isActive: _step >= (_hasVehicleStep ? 4 : 3), content: _reviewStep(fee)),
    ];
    final lastStep = steps.length - 1;

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
              physics: const ClampingScrollPhysics(),
              onStepContinue: _busy ? null : () => _onContinue(lastStep),
              onStepCancel: _step == 0 ? null : () => setState(() => _step -= 1),
              onStepTapped: _busy ? null : (i) {
                // Allow going back to an earlier step by tapping it; never skip ahead.
                if (i < _step) setState(() => _step = i);
              },
              // Buttons live in the fixed bottom bar instead (always visible).
              controlsBuilder: (context, details) => const SizedBox.shrink(),
              steps: steps,
            ),
          ),
        ],
      ),
      // Persistent navigation so the Continue button is ALWAYS visible, no
      // matter how long the current step is or how far it is scrolled.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (_step > 0) ...[
                OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step -= 1),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _onContinue(lastStep),
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_step == lastStep ? 'Submit Application' : 'Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- step bodies ----
  Widget _personalStep() {
    return Form(
      key: _personalForm,
      child: Column(
        children: [
          _tf(_fullName, 'Full name (as on ID)', cap: true),
          _tf(_idNumber, 'National ID number', keyboard: TextInputType.number),
          _tf(_phone, 'Phone (M-Pesa) e.g. 07XXXXXXXX', keyboard: TextInputType.phone),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date of birth'),
              child: Text(_dob == null ? 'Select date' : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                  style: TextStyle(color: _dob == null ? AppTheme.muted : AppTheme.ink)),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _gender = v ?? 'Male'),
          ),
          _tf(_address, 'Residential address / estate'),
          _tf(_town, 'Town'),
          _tf(_county, 'County'),
          _tf(_kinName, 'Next of kin — full name', cap: true),
          _tf(_kinPhone, 'Next of kin — phone', keyboard: TextInputType.phone),
        ],
      ),
    );
  }

  Widget _vehicleStep() {
    return Form(
      key: _vehicleForm,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle / service type'),
            items: _vehicleTypes.map((t) => DropdownMenuItem(value: t.value, child: Text(t.label))).toList(),
            onChanged: (v) => setState(() => _vehicleType = v ?? _vehicleTypes.first.value),
          ),
          _tf(_make, 'Make (e.g. Toyota, Boxer)', cap: true),
          _tf(_model, 'Model (e.g. Vitz, BM150)', cap: true),
          _tf(_year, 'Year of manufacture', keyboard: TextInputType.number),
          _tf(_plate, 'Number plate', cap: true),
          _tf(_color, 'Colour', cap: true),
          _tf(_insuranceCo, 'Insurance company', cap: true),
        ],
      ),
    );
  }

  Widget _feeStep(FeeQuote? fee) {
    if (fee == null) return const Text('Calculating your registration fee…');
    if (fee.registrationFee == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.celebration, color: AppTheme.green),
              const SizedBox(width: 10),
              Expanded(child: Text('Founding Rider 🎉  Registration is FREE.\n${fee.slotsRemaining} free slots remaining.')),
            ]),
            const SizedBox(height: 8),
            const Text('Tap Continue to record your KES 0 registration via Paystack and proceed.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted)),
            if (_feePaid) const Padding(padding: EdgeInsets.only(top: 8), child: Text('✓ Registration confirmed', style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registration Fee: KES ${fee.registrationFee}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Tap Continue to pay via Paystack before submitting.', style: TextStyle(color: AppTheme.muted)),
        if (_feePaid) const Padding(padding: EdgeInsets.only(top: 8), child: Text('✓ Payment recorded', style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _reviewStep(FeeQuote? fee) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _check('Personal info complete', _fullName.text.isNotEmpty && _dob != null),
        _check('All documents + profile photo uploaded', _allDocsCaptured),
        if (_hasVehicleStep) _check('Vehicle info complete', _plate.text.isNotEmpty),
        _check('Registration fee', _feePaid),
        const SizedBox(height: 8),
        const Text('On submit, your application moves to Under Review. We will verify your documents and activate you.',
            style: TextStyle(color: AppTheme.muted)),
      ],
    );
  }

  // ---- widgets ----
  Widget _tf(TextEditingController c, String label, {TextInputType? keyboard, bool cap = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        textCapitalization: cap ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
    );
  }

  Widget _docTile(String key) {
    final captured = _docs[key] != null;
    final uploading = _uploading == key;
    final isPhoto = key == 'profile_photo_url';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        captured ? Icons.check_circle : (isPhoto ? Icons.account_circle : Icons.upload_file),
        color: captured ? AppTheme.green : AppTheme.muted,
      ),
      title: Text(_label(key)),
      subtitle: isPhoto ? const Text('Used as your profile picture', style: TextStyle(fontSize: 11)) : null,
      trailing: uploading
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(onPressed: () => _capture(key), child: Text(captured ? 'Re-upload' : 'Upload')),
    );
  }

  Widget _check(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? AppTheme.green : AppTheme.muted, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ]),
      );

  String _label(String key) => switch (key) {
        'profile_photo_url' => 'Profile Photo (your face)',
        'national_id_url' => 'National ID',
        'driving_license_url' => 'Driving License',
        'selfie_url' => 'Selfie Verification',
        'vehicle_photo_url' => 'Vehicle Photo',
        'ownership_proof_url' => 'Ownership Proof',
        'logbook_url' => 'Vehicle Logbook',
        'insurance_url' => 'Insurance Certificate',
        'inspection_url' => 'Inspection Certificate',
        _ => key,
      };
}
