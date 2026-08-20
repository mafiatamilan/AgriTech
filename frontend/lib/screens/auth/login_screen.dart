import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _stateName = TextEditingController();
  final _district = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSignup = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _stateName.dispose();
    _district.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider.notifier);
      final accountType = ref.read(accountTypeProvider);
      await ref.read(accountTypeProvider.notifier).setType(accountType);
      if (_isSignup) {
        await auth.signupWithProfile(
          email: _email.text.trim(),
          password: _password.text,
          accountType: accountType,
          fullName: _name.text.trim(),
          phone: _phone.text.trim(),
          stateName: _stateName.text.trim(),
          district: _district.text.trim(),
        );
      } else {
        await auth.login(_email.text.trim(), _password.text);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountType = ref.watch(accountTypeProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.agriculture, size: 72, color: AppColors.green),
                const SizedBox(height: 16),
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                SegmentedButton<AccountType>(
                  segments: const [
                    ButtonSegment(
                      value: AccountType.farmer,
                      icon: Icon(Icons.agriculture_outlined),
                      label: Text('Farmer'),
                    ),
                    ButtonSegment(
                      value: AccountType.vendor,
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('Vendor'),
                    ),
                  ],
                  selected: {accountType},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) {
                          ref
                              .read(accountTypeProvider.notifier)
                              .setType(selection.first);
                          setState(() {
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 20),
                if (_isSignup) ...[
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: accountType == AccountType.vendor
                          ? 'Vendor name'
                          : 'Name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? accountType == AccountType.vendor
                              ? 'Enter vendor name'
                              : 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  textInputAction:
                      _isSignup && accountType == AccountType.vendor
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isSignup || accountType != AccountType.vendor) {
                      _submit();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) => value == null || value.length < 6
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                if (_isSignup) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter phone number'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stateName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'State'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter state'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _district,
                    textInputAction: accountType == AccountType.vendor
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'District'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter district'
                        : null,
                  ),
                ],
                if (_isSignup && accountType == AccountType.vendor) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Address'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter address'
                        : null,
                  ),
                ],
                if (_isSignup) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: true,
                    onChanged: null,
                    title: Text(
                      accountType == AccountType.vendor
                          ? 'Create a vendor account.'
                          : 'Create a farmer account.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isSignup
                                ? 'Sign up as ${accountType.name}'
                                : 'Log in as ${accountType.name}',
                          ),
                  ),
                ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                          _isSignup = !_isSignup;
                          _error = null;
                        }),
                  child: Text(
                    _isSignup
                        ? 'Already have an account? Log in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
