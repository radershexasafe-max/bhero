import 'package:flutter/material.dart';

import '../widgets/mobile_ui.dart';

class FeatureStubScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String message;

  const FeatureStubScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: title,
      subtitle: subtitle,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.info_outline_rounded,
            title: title,
            subtitle: subtitle,
            child: Text(message),
          ),
        ],
      ),
    );
  }
}
