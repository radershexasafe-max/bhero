import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/mobile_ui.dart';
import 'admin_control_screen.dart';
import 'bale_labels_screen.dart';
import 'bale_movement_screen.dart';
import 'categories_screen.dart';
import 'change_password_screen.dart';
import 'customers_screen.dart';
import 'expenses_screen.dart';
import 'notifications_screen.dart';
import 'ops_screens.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'refund_screen.dart';
import 'release_goods_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';
import 'stock_out_screen.dart';
import 'stocktake_screen.dart';
import 'suppliers_screen.dart';
import 'transfers_screen.dart';

class MoreScreen extends StatefulWidget {
  final AppState appState;
  const MoreScreen({super.key, required this.appState});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    await widget.appState.logout();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
    }
  }

  List<_MoreToolSection> _sections(BuildContext context) {
    final sections = <_MoreToolSection>[];
    final canCustomers = widget.appState.hasPermission('customers.view');
    final canCategories = widget.appState.hasPermission('categories.manage');
    final canProducts = widget.appState.hasPermission('products.view');
    final canSuppliers = widget.appState.hasPermission('suppliers.manage');
    final canPrepayments = widget.appState.hasPermission('prepayments.manage');
    final canTransfers = widget.appState.hasPermission('transfers.manage');
    final canMovement = widget.appState.hasPermission('bale.orders.track');
    final canStockTake = widget.appState.hasPermission('stocktake.manage');
    final canStockView = widget.appState.hasPermission('stock.view');
    final canStockOut = widget.appState.hasPermission('stock.import_export');
    final canAnnouncements = widget.appState.hasPermission('announcements.send') ||
        widget.appState.hasPermission('dashboard.view');
    final canReports = widget.appState.hasPermission('reports.view');
    final canSaleTransactions = widget.appState.hasPermission('pos.use') || canReports;
    final canBalances = widget.appState.hasPermission('customers.view');
    final canShift = widget.appState.hasPermission('day.manage');
    final canShiftCollections = widget.appState.hasRight('shift.collections') || canShift;
    final canExpenses = widget.appState.hasPermission('expenses.manage');
    final canRefunds = widget.appState.hasPermission('refunds.manage');
    final canAdmin = widget.appState.hasPermission('roles.manage');
    final canSettings = widget.appState.hasPermission('settings.manage');

    final catalogItems = <_MoreToolItem>[
      if (canCustomers)
        _MoreToolItem(
          icon: Icons.people_rounded,
          title: 'Customers',
          accentColor: const Color(0xFF1565C0),
          screenBuilder: (_) => CustomersScreen(appState: widget.appState),
        ),
      if (canCategories)
        _MoreToolItem(
          icon: Icons.category_rounded,
          title: 'Bale Categories',
          accentColor: const Color(0xFFB26A00),
          screenBuilder: (_) => CategoriesScreen(appState: widget.appState),
        ),
      if (canCategories)
        _MoreToolItem(
          icon: Icons.label_rounded,
          title: 'Bale Labels',
          accentColor: const Color(0xFF00897B),
          screenBuilder: (_) => BaleLabelsScreen(appState: widget.appState),
        ),
      if (canProducts)
        _MoreToolItem(
          icon: Icons.inventory_2_rounded,
          title: 'Bale Products',
          accentColor: const Color(0xFF6D4C41),
          screenBuilder: (_) => ProductsScreen(appState: widget.appState),
        ),
      if (canSuppliers)
        _MoreToolItem(
          icon: Icons.local_shipping_rounded,
          title: 'Suppliers',
          accentColor: const Color(0xFF455A64),
          screenBuilder: (_) => SuppliersScreen(appState: widget.appState),
        ),
    ];
    if (catalogItems.isNotEmpty) {
      sections.add(
        _MoreToolSection(
          title: 'Bale Catalog',
          icon: Icons.view_module_rounded,
          accentColor: const Color(0xFF9C3A18),
          items: catalogItems,
        ),
      );
    }

    final movementItems = <_MoreToolItem>[
      if (canStockView)
        _MoreToolItem(
          icon: Icons.inventory_rounded,
          title: 'Stock Levels',
          accentColor: const Color(0xFF00838F),
          screenBuilder: (_) => StockScreen(appState: widget.appState),
        ),
      if (canMovement)
        _MoreToolItem(
          icon: Icons.route_rounded,
          title: 'Bale Movement',
          accentColor: const Color(0xFF6D4C41),
          screenBuilder: (_) => BaleMovementScreen(appState: widget.appState),
        ),
      if (canTransfers)
        _MoreToolItem(
          icon: Icons.sync_alt_rounded,
          title: 'Transfers',
          accentColor: const Color(0xFF3949AB),
          screenBuilder: (_) => TransfersScreen(appState: widget.appState),
        ),
      if (canStockTake)
        _MoreToolItem(
          icon: Icons.fact_check_rounded,
          title: 'Stock Take',
          accentColor: const Color(0xFF00838F),
          screenBuilder: (_) => StockTakeScreen(appState: widget.appState),
        ),
      if (canStockOut)
        _MoreToolItem(
          icon: Icons.remove_shopping_cart_rounded,
          title: 'Out Stock',
          accentColor: const Color(0xFFE31B23),
          screenBuilder: (_) => StockOutScreen(appState: widget.appState),
        ),
    ];
    if (movementItems.isNotEmpty) {
      sections.add(
        _MoreToolSection(
          title: 'Movement And Stock',
          icon: Icons.swap_horiz_rounded,
          accentColor: const Color(0xFF5D4037),
          items: movementItems,
        ),
      );
    }

    if (canAnnouncements) {
      sections.add(
        _MoreToolSection(
          title: 'Communication',
          icon: Icons.campaign_rounded,
          accentColor: const Color(0xFF7B1E1E),
          items: [
            _MoreToolItem(
              icon: Icons.campaign_rounded,
              title: 'Announcements',
              accentColor: const Color(0xFF8E0000),
              screenBuilder: (_) => NotificationsScreen(appState: widget.appState),
            ),
          ],
        ),
      );
    }

    final salesItems = <_MoreToolItem>[
      if (canReports)
        _MoreToolItem(
          icon: Icons.bar_chart_rounded,
          title: 'Bale Reports',
          accentColor: const Color(0xFFE31B23),
          screenBuilder: (_) => ReportsScreen(appState: widget.appState),
        ),
      if (canSaleTransactions)
        _MoreToolItem(
          icon: Icons.attach_money_rounded,
          title: 'Sale Transactions',
          accentColor: const Color(0xFF2E7D32),
          screenBuilder: (_) => SaleTransactionsScreen(appState: widget.appState),
        ),
      if (canBalances)
        _MoreToolItem(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Customer Balances',
          accentColor: const Color(0xFF00897B),
          screenBuilder: (_) => CustomerBalancesScreen(appState: widget.appState),
        ),
      if (canShift)
        _MoreToolItem(
          icon: Icons.lock_clock_rounded,
          title: 'Close Shift',
          accentColor: const Color(0xFFEF6C00),
          screenBuilder: (_) => CloseShiftScreen(appState: widget.appState),
        ),
      if (canShiftCollections)
        _MoreToolItem(
          icon: Icons.collections_bookmark_rounded,
          title: 'Shift Collections',
          accentColor: const Color(0xFF1565C0),
          screenBuilder: (_) => ShiftCollectionsScreen(appState: widget.appState),
        ),
      if (canExpenses)
        _MoreToolItem(
          icon: Icons.payments_rounded,
          title: 'Expenses',
          accentColor: const Color(0xFFC62828),
          screenBuilder: (_) => ExpensesScreen(appState: widget.appState),
        ),
      if (canPrepayments)
        _MoreToolItem(
          icon: Icons.savings_rounded,
          title: 'Prepayments',
          accentColor: const Color(0xFF00897B),
          screenBuilder: (_) => PrepaymentsScreen(appState: widget.appState),
        ),
      if (widget.appState.hasPermission('release.goods'))
        _MoreToolItem(
          icon: Icons.inventory_rounded,
          title: 'Release Goods',
          accentColor: const Color(0xFF6D4C41),
          screenBuilder: (_) => ReleaseGoodsScreen(appState: widget.appState),
        ),
      if (canRefunds)
        _MoreToolItem(
          icon: Icons.undo_rounded,
          title: 'Refunds',
          accentColor: const Color(0xFF6D4C41),
          screenBuilder: (_) => RefundScreen(appState: widget.appState),
        ),
    ];
    if (salesItems.isNotEmpty) {
      sections.add(
        _MoreToolSection(
          title: 'Sales And Shifts',
          icon: Icons.point_of_sale_rounded,
          accentColor: const Color(0xFFAD1457),
          items: salesItems,
        ),
      );
    }

    final adminItems = <_MoreToolItem>[
      if (canAdmin)
        _MoreToolItem(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Admin Control',
          accentColor: const Color(0xFF8E0000),
          screenBuilder: (_) => AdminControlScreen(appState: widget.appState),
        ),
      if (canSettings)
        _MoreToolItem(
          icon: Icons.settings_rounded,
          title: 'Settings',
          accentColor: const Color(0xFF546E7A),
          screenBuilder: (_) => SettingsScreen(
            appState: widget.appState,
            onLogout: () => _logout(context),
          ),
        ),
    ];
    if (adminItems.isNotEmpty) {
      sections.add(
        _MoreToolSection(
          title: 'Administration',
          icon: Icons.admin_panel_settings_rounded,
          accentColor: const Color(0xFF7B1E1E),
          items: adminItems,
        ),
      );
    }

    sections.add(
      _MoreToolSection(
        title: 'My Account',
        icon: Icons.person_rounded,
        accentColor: const Color(0xFF455A64),
        items: [
          _MoreToolItem(
            icon: Icons.lock_rounded,
            title: 'Change Password',
            accentColor: const Color(0xFF455A64),
            screenBuilder: (_) => ChangePasswordScreen(appState: widget.appState),
          ),
          _MoreToolItem(
            icon: Icons.logout_rounded,
            title: 'Logout',
            accentColor: const Color(0xFFE31B23),
            onTap: _logout,
          ),
        ],
      ),
    );

    return sections;
  }

  List<_MoreToolSection> _filteredSections(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final sections = _sections(context);
    if (query.isEmpty) return sections;

    return sections
        .map((section) {
          final titleMatch = section.title.toLowerCase().contains(query);
          final items = titleMatch
              ? section.items
              : section.items
                  .where((item) => item.title.toLowerCase().contains(query))
                  .toList();
          return section.copyWith(items: items);
        })
        .where((section) => section.items.isNotEmpty)
        .toList();
  }

  Future<void> _openTool(_MoreToolItem item) async {
    if (item.onTap != null) {
      await item.onTap!(context);
      return;
    }
    if (item.screenBuilder == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: item.screenBuilder!),
    );
  }

  Widget _toolTile(_MoreToolItem item) {
    return MobileActionTile(
      icon: item.icon,
      title: item.title,
      subtitle: '',
      accentColor: item.accentColor,
      onTap: () => _openTool(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const MobileHeroCard(
          title: 'More Tools',
          subtitle: '',
        ),
        const SizedBox(height: 16),
        MobileSectionCard(
          icon: Icons.search_rounded,
          title: 'Search Tools',
          accentColor: const Color(0xFF455A64),
          child: MobileSearchField(
            controller: _searchCtrl,
            hintText: 'Search tools',
            onSearch: () => setState(() {}),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 16),
        if (sections.isEmpty)
          const MobileEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No tools found',
            message: 'Try a different tool name.',
          )
        else
          ...sections.expand((section) => [
                MobileSectionCard(
                  icon: section.icon,
                  title: section.title,
                  accentColor: section.accentColor,
                  child: Column(
                    children: section.items.map(_toolTile).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ]),
      ],
    );
  }
}

class _MoreToolSection {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<_MoreToolItem> items;

  const _MoreToolSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.items,
  });

  _MoreToolSection copyWith({List<_MoreToolItem>? items}) {
    return _MoreToolSection(
      title: title,
      icon: icon,
      accentColor: accentColor,
      items: items ?? this.items,
    );
  }
}

class _MoreToolItem {
  final IconData icon;
  final String title;
  final Color accentColor;
  final WidgetBuilder? screenBuilder;
  final Future<void> Function(BuildContext context)? onTap;

  const _MoreToolItem({
    required this.icon,
    required this.title,
    required this.accentColor,
    this.screenBuilder,
    this.onTap,
  });
}
