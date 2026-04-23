import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/mobile_ui.dart';
import 'bale_creation_screen.dart';
import 'bale_labels_screen.dart';
import 'bale_movement_screen.dart';
import 'categories_screen.dart';
import 'products_screen.dart';

class BalesScreen extends StatelessWidget {
  final AppState appState;
  const BalesScreen({super.key, required this.appState});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final headerItems = <({
      IconData icon,
      String title,
      Color color,
      Widget screen,
    })>[
      if (appState.hasPermission('products.view'))
        (
          icon: Icons.add_box_rounded,
          title: 'Bale Creation',
          color: const Color(0xFFE31B23),
          screen: BaleCreationScreen(appState: appState),
        ),
      if (appState.hasPermission('categories.manage'))
        (
          icon: Icons.category_rounded,
          title: 'Bale Categories',
          color: const Color(0xFFB26A00),
          screen: CategoriesScreen(appState: appState),
        ),
      if (appState.hasPermission('categories.manage'))
        (
          icon: Icons.label_rounded,
          title: 'Bale Labels',
          color: const Color(0xFF00897B),
          screen: BaleLabelsScreen(appState: appState),
        ),
      if (appState.hasPermission('products.manage') || appState.hasPermission('products.view'))
        (
          icon: Icons.inventory_2_rounded,
          title: 'Bale Products',
          color: const Color(0xFF5D4037),
          screen: ProductsScreen(appState: appState),
        ),
    ];
    final movementVisible = appState.hasPermission('bale.orders.track');

    return MobilePageScaffold(
      title: 'Bales',
      subtitle: '',
      child: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Column(
              children: headerItems
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BaleHeaderAction(
                        icon: item.icon,
                        title: item.title,
                        color: item.color,
                        onTap: () => _open(context, item.screen),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (movementVisible) ...[
              const SizedBox(height: 16),
              MobileActionTile(
                icon: Icons.route_rounded,
                title: 'Bale Movement',
                subtitle: '',
                accentColor: const Color(0xFF6D4C41),
                onTap: () => _open(
                  context,
                  BaleMovementScreen(appState: appState),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BaleHeaderAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _BaleHeaderAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withOpacity(0.14),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
