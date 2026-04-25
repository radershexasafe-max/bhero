import 'package:flutter/material.dart';

class BrandAssets {
  static const String defaultLogoAsset = 'assets/branding/tone_family_logo.jpg';
}

class BrandColors {
  static const Color primary = Color(0xFFFF1018);
  static const Color primaryDark = Color(0xFF121212);
  static const Color canvas = Color(0xFFF7F4F2);
  static const Color card = Colors.white;
  static const Color soft = Color(0xFFFFECEE);
  static const Color muted = Color(0xFF6B6B6B);
  static const Color success = Color(0xFF169536);
  static const Color warning = Color(0xFFEF6C00);
  static const Color danger = Color(0xFFC62828);
}

String resolveBrandLogoPath({
  String? overrideLogoPath,
  String? tenantLogoPath,
}) {
  final override = overrideLogoPath?.trim() ?? '';
  if (override.isNotEmpty) return override;
  final tenant = tenantLogoPath?.trim() ?? '';
  if (tenant.isNotEmpty) return tenant;
  return BrandAssets.defaultLogoAsset;
}

bool isBundledBrandAsset(String? value) {
  final path = value?.trim() ?? '';
  return path.startsWith('assets/');
}
