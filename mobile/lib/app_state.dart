import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppState extends ChangeNotifier {
  String baseUrl;
  String? token;
  UserProfile? user;
  Tenant? tenant;
  List<Location> locations;

  AppState({
    required this.baseUrl,
    this.token,
    this.user,
    this.tenant,
    this.locations = const [],
  });

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  static const Map<String, Set<String>> _defaultRolePermissions = {
    'TELLER': {
      'dashboard.view',
      'pos.use',
      'day.manage',
      'products.view',
      'stock.view',
      'customers.view',
      'profile.manage',
    },
    'SUPERVISOR': {
      'dashboard.view',
      'pos.use',
      'day.manage',
      'products.view',
      'products.manage',
      'products.import_export',
      'categories.manage',
      'stock.view',
      'stock.import_export',
      'transfers.manage',
      'stocktake.manage',
      'expenses.manage',
      'refunds.manage',
      'reports.view',
      'customers.view',
      'customers.manage',
      'prepayments.manage',
      'announcements.send',
      'warehouse.transfer',
      'bale.orders.track',
      'release.goods',
      'profile.manage',
    },
    'SHOP_ADMIN': {
      'dashboard.view',
      'pos.use',
      'day.manage',
      'products.view',
      'products.manage',
      'products.import_export',
      'categories.manage',
      'stock.view',
      'stock.import_export',
      'transfers.manage',
      'stocktake.manage',
      'expenses.manage',
      'refunds.manage',
      'reports.view',
      'customers.view',
      'customers.manage',
      'suppliers.manage',
      'prepayments.manage',
      'loyalty.manage',
      'audit.view',
      'users.manage',
      'roles.manage',
      'registrations.approve',
      'announcements.send',
      'settings.manage',
      'locations.manage',
      'warehouse.transfer',
      'bale.orders.track',
      'release.goods',
      'prices.update',
      'profile.manage',
    },
    'TENANT_ADMIN': {
      'dashboard.view',
      'pos.use',
      'day.manage',
      'products.view',
      'products.manage',
      'products.import_export',
      'categories.manage',
      'stock.view',
      'stock.import_export',
      'transfers.manage',
      'stocktake.manage',
      'expenses.manage',
      'refunds.manage',
      'reports.view',
      'customers.view',
      'customers.manage',
      'suppliers.manage',
      'prepayments.manage',
      'loyalty.manage',
      'audit.view',
      'users.manage',
      'roles.manage',
      'registrations.approve',
      'announcements.send',
      'settings.manage',
      'locations.manage',
      'warehouse.transfer',
      'bale.orders.track',
      'release.goods',
      'prices.update',
      'profile.manage',
    },
    'SUPERADMIN': {
      'dashboard.view',
      'pos.use',
      'day.manage',
      'products.view',
      'products.manage',
      'products.import_export',
      'categories.manage',
      'stock.view',
      'stock.import_export',
      'transfers.manage',
      'stocktake.manage',
      'expenses.manage',
      'refunds.manage',
      'reports.view',
      'customers.view',
      'customers.manage',
      'suppliers.manage',
      'prepayments.manage',
      'loyalty.manage',
      'audit.view',
      'users.manage',
      'roles.manage',
      'registrations.approve',
      'announcements.send',
      'settings.manage',
      'locations.manage',
      'warehouse.transfer',
      'bale.orders.track',
      'release.goods',
      'prices.update',
      'profile.manage',
    },
  };

  static const Map<String, Set<String>> _defaultRoleRights = {
    'TENANT_ADMIN': {'shift.collections'},
    'SHOP_ADMIN': {'shift.collections'},
    'SUPERADMIN': {'shift.collections'},
  };

  List<Location> get accessibleLocations {
    final allowedIds = user?.locationIds ?? const <int>[];
    final source = allowedIds.isEmpty
        ? locations
        : locations.where((location) => allowedIds.contains(location.id)).toList();
    final deduped = <int, Location>{};
    for (final location in (source.isEmpty ? locations : source)) {
      deduped[location.id] = location;
    }
    return deduped.values.toList();
  }

  int? get defaultLocationId => user?.locationId ?? (accessibleLocations.isNotEmpty ? accessibleLocations.first.id : null);

  String get roleCode => (user?.role ?? 'TELLER').toUpperCase().trim();

  static const Map<String, String> _permissionAliases = {
    'laybys.manage': 'prepayments.manage',
  };

  static String _canonicalPermission(String key) {
    final trimmed = key.trim();
    return _permissionAliases[trimmed] ?? trimmed;
  }

  bool hasPermission(String key) {
    final current = user;
    if (current == null || key.trim().isEmpty) return false;
    final canonical = _canonicalPermission(key);
    if (current.permissions.isNotEmpty) {
      return current.permissions.contains(canonical) || current.permissions.contains(key.trim());
    }
    return (_defaultRolePermissions[roleCode] ?? const <String>{}).contains(canonical);
  }

  bool hasRight(String key) {
    final current = user;
    if (current == null || key.trim().isEmpty) return false;
    if (current.rights.isNotEmpty) {
      return current.rights.contains(key);
    }
    return (_defaultRoleRights[roleCode] ?? const <String>{}).contains(key);
  }

  static const _kBaseUrl = 'base_url';
  static const _kToken = 'token';
  static const _kUser = 'user_json';
  static const _kTenant = 'tenant_json';
  static const _kLocations = 'locations_json';

  static String _normalizeBaseUrl(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned == 'https://bales.rapidconnect.co.zw') {
      return 'http://bales.rapidconnect.co.zw';
    }
    return cleaned;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedBase = prefs.getString(_kBaseUrl);
    baseUrl = _normalizeBaseUrl(storedBase ?? baseUrl);
    if (storedBase != null && storedBase != baseUrl) {
      await prefs.setString(_kBaseUrl, baseUrl);
    }
    token = prefs.getString(_kToken);

    final uj = prefs.getString(_kUser);
    if (uj != null) {
      try { user = UserProfile.fromJson(jsonDecode(uj)); } catch (_) {}
    }
    final tj = prefs.getString(_kTenant);
    if (tj != null) {
      try { tenant = Tenant.fromJson(jsonDecode(tj)); } catch (_) {}
    }
    final lj = prefs.getString(_kLocations);
    if (lj != null) {
      try {
        final arr = (jsonDecode(lj) as List<dynamic>).cast<Map<String, dynamic>>();
        locations = arr.map(Location.fromJson).toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = _normalizeBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    notifyListeners();
  }

  Future<void> saveSession({
    required String token,
    required UserProfile user,
    required Tenant tenant,
    required List<Location> locations,
  }) async {
    this.token = token;
    this.user = user;
    this.tenant = tenant;
    this.locations = locations;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, jsonEncode({
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'role': user.role,
      'display_role': user.displayRole,
      'tenant_id': user.tenantId,
      'location_id': user.locationId,
      'location_ids': user.locationIds,
      'permissions': user.permissions,
      'rights': user.rights,
    }));
    await prefs.setString(_kTenant, jsonEncode({'id': tenant.id, 'name': tenant.name, 'logo_path': tenant.logoPath}));
    await prefs.setString(_kLocations, jsonEncode(locations.map((l) => {
      'id': l.id, 'name': l.name, 'type': l.type
    }).toList()));
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    tenant = null;
    locations = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    await prefs.remove(_kTenant);
    await prefs.remove(_kLocations);
    notifyListeners();
  }
}
