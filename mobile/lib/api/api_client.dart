import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../models.dart';

class ApiClient {
  final String baseUrl;
  final String? token;
  static const String connectionFallback =
      'Could not connect right now. Check your internet connection and tap Reload to try again.';

  ApiClient({required this.baseUrl, required this.token});

  static String friendlyError(
    Object error, {
    String fallback = connectionFallback,
  }) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) return fallback;

    final sanitized = raw
        .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), 'the server')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final text = sanitized.toLowerCase();

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('connection aborted') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('handshakeexception') ||
        text.contains('cloudflare') ||
        text.contains('web server is down') ||
        text.contains('http 520') ||
        text.contains('http 521') ||
        text.contains('http 522') ||
        text.contains('http 523') ||
        text.contains('http 524') ||
        text.contains('http 525') ||
        text.contains('http 526') ||
        RegExp(r'\b52[0-6]\b').hasMatch(text) ||
        text.contains('could not reach server')) {
      return fallback;
    }
    if (text.contains('html error page') || text.contains('latest server update')) {
      return 'The app needs the latest web update on the server. Upload the newest backend files and try again.';
    }
    if (text == 'not found' || text.contains('http 404') || text.contains('not_found')) {
      return 'This feature is not available on the current server yet. Upload the latest backend update and try again.';
    }
    if (text.contains('unauthorized') || text.contains('forbidden')) {
      return 'Your session or access rights need attention. Sign in again or ask an admin to check your permissions.';
    }
    if (text.contains('sqlstate') ||
        text.contains('stack trace') ||
        text.contains('unexpected character') ||
        text.contains('format exception') ||
        text.contains('<!doctype') ||
        text.contains('<html') ||
        (text.contains('exception') &&
            !text.contains('not found') &&
            !text.contains('forbidden') &&
            !text.contains('unauthorized'))) {
      return fallback;
    }
    if (sanitized.length > 160) {
      return fallback;
    }
    return sanitized;
  }

  static bool isConnectionIssue(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim().toLowerCase();
    if (raw.isEmpty) return true;
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('connection aborted') ||
        raw.contains('network is unreachable') ||
        raw.contains('timed out') ||
        raw.contains('handshakeexception') ||
        raw.contains('cloudflare') ||
        raw.contains('web server is down') ||
        raw.contains('http 520') ||
        raw.contains('http 521') ||
        raw.contains('http 522') ||
        raw.contains('http 523') ||
        raw.contains('http 524') ||
        raw.contains('http 525') ||
        raw.contains('http 526') ||
        raw.contains('could not reach server');
  }

  static String _cleanBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static Uri _uriForBase(String effectiveBaseUrl, String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    if (query != null) {
      query.forEach((k, v) {
        if (v == null) return;
        q[k] = v.toString();
      });
    }
    return Uri.parse('${_cleanBaseUrl(effectiveBaseUrl)}/api$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  Uri _u(String path, [Map<String, dynamic>? query]) {
    return _uriForBase(baseUrl, path, query);
  }

  static List<String> _candidateBaseUrlsFor(String rawBaseUrl) {
    final cleaned = _cleanBaseUrl(rawBaseUrl);
    final candidates = <String>[cleaned];
    if (cleaned.startsWith('https://')) {
      candidates.add('http://${cleaned.substring('https://'.length)}');
    }
    return candidates;
  }

  bool _shouldRetryOverHttp(http.Response res, Uri uri) {
    if (uri.scheme != 'https') return false;
    if (const {404, 502, 503, 504, 521, 525, 526}.contains(res.statusCode)) {
      return true;
    }
    final message = _responseMessage(res).toLowerCase();
    return message.contains('unexpected error occurred on a receive') ||
        message.contains('html error page');
  }

  Map<String, String> _headers({bool auth = true}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };
    if (auth && token != null && token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? fallback;
  }

  double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? fallback;
  }

  bool _isNotFoundError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('not_found') || text.contains('http 404') || text.contains('not found');
  }

  String _responseMessage(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) {
      return 'The server returned an empty response (HTTP ${res.statusCode}).';
    }

    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return (data['message'] ?? data['error'] ?? 'HTTP ${res.statusCode}').toString();
      }
    } catch (_) {
      // Fall through to plain-text / HTML cleanup below.
    }

    final plain = body
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isNotEmpty) {
      final snippet = plain.length > 180 ? '${plain.substring(0, 180)}...' : plain;
      if (snippet.toLowerCase() == 'not found') {
        return 'This action needs the latest server update. The requested route was not found.';
      }
      return snippet;
    }

    if (body.startsWith('<')) {
      return 'The server returned an HTML error page instead of JSON. Upload the latest backend files and try again.';
    }

    return 'HTTP ${res.statusCode}';
  }

  Map<String, dynamic> _decodeResponse(http.Response res) {
    final body = res.body.trim();
    if (res.statusCode >= 520 && res.statusCode <= 526) {
      throw Exception(connectionFallback);
    }
    if (body.isEmpty) {
      if (res.statusCode >= 400) {
        throw Exception(
          friendlyError(
            'The server returned an empty response (HTTP ${res.statusCode}).',
            fallback: connectionFallback,
          ),
        );
      }
      return <String, dynamic>{'ok': true};
    }
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return data;
      }
      throw Exception('Unexpected response shape from server.');
    } on FormatException {
      throw Exception(
        friendlyError(
          _responseMessage(res),
          fallback: connectionFallback,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query}) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrlsFor(baseUrl)) {
      final uri = _uriForBase(candidate, path, query);
      try {
        final res = await http.get(uri, headers: _headers());
        if (_shouldRetryOverHttp(res, uri)) {
          lastError = Exception(_responseMessage(res));
          continue;
        }
        final data = _decodeResponse(res);
        if (res.statusCode >= 400) {
          throw Exception(
            friendlyError(
              (data['message'] ?? data['error'] ?? _responseMessage(res)).toString(),
              fallback: connectionFallback,
            ),
          );
        }
        return data;
      } on HandshakeException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on SocketException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on http.ClientException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      }
    }
    throw Exception(
      friendlyError(
        lastError ?? 'Could not reach server.',
        fallback: connectionFallback,
      ),
    );
  }

  Future<Map<String, dynamic>> getBaleReportsDashboard({
    required String from,
    required String to,
    int? locationId,
  }) async {
    try {
      return await _get('/reports/bale_dashboard', query: {
        'from': from,
        'to': to,
        if (locationId != null) 'location_id': locationId,
      });
    } catch (_) {
      final summary = await getReportSummary(
        from: from,
        to: to,
        locationId: locationId,
      );
      final series = await getReportTimeSeries(
        from: from,
        to: to,
        locationId: locationId,
      );
      final byLocation = await getReportByLocation(from: from, to: to);
      return {
        'ok': true,
        'summary': {
          'date_from': summary.dateFrom,
          'date_to': summary.dateTo,
          'total_sales': summary.totalSales,
          'sales_count': summary.salesCount,
          'gross_profit': summary.grossProfit,
          'expenses': summary.expenses,
          'net_profit': summary.netProfit,
        },
        'series': series,
        'by_location': byLocation,
        'sale_transactions': const <String, dynamic>{},
        'close_shift': const <String, dynamic>{},
        'stock_distribution': const <String, dynamic>{},
        'stock_orders': const <String, dynamic>{},
        'stock_receivables': const <String, dynamic>{},
        'creditors': const <String, dynamic>{},
        'debtors': const <String, dynamic>{},
        'prices': const <String, dynamic>{},
      };
    }
  }

  Future<Map<String, dynamic>> _post(String path, {Map<String, dynamic>? body, bool auth = true}) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrlsFor(baseUrl)) {
      final uri = _uriForBase(candidate, path);
      try {
        final res = await http.post(uri, headers: _headers(auth: auth), body: jsonEncode(body ?? {}));
        if (_shouldRetryOverHttp(res, uri)) {
          lastError = Exception(_responseMessage(res));
          continue;
        }
        final data = _decodeResponse(res);
        if (res.statusCode >= 400) {
          throw Exception(
            friendlyError(
              (data['message'] ?? data['error'] ?? _responseMessage(res)).toString(),
              fallback: connectionFallback,
            ),
          );
        }
        return data;
      } on HandshakeException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on SocketException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on http.ClientException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      }
    }
    throw Exception(
      friendlyError(
        lastError ?? 'Could not reach server.',
        fallback: connectionFallback,
      ),
    );
  }

  // Auth
  static Future<({String token, UserProfile user, Tenant tenant, List<Location> locations})> login({
    required String baseUrl,
    required String identifier,
    required String password,
  }) async {
    final client = ApiClient(baseUrl: baseUrl, token: null);
    http.Response? lastResponse;
    Object? lastError;
    for (final candidate in _candidateBaseUrlsFor(baseUrl)) {
      final uri = _uriForBase(candidate, '/login');
      try {
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        );
        if (client._shouldRetryOverHttp(res, uri)) {
          lastResponse = res;
          continue;
        }
        final data = client._decodeResponse(res);
        if (res.statusCode >= 400) {
          throw Exception(
            friendlyError(
              (data['message'] ?? data['error'] ?? client._responseMessage(res)).toString(),
              fallback: connectionFallback,
            ),
          );
        }
        final token = (data['token'] ?? '').toString();
        final user = UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
        final tenant = Tenant.fromJson(Map<String, dynamic>.from(data['tenant'] as Map));
        final locs = (data['locations'] as List<dynamic>).map((e) => Location.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        return (token: token, user: user, tenant: tenant, locations: locs);
      } on HandshakeException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on SocketException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on http.ClientException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      }
    }
    if (lastResponse != null) {
      final data = client._decodeResponse(lastResponse);
      throw Exception(
        friendlyError(
          (data['message'] ?? data['error'] ?? client._responseMessage(lastResponse)).toString(),
          fallback: connectionFallback,
        ),
      );
    }
    throw Exception(
      friendlyError(
        lastError ?? 'Could not reach server.',
        fallback: connectionFallback,
      ),
    );
  }

  static Future<void> register({
    required String baseUrl,
    required String name,
    required String email,
    required String password,
    String username = '',
    String phone = '',
    String note = '',
  }) async {
    final client = ApiClient(baseUrl: baseUrl, token: null);
    http.Response? lastResponse;
    Object? lastError;
    final body = {
      'name': name,
      'email': email,
      'password': password,
      if (username.isNotEmpty) 'username': username,
      if (phone.isNotEmpty) 'phone': phone,
      if (note.isNotEmpty) 'note': note,
    };
    for (final candidate in _candidateBaseUrlsFor(baseUrl)) {
      final uri = _uriForBase(candidate, '/register');
      try {
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (client._shouldRetryOverHttp(res, uri)) {
          lastResponse = res;
          continue;
        }
        final data = client._decodeResponse(res);
        if (res.statusCode >= 400) {
          throw Exception(
            friendlyError(
              (data['message'] ?? data['error'] ?? client._responseMessage(res)).toString(),
              fallback: connectionFallback,
            ),
          );
        }
        return;
      } on HandshakeException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on SocketException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      } on http.ClientException catch (e) {
        lastError = e;
        if (uri.scheme == 'https') continue;
        rethrow;
      }
    }
    if (lastResponse != null) {
      final data = client._decodeResponse(lastResponse);
      throw Exception(
        friendlyError(
          (data['message'] ?? data['error'] ?? client._responseMessage(lastResponse)).toString(),
          fallback: connectionFallback,
        ),
      );
    }
    throw Exception(
      friendlyError(
        lastError ?? 'Could not reach server.',
        fallback: connectionFallback,
      ),
    );
  }

  Future<List<Location>> getLocations() async {
    final data = await _get('/locations');
    final locs = (data['locations'] as List<dynamic>).map((e) => Location.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return locs;
  }

  Future<int> createLocation({
    required String name,
    required String type,
  }) async {
    final data = await _post('/locations/create', body: {
      'name': name,
      'type': type,
    });
    return _asInt(data['id']);
  }

  Future<void> updateLocation({
    required int id,
    required String name,
    required String type,
  }) async {
    await _post('/locations/update', body: {
      'id': id,
      'name': name,
      'type': type,
    });
  }

  Future<void> deleteLocation(int id) async {
    await _post('/locations/delete', body: {
      'id': id,
    });
  }

  Future<List<Product>> getProducts({String? search, bool all = false, String? barcode, int? limit}) async {
    final data = await _get('/products', query: {
      if (all) 'all': 1,
      if (search != null && search.isNotEmpty) 'search': search,
      if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
      if (limit != null && limit > 0) 'limit': limit,
    });
    final products = (data['products'] as List<dynamic>).map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return products;
  }

  Future<List<Map<String, dynamic>>> getProductRows({
    String? search,
    bool all = false,
    String? barcode,
    int? limit,
    int? locationId,
    bool inStockOnly = false,
  }) async {
    final data = await _get('/products', query: {
      if (all) 'all': 1,
      if (search != null && search.isNotEmpty) 'search': search,
      if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
      if (limit != null && limit > 0) 'limit': limit,
      if (locationId != null && locationId > 0) 'location_id': locationId,
      if (inStockOnly) 'pos': 1,
    });
    return (data['products'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> createProduct({
    required String name,
    String barcode = '',
    double costPrice = 0,
    double sellPrice = 0,
    int reorderLevel = 0,
  }) async {
    final data = await _post('/products/create', body: {
      'name': name,
      if (barcode.isNotEmpty) 'barcode': barcode,
      'cost_price': costPrice,
      'sell_price': sellPrice,
      'reorder_level': reorderLevel,
    });
    return _asInt(data['id']);
  }

  Future<void> updateProduct({
    required int id,
    required String name,
    String barcode = '',
    double costPrice = 0,
    double sellPrice = 0,
    int reorderLevel = 0,
  }) async {
    await _post('/products/update', body: {
      'id': id,
      'name': name,
      'barcode': barcode,
      'cost_price': costPrice,
      'sell_price': sellPrice,
      'reorder_level': reorderLevel,
    });
  }

  Future<void> deleteProduct(int id) async {
    await _post('/products/delete', body: {
      'id': id,
    });
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _post('/profile/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<List<Map<String, dynamic>>> getReportTimeSeries({
    required String from,
    required String to,
    int? locationId,
  }) async {
    final data = await _get('/reports/timeseries', query: {
      'from': from,
      'to': to,
      if (locationId != null) 'location_id': locationId,
    });
    final rows = (data['series'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return rows;
  }

  Future<List<Map<String, dynamic>>> getReportByLocation({
    required String from,
    required String to,
  }) async {
    final data = await _get('/reports/by_location', query: {
      'from': from,
      'to': to,
    });
    final rows = (data['rows'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return rows;
  }

  Future<Map<String, dynamic>> importStock({
    required int locationId,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post('/stock/import', body: {
      'location_id': locationId,
      'items': items,
    });
    return data;
  }

  Future<void> setStock({
    required int locationId,
    required int productId,
    required double onHand,
  }) async {
    await _post('/stock/set', body: {
      'location_id': locationId,
      'product_id': productId,
      'on_hand': onHand,
    });
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async {
    final data = await _post('/sales', body: payload);
    return data;
  }

  Future<List<StockRow>> getStock({required int locationId, String search = ''}) async {
    final data = await _get('/stock', query: {'location_id': locationId, 'search': search});
    final rows = (data['rows'] as List<dynamic>).map((e) => StockRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return rows;
  }

  Future<Map<String, dynamic>> getStockOutData({
    required int locationId,
    String search = '',
  }) async {
    return _get('/stock/out', query: {
      'location_id': locationId,
      if (search.isNotEmpty) 'search': search,
    });
  }

  Future<List<Transfer>> getTransfers({String? status, int? toLocationId, int? fromLocationId}) async {
    final data = await _get('/transfers', query: {
      if (status != null && status.isNotEmpty) 'status': status,
      if (toLocationId != null) 'to_location_id': toLocationId,
      if (fromLocationId != null) 'from_location_id': fromLocationId,
    });
    final rows = (data['transfers'] as List<dynamic>).map((e) => Transfer.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return rows;
  }

  Future<({Transfer transfer, List<TransferItem> items})> getTransfer(int id) async {
    final data = await _get('/transfers/$id');
    final t = Transfer.fromJson(Map<String, dynamic>.from(data['transfer'] as Map));
    final items = (data['items'] as List<dynamic>).map((e) => TransferItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return (transfer: t, items: items);
  }

  Future<void> dispatchTransfer(int id) async {
    await _post('/transfers/$id/dispatch', body: {});
  }

  Future<int> createTransfer({
    required int fromLocationId,
    required int toLocationId,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post('/transfers', body: {
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'items': items,
    });
    return _asInt(data['transfer_id']);
  }

  Future<void> receiveTransfer(int id, List<Map<String, dynamic>> items) async {
    await _post('/transfers/$id/receive', body: {'items': items});
  }

  Future<List<Map<String, dynamic>>> listStockTakes() async {
    final data = await _get('/stocktakes');
    return (data['stocktakes'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> startStockTake(int locationId) async {
    final data = await _post('/stocktakes', body: {'location_id': locationId});
    return _asInt(data['stock_take_id']);
  }

  Future<Map<String, dynamic>> getStockTake(int id) async {
    final data = await _get('/stocktakes/$id');
    return data;
  }

  Future<void> finalizeStockTake(int id, List<Map<String, dynamic>> items) async {
    await _post('/stocktakes/$id/finalize', body: {'items': items});
  }

  Future<Map<String, dynamic>> getStockTakeReport(int id) async {
    return _get('/stocktakes/$id/report');
  }

  Future<ReportSummary> getReportSummary({required String from, required String to, int? locationId}) async {
    final data = await _get('/reports/summary', query: {
      'from': from,
      'to': to,
      if (locationId != null) 'location_id': locationId,
    });
    final summary = ReportSummary.fromJson(Map<String, dynamic>.from(data['summary'] as Map));
    return summary;
  }

  // ── Sale lookup ───────────────────────────────────────────────
  Future<SaleDetail> lookupSale({required String saleNumber}) async {
    final data = await _get('/sales/lookup', query: {'sale_number': saleNumber});
    final sale = Map<String, dynamic>.from(data['sale'] as Map);
    // Merge items into sale map so SaleDetail.fromJson can parse them
    if (data['items'] != null) {
      sale['items'] = data['items'];
    }
    return SaleDetail.fromJson(sale);
  }

  // ── Refunds ───────────────────────────────────────────────────
  Future<List<Refund>> getRefunds({String? from, String? to, int? locationId}) async {
    final data = await _get('/refunds', query: {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
    final rows = (data['refunds'] as List<dynamic>)
        .map((e) => Refund.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return rows;
  }

  Future<Map<String, dynamic>> processRefund({
    required int saleId,
    required String reason,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post('/refunds', body: {
      'sale_id': saleId,
      'reason': reason,
      'items': items,
    });
    return data;
  }

  Future<Map<String, dynamic>> getRefundDetail(int id) async {
    final data = await _get('/refunds/$id');
    return data;
  }

  // ── Stock: add increment ──────────────────────────────────────
  Future<void> addStock({
    required int locationId,
    required int productId,
    required int quantity,
    String note = '',
  }) async {
    await _post('/stock/add', body: {
      'location_id': locationId,
      'product_id': productId,
      'quantity': quantity,
      if (note.isNotEmpty) 'note': note,
    });
  }

  // ── Low stock alerts ──────────────────────────────────────────
  Future<List<LowStockItem>> getLowStock({int? locationId, int? threshold}) async {
    final data = await _get('/stock/low', query: {
      if (locationId != null) 'location_id': locationId,
      if (threshold != null) 'threshold': threshold,
    });
    final rows = (data['items'] as List<dynamic>)
        .map((e) => LowStockItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return rows;
  }

  // ── Categories ────────────────────────────────────────────────
  Future<List<ProductCategory>> getCategories() async {
    final data = await _get('/categories');
    return (data['categories'] as List<dynamic>)
        .map((e) => ProductCategory.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ProductCategory>> getBaleCategories() async {
    final data = await _get('/bale-categories');
    return (data['categories'] as List<dynamic>)
        .map((e) => ProductCategory.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> createBaleCategory({
    required String name,
    String description = '',
  }) async {
    final data = await _post('/bale-categories', body: {
      'name': name,
      if (description.isNotEmpty) 'description': description,
    });
    return _asInt(data['id']);
  }

  Future<void> updateBaleCategory(
    int id, {
    required String name,
    String description = '',
  }) async {
    await _post('/bale-categories/$id', body: {
      'name': name,
      'description': description,
    });
  }

  Future<void> deleteBaleCategory(int id) async {
    await _post('/bale-categories/$id', body: {'_action': 'delete'});
  }

  Future<List<Map<String, dynamic>>> getBaleLabels() async {
    final data = await _get('/bale-labels');
    return (data['labels'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> createBaleLabel({
    required String name,
    String description = '',
  }) async {
    final data = await _post('/bale-labels', body: {
      'name': name,
      if (description.isNotEmpty) 'description': description,
    });
    return _asInt(data['id']);
  }

  Future<void> updateBaleLabel(
    int id, {
    required String name,
    String description = '',
  }) async {
    await _post('/bale-labels/$id', body: {
      'name': name,
      'description': description,
    });
  }

  Future<void> deleteBaleLabel(int id) async {
    await _post('/bale-labels/$id', body: {'_action': 'delete'});
  }

  Future<Map<String, dynamic>> getBaleMovement({
    String search = '',
    int? categoryId,
    String? date,
    String? dateFrom,
    String? dateTo,
    int? grade,
  }) async {
    return _get('/bale-movement', query: {
      if (search.isNotEmpty) 'search': search,
      if (categoryId != null && categoryId > 0) 'category_id': categoryId,
      if (date != null && date.isNotEmpty) 'date': date,
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      if (grade != null && grade > 0) 'grade': grade,
    });
  }

  Future<void> reverseBaleMovement(int baleId, {String reason = ''}) async {
    await _post('/bale-movement/reverse', body: {
      'receipt_id': baleId,
      if (reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> getBaleOrders({String search = '', String status = 'OPEN'}) async {
    final data = await _get('/bale-orders', query: {
      if (search.isNotEmpty) 'search': search,
      if (status.isNotEmpty) 'status': status,
    });
    return (data['orders'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getBaleOrder(int id) async {
    final data = await _get('/bale-orders/$id');
    return Map<String, dynamic>.from(data['order'] as Map);
  }

  Future<int> createBaleOrderFromBale({
    required int baleId,
    required int quantityOrdered,
    String orderedByName = '',
    String receivedByName = '',
    int? receivedByUserId,
    double? costPrice,
    double? sellPrice,
    String supplierName = '',
    String note = '',
  }) async {
    final body = {
      'bale_id': baleId,
      'quantity_ordered': quantityOrdered,
      if (receivedByName.isNotEmpty) 'received_by_name': receivedByName,
      if (receivedByUserId != null && receivedByUserId > 0) 'received_by_user_id': receivedByUserId,
      if (costPrice != null) 'cost_price': costPrice,
      if (sellPrice != null) 'sell_price': sellPrice,
      if (supplierName.isNotEmpty) 'supplier_name': supplierName,
      if (note.isNotEmpty) 'notes': note,
    };

    try {
      final data = await _post('/bale-orders/from-bale', body: body);
      return _asInt(data['id']);
    } catch (error) {
      if (!_isNotFoundError(error)) rethrow;

      final baleData = await _get('/bales/$baleId');
      final bale = Map<String, dynamic>.from(baleData['bale'] as Map);
      final data = await _post('/bale-orders', body: {
        'ordered_by_name': orderedByName,
        'received_by_name': receivedByName,
        if (supplierName.isNotEmpty) 'supplier_name': supplierName,
        if (note.isNotEmpty) 'notes': note,
        'items': [
          {
            'source_bale_id': baleId,
            'category_id': _asInt(bale['category_id']),
            'product_id': _asInt(bale['product_id']),
            'label_id': _asInt(bale['label_id']),
            'grade': _asInt(bale['grade']),
            'unit_of_measure': (bale['unit_of_measure'] ?? 'PCS').toString(),
            'unit_quantity': _asDouble(bale['unit_quantity']),
            'cost_price': costPrice ?? _asDouble(bale['cost_price']),
            'sell_price': sellPrice ?? _asDouble(bale['sell_price']),
            'label': (bale['label_name'] ?? bale['label'] ?? '').toString(),
            'description': (bale['product_name'] ?? bale['description'] ?? '').toString(),
            'quantity_ordered': quantityOrdered,
            if (note.isNotEmpty) 'note': note,
          },
        ],
      });
      return _asInt(data['id']);
    }
  }

  Future<void> updateBaleOrder(int id, Map<String, dynamic> payload) async {
    await _post('/bale-orders/$id', body: payload);
  }

  Future<void> deleteBaleOrder(int id) async {
    await _post('/bale-orders/$id', body: {'_action': 'delete'});
  }

  Future<int> receiveBaleOrderItem(
    int orderItemId, {
    required int locationId,
    required int quantityReceived,
    required double sellPrice,
    String receivedByName = '',
  }) async {
    final data = await _post('/bale-orders/items/$orderItemId/receive', body: {
      'location_id': locationId,
      'quantity_received': quantityReceived,
      'sell_price': sellPrice,
      if (receivedByName.isNotEmpty) 'received_by_name': receivedByName,
    });
    return _asInt(data['receipt_id']);
  }

  Future<List<Map<String, dynamic>>> getBales({
    String search = '',
    int? categoryId,
    int? labelId,
    int? productId,
    int? grade,
    int? locationId,
    int? limit,
  }) async {
    final data = await _get('/bales', query: {
      if (search.isNotEmpty) 'search': search,
      if (categoryId != null && categoryId > 0) 'category_id': categoryId,
      if (labelId != null && labelId > 0) 'label_id': labelId,
      if (productId != null && productId > 0) 'product_id': productId,
      if (grade != null && grade > 0) 'grade': grade,
      if (locationId != null && locationId > 0) 'location_id': locationId,
      if (limit != null && limit > 0) 'limit': limit,
    });
    return (data['bales'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> saveBale(Map<String, dynamic> payload) async {
    final data = await _post('/bales', body: payload);
    return _asInt(data['id']);
  }

  Future<void> updateBale(int id, Map<String, dynamic> payload) async {
    await _post('/bales/$id', body: payload);
  }

  Future<void> deleteBale(int id) async {
    await _post('/bales/$id', body: {'_action': 'delete'});
  }

  Future<void> postStockOut({
    required int locationId,
    required int productId,
    String action = 'REMOVE',
    int quantity = 0,
    int? targetQty,
    String note = '',
  }) async {
    await _post('/stock/out', body: {
      'location_id': locationId,
      'product_id': productId,
      'action': action,
      if (action == 'ADJUST') 'target_qty': targetQty,
      if (action != 'ADJUST') 'quantity': quantity,
      if (note.isNotEmpty) 'note': note,
    });
  }

  Future<int> createCategory({required String name, int? parentId, int sortOrder = 0}) async {
    final data = await _post('/categories', body: {'name': name, 'parent_id': parentId, 'sort_order': sortOrder});
    return _asInt(data['id']);
  }

  Future<void> updateCategory(int id, {required String name, int? parentId, int sortOrder = 0}) async {
    await _post('/categories/$id', body: {'name': name, 'parent_id': parentId, 'sort_order': sortOrder});
  }

  Future<void> deleteCategory(int id) async {
    await _post('/categories/$id', body: {'_action': 'delete'});
  }

  // ── Customers ─────────────────────────────────────────────────
  Future<List<Customer>> getCustomers({String search = ''}) async {
    final data = await _get('/customers', query: {if (search.isNotEmpty) 'search': search});
    return (data['customers'] as List<dynamic>)
        .map((e) => Customer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Customer>> searchCustomers(String q) async {
    final data = await _get('/customers/search', query: {'q': q});
    return (data['customers'] as List<dynamic>)
        .map((e) => Customer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> createCustomer(Map<String, dynamic> payload) async {
    final data = await _post('/customers', body: payload);
    return _asInt(data['id']);
  }

  Future<Map<String, dynamic>> importCustomersFile({
    required String filePath,
    String? filename,
  }) async {
    final request = http.MultipartRequest('POST', _u('/customers/import'));
    if (token != null && token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'customer_file',
        filePath,
        filename: filename ?? filePath.split(Platform.pathSeparator).last,
      ),
    );
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = _decodeResponse(res);
    if (res.statusCode >= 400) {
      throw Exception((data['message'] ?? data['error'] ?? _responseMessage(res)).toString());
    }
    return data;
  }

  Future<Map<String, dynamic>> importCustomersFromPhonebook(
    List<Map<String, dynamic>> customers,
  ) async {
    return _post('/customers/import-contacts', body: {
      'customers': customers,
    });
  }

  Future<void> updateCustomer(int id, Map<String, dynamic> payload) async {
    await _post('/customers/$id', body: payload);
  }

  Future<void> deleteCustomer(int id) async {
    await _post('/customers/$id', body: {'_action': 'delete'});
  }

  Future<Map<String, dynamic>> getCustomer(int id) async {
    return await _get('/customers/$id');
  }

  // ── Suppliers ─────────────────────────────────────────────────
  Future<List<Supplier>> getSuppliers({String search = ''}) async {
    final data = await _get('/suppliers', query: {if (search.isNotEmpty) 'search': search});
    return (data['suppliers'] as List<dynamic>)
        .map((e) => Supplier.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> createSupplier(Map<String, dynamic> payload) async {
    final data = await _post('/suppliers', body: payload);
    return _asInt(data['id']);
  }

  Future<void> updateSupplier(int id, Map<String, dynamic> payload) async {
    await _post('/suppliers/$id', body: payload);
  }

  Future<void> deleteSupplier(int id) async {
    await _post('/suppliers/$id', body: {'_action': 'delete'});
  }

  Future<Map<String, dynamic>> getSaleTransactions({
    String search = '',
    int? categoryId,
    int? labelId,
    int? customerId,
    int? salespersonId,
    int? shopId,
    String? dateFrom,
    String? dateTo,
  }) async {
      return _get('/sales/transactions', query: {
        if (search.isNotEmpty) 'search': search,
        if (categoryId != null && categoryId > 0) 'category_id': categoryId,
        if (labelId != null && labelId > 0) 'label_id': labelId,
        if (customerId != null && customerId > 0) 'customer_id': customerId,
        if (salespersonId != null && salespersonId > 0) 'salesperson_id': salespersonId,
        if (shopId != null && shopId > 0) 'shop_id': shopId,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      });
    }

  Future<Map<String, dynamic>> getCustomerBalances({String search = '', int? locationId}) async {
    return _get('/customer-balances', query: {
      if (search.isNotEmpty) 'search': search,
      if (locationId != null && locationId > 0) 'location_id': locationId,
    });
  }

  Future<Map<String, dynamic>> getCustomerAccountStatus(int customerId) async {
    return _get('/customers/account-status', query: {
      'customer_id': customerId,
    });
  }

  Future<Map<String, dynamic>> collectCustomerBalance({
    required int customerId,
    required double amount,
    String method = 'CASH',
    String reference = '',
  }) async {
    return _post('/customer-balances/collect', body: {
      'customer_id': customerId,
      'amount': amount,
      'method': method,
      if (reference.isNotEmpty) 'reference': reference,
    });
  }

  Future<Map<String, dynamic>> getCloseShift({
    required int locationId,
    required String from,
    required String to,
    required String businessDate,
  }) async {
    return _get('/close-shift', query: {
      'location_id': locationId,
      'from': from,
      'to': to,
      'business_date': businessDate,
    });
  }

  Future<Map<String, dynamic>> getDayStatus({
    required int locationId,
    String? date,
    bool includeSummary = false,
  }) async {
    return _get('/day/status', query: {
      'location_id': locationId,
      if (date != null && date.isNotEmpty) 'date': date,
      if (includeSummary) 'include_summary': 1,
    });
  }

  Future<Map<String, dynamic>> startShift({
    required int locationId,
    required String businessDate,
    double openingCash = 0,
    double openingCard = 0,
    double openingEcocash = 0,
  }) async {
    return _post('/day/open', body: {
      'location_id': locationId,
      'business_date': businessDate,
      'opening_cash': openingCash,
      'opening_card': openingCard,
      'opening_ecocash': openingEcocash,
    });
  }

  Future<Map<String, dynamic>> closeShift({
    required int locationId,
    required String businessDate,
    double countedCash = 0,
    double countedCard = 0,
    double countedEcocash = 0,
  }) async {
    return _post('/day/close', body: {
      'location_id': locationId,
      'business_date': businessDate,
      'counted_cash': countedCash,
      'counted_card': countedCard,
      'counted_ecocash': countedEcocash,
    });
  }

  Future<List<Map<String, dynamic>>> getShiftCollections({
    required String from,
    required String to,
    int? locationId,
    String groupBy = 'date',
  }) async {
    final data = await _get('/shift-collections', query: {
      'from': from,
      'to': to,
      if (locationId != null && locationId > 0) 'location_id': locationId,
      if (groupBy.isNotEmpty) 'group_by': groupBy,
    });
    return (data['rows'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> createExpense({
    required int locationId,
    required String category,
    required double amount,
    required String expenseDate,
    String note = '',
  }) async {
    final data = await _post('/expenses', body: {
      'location_id': locationId,
      'category': category,
      'amount': amount,
      'expense_date': expenseDate,
      if (note.isNotEmpty) 'note': note,
    });
    return _asInt(data['id']);
  }

  Future<Map<String, dynamic>> getExpenses({
    String? from,
    String? to,
    int? locationId,
    String category = '',
  }) async {
    return _get('/expenses', query: {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (locationId != null && locationId > 0) 'location_id': locationId,
      if (category.isNotEmpty) 'category': category,
    });
  }

  Future<Map<String, dynamic>> getPrepayments() async {
    return _get('/prepayments');
  }

  Future<int> createPrepayment(Map<String, dynamic> payload) async {
    final data = await _post('/prepayments', body: payload);
    return _asInt(data['id']);
  }

  Future<int> releaseGoods({
    required int prepaymentId,
    required double amount,
    String note = '',
  }) async {
    final data = await _post('/prepayments/release', body: {
      'prepayment_id': prepaymentId,
      'amount': amount,
      if (note.isNotEmpty) 'note': note,
    });
    return _asInt(data['id']);
  }

  Future<Map<String, dynamic>> getReleaseGoods({String search = ''}) async {
    return _get('/release-goods', query: {
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
  }

  Future<void> collectReleaseGoods({
    required int saleId,
    String note = '',
  }) async {
    await _post('/release-goods/collect', body: {
      'sale_id': saleId,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final data = await _get('/users');
    return (data['users'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getUserChoices() async {
    final data = await _get('/users/choices');
    return (data['users'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> createUser(Map<String, dynamic> payload) async {
    await _post('/users/create', body: payload);
  }

  Future<void> updateUser(Map<String, dynamic> payload) async {
    await _post('/users/update', body: payload);
  }

  Future<Map<String, dynamic>> getAdminControl() async {
    return _get('/admin/control');
  }

  Future<Map<String, dynamic>> getNotifications({
    bool unreadOnly = false,
    int limit = 80,
  }) async {
    final query = {
      'unread_only': unreadOnly ? 1 : 0,
      'limit': limit,
    };
    try {
      return await _get('/notifications', query: query);
    } catch (error) {
      if (!_isNotFoundError(error)) rethrow;
      return _get('/announcements', query: query);
    }
  }

  Future<void> markNotificationRead(int id) async {
    await _post('/notifications/$id/read', body: const {});
  }

  Future<int> sendAnnouncement({
    required String title,
    required String body,
    int? locationId,
  }) async {
    final payload = {
      'title': title,
      'body': body,
      if (locationId != null && locationId > 0) 'location_id': locationId,
    };
    try {
      final data = await _post('/announcements/send', body: payload);
      return _asInt(data['sent']);
    } catch (error) {
      if (!_isNotFoundError(error)) rethrow;
    }
    try {
      final data = await _post('/announcements', body: payload);
      return _asInt(data['sent']);
    } catch (error) {
      if (!_isNotFoundError(error)) rethrow;
    }
    final data = await _post('/notifications/send', body: payload);
    return _asInt(data['sent']);
  }

  Future<List<Map<String, dynamic>>> getRoleProfiles() async {
    final data = await _get('/admin/roles');
    return (data['roles'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> saveRoleProfile(Map<String, dynamic> payload, {int? id}) async {
    final data = await _post(id == null ? '/admin/roles' : '/admin/roles/$id', body: payload);
    return _asInt(data['id']);
  }

  Future<void> deleteRoleProfile(int id) async {
    await _post('/admin/roles/$id', body: {'_action': 'delete'});
  }

  Future<Map<String, dynamic>> getUserAccess(int id) async {
    return _get('/admin/users/$id/access');
  }

  Future<void> saveUserAccess(int id, Map<String, dynamic> payload) async {
    await _post('/admin/users/$id/access', body: payload);
  }

  Future<void> deleteAdminUser(int id) async {
    await _post('/admin/users/$id/delete', body: const {});
  }

  Future<List<Map<String, dynamic>>> getRegistrationRequests({String status = ''}) async {
    final data = await _get('/admin/registrations', query: {
      if (status.isNotEmpty) 'status': status,
    });
    return (data['registrations'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> approveRegistration(int id, Map<String, dynamic> payload) async {
    final data = await _post('/admin/registrations/$id/approve', body: payload);
    return _asInt(data['user_id']);
  }

  Future<void> rejectRegistration(int id, {String reason = ''}) async {
    await _post('/admin/registrations/$id/reject', body: {
      if (reason.isNotEmpty) 'reason': reason,
    });
  }

  // ── Purchase Orders ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPurchaseOrders({int? supplierId, String? status}) async {
    final data = await _get('/purchase-orders', query: {
      if (supplierId != null) 'supplier_id': supplierId,
      if (status != null) 'status': status,
    });
    return (data['purchase_orders'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<int> createPurchaseOrder(Map<String, dynamic> payload) async {
    final data = await _post('/purchase-orders', body: payload);
    return _asInt(data['id']);
  }

  Future<void> receivePurchaseOrder(int id, List<Map<String, dynamic>> items) async {
    await _post('/purchase-orders/$id/receive', body: {'items': items});
  }

  // ── Laybys ────────────────────────────────────────────────────
  // ── Loyalty ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> getLoyaltyConfig() async {
    return await _get('/loyalty/config');
  }

  Future<void> updateLoyaltyConfig(Map<String, dynamic> payload) async {
    await _post('/loyalty/config', body: payload);
  }

  Future<double> redeemLoyaltyPoints({required int customerId, required int points}) async {
    final data = await _post('/loyalty/redeem', body: {'customer_id': customerId, 'points': points});
    return double.tryParse('${data['dollar_value'] ?? ''}') ?? 0.0;
  }

  // ── Parked carts ──────────────────────────────────────────────
  Future<List<ParkedCart>> getParkedCarts({required int locationId}) async {
    final data = await _get('/carts/parked', query: {'location_id': locationId});
    return (data['carts'] as List<dynamic>)
        .map((e) => ParkedCart.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> parkCart(Map<String, dynamic> payload) async {
    final data = await _post('/carts/park', body: payload);
    return _asInt(data['id']);
  }

  Future<Map<String, dynamic>> retrieveParkedCart(int id) async {
    return await _get('/carts/parked/$id');
  }

  Future<void> deleteParkedCart(int id) async {
    await _post('/carts/parked/$id/delete', body: {});
  }

  // ── POS Favorites ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getFavorites({int? locationId}) async {
    final data = await _get('/pos/favorites', query: {if (locationId != null) 'location_id': locationId});
    return (data['favorites'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> addFavorite({required int productId, int? locationId}) async {
    await _post('/pos/favorites', body: {'product_id': productId, 'location_id': locationId});
  }

  Future<void> removeFavorite({required int productId}) async {
    await _post('/pos/favorites/remove', body: {'product_id': productId});
  }

  // ── Profit margin alerts ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> getMarginAlerts() async {
    final data = await _get('/alerts/margin');
    return (data['items'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
