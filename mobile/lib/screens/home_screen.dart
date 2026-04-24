import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../services/sync_service.dart';
import 'change_password_screen.dart';
import 'bale_movement_screen.dart';
import 'bales_screen.dart';
import 'dashboard_tab.dart';
import 'more_screen.dart';
import 'pos_screen.dart';
import 'stock_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState appState;
  const HomeScreen({super.key, required this.appState});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription? _connSub;
  int _queued = 0;
  bool _syncing = false;
  final Map<int, Widget> _pageCache = {};
  final Map<int, GlobalKey<NavigatorState>> _navigatorKeys = {};
  DateTime? _lastBackPressedAt;

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  List<_HomeTabItem> _buildTabs() {
    final tabs = <_HomeTabItem>[];
    if (widget.appState.hasPermission('dashboard.view')) {
      tabs.add(
        _HomeTabItem(
          item: const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          builder: () => DashboardTab(appState: widget.appState),
        ),
      );
    }
    if (widget.appState.hasPermission('pos.use')) {
      tabs.add(
        _HomeTabItem(
          item: const BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'Bale Sales',
          ),
          builder: () => PosScreen(appState: widget.appState),
        ),
      );
    }
    if (widget.appState.hasPermission('products.view')) {
      tabs.add(
        _HomeTabItem(
          item: const BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Bales',
          ),
          builder: () => BalesScreen(appState: widget.appState),
        ),
      );
    }
    if (widget.appState.hasPermission('bale.orders.track')) {
      tabs.add(
        _HomeTabItem(
          item: const BottomNavigationBarItem(
            icon: Icon(Icons.route_rounded),
            label: 'Movement',
          ),
          builder: () => BaleMovementScreen(appState: widget.appState),
        ),
      );
    }
    if (widget.appState.hasPermission('stock.view')) {
      tabs.add(
        _HomeTabItem(
          item: const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
          builder: () => StockScreen(appState: widget.appState),
        ),
      );
    }
    tabs.add(
      _HomeTabItem(
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.more_horiz),
          label: 'More',
        ),
        builder: () => MoreScreen(appState: widget.appState),
      ),
    );
    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
    _requestNotificationPermission();
    unawaited(_trySync());
    _connSub = Connectivity().onConnectivityChanged.listen((_) {
      _refreshQueueCount();
      unawaited(_trySync());
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshQueueCount() async {
    final count = await LocalDb.instance.queuedCount();
    if (!mounted) return;
    setState(() => _queued = count);
  }

  Future<void> _trySync() async {
    if (_syncing) return;
    if (!widget.appState.isLoggedIn) return;
    final conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) return;
    _syncing = true;
    try {
      await SyncService.syncQueuedSales(api);
      await SyncService.syncProductCache(api);
      await _refreshQueueCount();
    } catch (_) {
      // Keep silent here; sync retries again automatically.
    }
    _syncing = false;
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted || status.isLimited) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Keep silent on platforms where notification permission is not exposed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantName = widget.appState.tenant?.name ?? 'T.One Bales';
    final userName = widget.appState.user?.name ?? 'User';
    final role = (widget.appState.user?.role ?? 'TELLER').toUpperCase();
    final displayRole = ((widget.appState.user?.displayRole ?? '').trim().isNotEmpty)
        ? widget.appState.user!.displayRole!.trim()
        : role;
    final tabs = _buildTabs();
    final navItems = tabs.map((tab) => tab.item).toList();

    final safeTab = _tab >= navItems.length ? 0 : _tab;
    if (safeTab != _tab) {
      _tab = safeTab;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3F0),
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tenantName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '$userName - $displayRole',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_queued > 0)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  'Queued: $_queued',
                  style: const TextStyle(
                    color: Color(0xFFE31B23),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'password') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordScreen(
                      appState: widget.appState,
                    ),
                  ),
                );
              }
              if (value == 'logout') {
                await widget.appState.logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'password',
                child: Text('Change Password'),
              ),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final currentNavigator = _navigatorKeys[safeTab]?.currentState;
          if (currentNavigator != null && currentNavigator.canPop()) {
            currentNavigator.pop();
            return;
          }
          if (_tab != 0) {
            setState(() => _tab = 0);
            return;
          }
          final now = DateTime.now();
          if (_lastBackPressedAt == null ||
              now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
            _lastBackPressedAt = now;
            if (mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Press back again to close the app.')),
                );
            }
            return;
          }
          await SystemNavigator.pop();
        },
        child: KeyedSubtree(
          key: ValueKey('home-tab-$safeTab'),
          child: Navigator(
            key: _navigatorKeys.putIfAbsent(safeTab, () => GlobalKey<NavigatorState>()),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => _pageForTab(safeTab, tabs),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeTab,
        onTap: (i) => setState(() => _tab = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFE31B23),
        unselectedItemColor: Colors.black54,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        items: navItems,
      ),
    );
  }

  Widget _pageForTab(int index, List<_HomeTabItem> tabs) {
    final cacheKey = index;
    return _pageCache.putIfAbsent(cacheKey, () {
      if (index < 0 || index >= tabs.length) {
        return DashboardTab(appState: widget.appState);
      }
      return tabs[index].builder();
    });
  }
}

class _HomeTabItem {
  final BottomNavigationBarItem item;
  final Widget Function() builder;

  const _HomeTabItem({
    required this.item,
    required this.builder,
  });
}
