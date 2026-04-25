import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/brand.dart';

class BrandLogoImage extends StatelessWidget {
  final String? logoPath;
  final double height;
  final double? width;
  final BoxFit fit;

  const BrandLogoImage({
    super.key,
    this.logoPath,
    this.height = 96,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolveBrandLogoPath(overrideLogoPath: logoPath);
    final image = _buildImage(resolved);
    return SizedBox(
      height: height,
      width: width,
      child: image,
    );
  }

  Widget _buildImage(String path) {
    if (isBundledBrandAsset(path)) {
      return Image.asset(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() {
    return const Center(
      child: Text(
        'T.One Bales',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: BrandColors.primary,
        ),
      ),
    );
  }
}
