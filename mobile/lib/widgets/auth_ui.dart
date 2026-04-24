import 'dart:io';

import 'package:flutter/material.dart';

class AuthPageShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? logoPath;
  final Widget child;
  final Widget footer;
  final VoidCallback? onBack;

  const AuthPageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.logoPath,
    required this.child,
    required this.footer,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 36),
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AuthLogo(
                    logoPath: logoPath,
                    height: 150,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      height: 1.02,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF757575),
                    ),
                  ),
                  const SizedBox(height: 34),
                  child,
                  const SizedBox(height: 22),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthLogo extends StatelessWidget {
  final String? logoPath;
  final double height;

  const AuthLogo({
    super.key,
    required this.logoPath,
    this.height = 120,
  });

  bool get _hasLogo => logoPath != null && logoPath!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasLogo) {
      return Container(
        height: height,
        alignment: Alignment.center,
        child: const Text(
          'T.One Bales',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Color(0xFFE31B23),
          ),
        ),
      );
    }

    final path = logoPath!.trim();
    final image = path.startsWith('http://') || path.startsWith('https://')
        ? Image.network(
            path,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback(),
          )
        : Image.file(
            File(path),
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback(),
          );

    return Container(
      height: height,
      alignment: Alignment.center,
      child: image,
    );
  }

  Widget _fallback() {
    return const Text(
      'T.One Bales',
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        color: Color(0xFFE31B23),
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9E9E9E),
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFFE31B23),
          size: 34,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: Color(0xFFDADADA), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: Color(0xFFDADADA), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: Color(0xFFE31B23), width: 2),
        ),
      ),
    );
  }
}
