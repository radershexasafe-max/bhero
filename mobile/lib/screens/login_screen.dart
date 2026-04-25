import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../services/printer_service.dart';
import '../theme/brand.dart';
import '../widgets/auth_ui.dart';

class LoginScreen extends StatefulWidget {
  final AppState appState;
  const LoginScreen({super.key, required this.appState});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _kRememberMe = 'login_remember_me';
  static const _kRememberedIdentifier = 'login_remembered_identifier';

  final _identifier = TextEditingController();
  final _pass = TextEditingController();
  final _printer = PrinterService();

  bool _loading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  String? _error;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  @override
  void dispose() {
    _identifier.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadBranding() async {
    final prefs = await SharedPreferences.getInstance();
    final branding = await _printer.getReceiptBranding();
    final remembered = prefs.getBool(_kRememberMe) ?? true;
    final rememberedIdentifier = prefs.getString(_kRememberedIdentifier) ?? '';
    if (!mounted) return;
    setState(() {
      _rememberMe = remembered;
      if (rememberedIdentifier.isNotEmpty) {
        _identifier.text = rememberedIdentifier;
      }
      _logoPath = resolveBrandLogoPath(
        overrideLogoPath: branding.logoPath,
        tenantLogoPath: widget.appState.tenant?.logoPath,
      );
    });
  }

  Future<void> _persistRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMe, _rememberMe);
    if (_rememberMe && _identifier.text.trim().isNotEmpty) {
      await prefs.setString(_kRememberedIdentifier, _identifier.text.trim());
    } else {
      await prefs.remove(_kRememberedIdentifier);
    }
  }

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = widget.appState.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      await widget.appState.setBaseUrl(base);

      final res = await ApiClient.login(
        baseUrl: base,
        identifier: _identifier.text.trim(),
        password: _pass.text,
      );
      await _persistRememberMe();
      await widget.appState.saveSession(
        token: res.token,
        user: res.user,
        tenant: res.tenant,
        locations: res.locations,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.friendlyError(
          e,
          fallback: 'Could not sign in right now. Check your internet connection and tap Reload to try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showForgotPasswordInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please contact your admin to reset your password.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Welcome',
      subtitle: 'Login to continue',
      logoPath: _logoPath,
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _identifier,
            hintText: 'Email or Username',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          AuthTextField(
            controller: _pass,
            hintText: 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFF9E9E9E),
                size: 24,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BrandColors.soft,
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
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _rememberMe ? BrandColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: BrandColors.primary,
                      width: 2,
                    ),
                  ),
                  child: _rememberMe
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Remember me',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF616161),
                  ),
                ),
              ),
              TextButton(
                onPressed: _showForgotPasswordInfo,
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _doLogin,
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 10,
                shadowColor: const Color(0x33FF1018),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 19,
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
            "Don't have an account? ",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: BrandColors.muted,
            ),
          ),
          GestureDetector(
            onTap: _loading ? null : () => Navigator.of(context).pushNamed('/register'),
            child: const Text(
              'Register',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: BrandColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
