import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../services/printer_service.dart';
import '../widgets/auth_ui.dart';

class RegisterScreen extends StatefulWidget {
  final AppState appState;
  const RegisterScreen({super.key, required this.appState});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _printer = PrinterService();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadBranding() async {
    final branding = await _printer.getReceiptBranding();
    if (!mounted) return;
    setState(() {
      _logoPath = branding.logoPath.trim().isNotEmpty
          ? branding.logoPath.trim()
          : widget.appState.tenant?.logoPath;
    });
  }

  Future<void> _submit() async {
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = widget.appState.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      await ApiClient.register(
        baseUrl: base,
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        username: _username.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration submitted for admin approval.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.friendlyError(
          e,
          fallback: 'Could not create the account right now. Check your internet connection and tap Reload to try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Create Account',
      subtitle: 'Join the T.One Family',
      logoPath: _logoPath,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _name,
            hintText: 'Full Name',
            icon: Icons.account_circle_outlined,
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _username,
            hintText: 'Username',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _email,
            hintText: 'Email',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _phone,
            hintText: 'Phone',
            icon: Icons.call_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _password,
            hintText: 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFF9E9E9E),
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _confirmPassword,
            hintText: 'Confirm Password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFF9E9E9E),
                size: 28,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB71C1C),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF120A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 10,
                shadowColor: const Color(0x33FF120A),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Register',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Already have an account? ',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF616161),
            ),
          ),
          GestureDetector(
            onTap: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text(
              'Login',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFFE31B23),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
