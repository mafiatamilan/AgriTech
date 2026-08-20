import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../providers/providers.dart';

const _vendorTypes = [
  ('ENAM_TRADER', 'e-NAM Trader Registration'),
  ('APMC_LICENSE', 'APMC Trader / Commission Agent Licence'),
  ('FPO_FPC', 'FPO / FPC registration'),
  ('GSTIN', 'GSTIN registered business'),
  ('OTHER_AGRI_TRADER', 'Other agricultural-trader credential'),
];

class IdentityOnboardingScreen extends ConsumerStatefulWidget {
  const IdentityOnboardingScreen({super.key});

  @override
  ConsumerState<IdentityOnboardingScreen> createState() =>
      _IdentityOnboardingScreenState();
}

class _IdentityOnboardingScreenState
    extends ConsumerState<IdentityOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();
  final _farmerId = TextEditingController();
  final _businessName = TextEditingController();
  final _contactPerson = TextEditingController();
  final _registration = TextEditingController();
  final _gstin = TextEditingController();
  final _aadhaar = TextEditingController();
  final _aadhaarOtp = TextEditingController();
  String _vendorType = _vendorTypes.first.$1;
  bool _busy = false;
  bool _identityOtpSent = false;
  bool _aadhaarOtpSent = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _otp.dispose();
    _farmerId.dispose();
    _businessName.dispose();
    _contactPerson.dispose();
    _registration.dispose();
    _gstin.dispose();
    _aadhaar.dispose();
    _aadhaarOtp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await call();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(authProvider).profile;
    final backend = ref.read(backendProvider);
    if (profile == null) return;
    await _run(() async {
      if (profile.role == 'VENDOR') {
        final started = await backend.startVendorVerification(
          businessName: _businessName.text.trim(),
          contactPerson: _contactPerson.text.trim(),
          mobileNumber: profile.phone ?? '',
          state: profile.state ?? '',
          district: profile.district ?? '',
          verificationType: _vendorType,
          registrationNumber: _registration.text.trim(),
          gstin: _gstin.text.trim(),
          consent: true,
        );
        if (started.status == 'IDENTITY_FAILED') {
          throw ApiException(400, started.message);
        }
        final sent = await backend.sendVendorOtp(
          verificationType: _vendorType,
          registrationNumber: _registration.text.trim(),
          mobileNumber: profile.phone ?? '',
        );
        setState(() {
          _identityOtpSent = true;
          _message = sent.message;
        });
      } else {
        final started = await backend.startFarmerVerification(
          fullName: profile.name,
          mobileNumber: profile.phone ?? '',
          state: profile.state ?? '',
          district: profile.district ?? '',
          farmerId: _farmerId.text.trim(),
          consent: true,
        );
        if (started.status == 'IDENTITY_FAILED') {
          throw ApiException(400, started.message);
        }
        final sent = await backend.sendFarmerOtp(
          farmerId: _farmerId.text.trim(),
          mobileNumber: profile.phone ?? '',
        );
        setState(() {
          _identityOtpSent = true;
          _message = sent.message;
        });
      }
    });
  }

  Future<void> _verifyIdentity() async {
    final profile = ref.read(authProvider).profile;
    if (profile == null) return;
    if (_otp.text.trim().isEmpty) {
      setState(() => _error = 'Enter the OTP');
      return;
    }
    await _run(() async {
      final backend = ref.read(backendProvider);
      if (profile.role == 'VENDOR') {
        await backend.verifyVendor(
          verificationType: _vendorType,
          registrationNumber: _registration.text.trim(),
          mobileNumber: profile.phone ?? '',
          otp: _otp.text.trim(),
        );
      } else {
        await backend.verifyFarmer(
          farmerId: _farmerId.text.trim(),
          mobileNumber: profile.phone ?? '',
          otp: _otp.text.trim(),
        );
      }
      await ref.read(authProvider.notifier).refreshProfile();
    });
  }

  Future<void> _requestAadhaarOtp() async {
    if (_aadhaar.text.trim().length != 12) {
      setState(() => _error = 'Enter 12 digit Aadhaar number');
      return;
    }
    await _run(() async {
      final sent = await ref
          .read(backendProvider)
          .requestAadhaarOtp(
            aadhaarNumber: _aadhaar.text.trim(),
            consent: true,
          );
      setState(() {
        _aadhaarOtpSent = true;
        _message = sent.message;
      });
    });
  }

  Future<void> _verifyAadhaarOtp() async {
    if (_aadhaarOtp.text.trim().isEmpty) {
      setState(() => _error = 'Enter Aadhaar OTP');
      return;
    }
    await _run(() async {
      await ref
          .read(backendProvider)
          .verifyAadhaarOtp(
            aadhaarNumber: _aadhaar.text.trim(),
            otp: _aadhaarOtp.text.trim(),
          );
      setState(() => _message = 'Optional Aadhaar KYC verified');
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile;
    final isVendor = profile?.role == 'VENDOR';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity verification'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(authProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile?.demoVerificationMode ?? true) const _DemoBanner(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isVendor ? 'Verify Vendor / Buyer' : 'Verify Farmer',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isVendor
                        ? 'Only verified agricultural buyers can post purchase requirements and complete marketplace matches.'
                        : 'Only verified farmers can publish produce for commercial matching.',
                  ),
                  const SizedBox(height: 12),
                  _Badge(status: profile?.verificationStatus ?? 'UNVERIFIED'),
                ],
              ),
            ),
          ),
          Form(
            key: _formKey,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (isVendor) ..._vendorFields() else ..._farmerFields(),
                    const SizedBox(height: 12),
                    if (!_identityOtpSent)
                      FilledButton.icon(
                        onPressed: _busy ? null : _startIdentity,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text('Start verification'),
                      )
                    else ...[
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Verification OTP',
                          prefixIcon: Icon(Icons.password),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _verifyIdentity,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          isVendor ? 'Verify vendor' : 'Verify farmer',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _AadhaarCard(
            aadhaar: _aadhaar,
            aadhaarOtp: _aadhaarOtp,
            otpSent: _aadhaarOtpSent,
            busy: _busy,
            onRequestOtp: _requestAadhaarOtp,
            onVerifyOtp: _verifyAadhaarOtp,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                style: TextStyle(color: Colors.green.shade800),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _farmerFields() => [
    TextFormField(
      controller: _farmerId,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Farmer ID',
        prefixIcon: Icon(Icons.badge_outlined),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Enter Farmer ID' : null,
    ),
    const SizedBox(height: 8),
    const CheckboxListTile(
      value: true,
      onChanged: null,
      title: Text('I consent to Farmer Registry identity verification.'),
      contentPadding: EdgeInsets.zero,
    ),
  ];

  List<Widget> _vendorFields() => [
    TextFormField(
      controller: _businessName,
      decoration: const InputDecoration(
        labelText: 'Business / vendor name',
        prefixIcon: Icon(Icons.storefront_outlined),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Enter business name' : null,
    ),
    const SizedBox(height: 8),
    TextFormField(
      controller: _contactPerson,
      decoration: const InputDecoration(
        labelText: 'Contact person',
        prefixIcon: Icon(Icons.person_outline),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Enter contact person' : null,
    ),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      initialValue: _vendorType,
      decoration: const InputDecoration(labelText: 'Verification type'),
      items: [
        for (final type in _vendorTypes)
          DropdownMenuItem(value: type.$1, child: Text(type.$2)),
      ],
      onChanged: (v) => setState(() => _vendorType = v ?? _vendorType),
    ),
    const SizedBox(height: 8),
    TextFormField(
      controller: _registration,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Registration / licence number',
        prefixIcon: Icon(Icons.assignment_outlined),
      ),
      validator: (v) => v == null || v.trim().isEmpty
          ? 'Enter registration or licence number'
          : null,
    ),
    const SizedBox(height: 8),
    TextFormField(
      controller: _gstin,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'GSTIN (optional)',
        prefixIcon: Icon(Icons.receipt_long_outlined),
      ),
    ),
    const SizedBox(height: 8),
    const CheckboxListTile(
      value: true,
      onChanged: null,
      title: Text('I consent to agricultural-trader credential verification.'),
      contentPadding: EdgeInsets.zero,
    ),
  ];
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.14),
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'DEMO / MOCK VERIFICATION MODE\nFarmer: FARMER-DEMO-001, 9999999999, OTP 123456\nVendor: VENDOR-DEMO-001, 8888888888, OTP 123456',
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final verified = status == 'IDENTITY_VERIFIED';
    return Chip(
      avatar: Icon(
        verified ? Icons.verified : Icons.pending_outlined,
        size: 18,
      ),
      label: Text(verified ? 'Verified' : status.replaceAll('_', ' ')),
    );
  }
}

class _AadhaarCard extends StatelessWidget {
  const _AadhaarCard({
    required this.aadhaar,
    required this.aadhaarOtp,
    required this.otpSent,
    required this.busy,
    required this.onRequestOtp,
    required this.onVerifyOtp,
  });

  final TextEditingController aadhaar;
  final TextEditingController aadhaarOtp;
  final bool otpSent;
  final bool busy;
  final VoidCallback onRequestOtp;
  final VoidCallback onVerifyOtp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional Aadhaar KYC',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'I consent to Aadhaar-based authentication solely for identity verification.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: aadhaar,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: const InputDecoration(
                labelText: 'Aadhaar number',
                helperText: 'Stored as XXXX XXXX 1234 after verification',
                prefixIcon: Icon(Icons.fingerprint),
              ),
            ),
            const SizedBox(height: 12),
            if (!otpSent)
              OutlinedButton.icon(
                onPressed: busy ? null : onRequestOtp,
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Request Aadhaar OTP'),
              )
            else ...[
              TextFormField(
                controller: aadhaarOtp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Aadhaar OTP'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : onVerifyOtp,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Verify Aadhaar KYC'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
