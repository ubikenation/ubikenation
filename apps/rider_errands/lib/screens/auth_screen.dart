import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _isLogin = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('Email not confirmed')) {
      return 'Please verify your email first — check your inbox for the link.';
    }
    if (m.contains('Invalid login credentials')) return 'Wrong email or password.';
    if (m.contains('User already registered')) return 'That email already has an account. Try logging in.';
    if (m.contains('SocketException') || m.contains('Failed host lookup')) {
      return 'No internet connection. Turn on data or Wi-Fi and try again.';
    }
    return m.replaceFirst('AuthException(message: ', '').replaceAll(')', '');
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = context.read<AuthService>();
    try {
      if (_isLogin) {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      } else {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          phone: _phone.text.trim(),
        );
        if (res.session == null) {
          setState(() {
            _isLogin = true;
            _info = 'Account created! Check your email to verify, then log in.';
          });
        }
      }
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final auth = context.read<AuthService>();
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Your email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send link')),
        ],
      ),
    );
    if (send != true) return;
    try {
      await auth.resetPassword(emailCtrl.text.trim());
      if (mounted) setState(() => _info = 'Password reset link sent to your email.');
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Image.asset('assets/logo.png', height: 64, fit: BoxFit.contain),
                const SizedBox(height: 8),
                const Text('U-Bike Rider',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.ink)),
                const Text('Become a Rider', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 32),
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (M-Pesa)'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppTheme.muted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text('Forgot password?')),
                  ),
                const SizedBox(height: 8),
                if (_info != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_info!, style: const TextStyle(color: AppTheme.primary)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isLogin ? 'Log In' : 'Sign Up'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _isLogin = !_isLogin;
                            _error = null;
                            _info = null;
                          }),
                  child: Text(_isLogin ? 'New rider? Create an account' : 'Have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
