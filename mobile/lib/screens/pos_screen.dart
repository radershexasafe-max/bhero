import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../models.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';
import '../widgets/mobile_ui.dart';
import 'scanner_screen.dart';

class PosScreen extends StatefulWidget {
  final AppState appState;
  const PosScreen({super.key, required this.appState});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _discountValue = TextEditingController();

  String _paymentMethod = 'CASH';
  String _secondaryMethod = 'CASH';
  String _discountType = 'none';
  int? _locationId;
  bool _loading = false;
  bool _online = true;
  String? _catalogError;
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _featuredBales = [];
  final List<CartItem> _cart = [];
  Customer? _selectedCustomer;
  double _customerAvailablePrepayment = 0;
  double _customerPendingBalance = 0;
  Timer? _searchDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.defaultLocationId;
    _search.addListener(_handleSearchChanged);
    _refreshOnline();
    _loadCatalog();
    unawaited(_syncProductsForOfflineSilently());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
      _refreshOnline();
      _loadCatalog();
      unawaited(_syncProductsForOfflineSilently());
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchDebounce?.cancel();
    _search.removeListener(_handleSearchChanged);
    _search.dispose();
    _amount.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;
  double _toDouble(dynamic value) => double.tryParse('${value ?? ''}') ?? 0.0;

  Future<void> _refreshOnline() async {
    final c = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _online = !c.contains(ConnectivityResult.none));
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFC62828) : null,
        ),
      );
  }

  String _friendlyError(
    Object error, {
    String fallback = 'Could not connect right now. Check your connection and try again.',
  }) {
    return ApiClient.friendlyError(error, fallback: fallback);
  }

  String? _friendlyLoadError(Object error, {String? fallback}) {
    final message = ApiClient.friendlyError(
      error,
      fallback: fallback ?? 'Could not load bale items right now. Refresh to try again.',
    ).trim();
    if (message.isEmpty) return fallback ?? 'Could not load bale items right now. Refresh to try again.';
    return message;
  }

  bool _looksLikeConnectivityIssue(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('connection closed');
  }

  List<CartItem> _snapshotCartItems() {
    return _cart
        .map((item) => CartItem(product: item.product, qty: item.qty))
        .toList();
  }

  String? _buildReceiptAccountNote({
    required double saleTotal,
    required double amountPaid,
    Map<String, dynamic>? accountSummary,
  }) {
    if (_selectedCustomer == null) return null;
    final lines = <String>[];
    final available = _toDouble(
      accountSummary == null
          ? _customerAvailablePrepayment
          : accountSummary['available_prepayment_before'] ?? _customerAvailablePrepayment,
    );
    final appliedFromAccount = _toDouble(
      accountSummary == null
          ? ((saleTotal - amountPaid) > 0 ? (saleTotal - amountPaid).clamp(0, available) : 0.0)
          : accountSummary['prepayment_applied'],
    );
    final availableAfter = _toDouble(
      accountSummary == null
          ? (available - appliedFromAccount)
          : accountSummary['available_prepayment_after'],
    );
    final pending = _toDouble(
      accountSummary == null
          ? _customerPendingBalance
          : accountSummary['pending_balance_before'] ?? _customerPendingBalance,
    );
    final pendingAfter = _toDouble(
      accountSummary == null
          ? (pending + (saleTotal - amountPaid - appliedFromAccount))
          : accountSummary['pending_balance_after'],
    );

    if (available > 0) {
      lines.add('Customer balance before sale: +${available.toStringAsFixed(0)}');
    }

    if (pending > 0) {
      lines.add('Customer balance before sale: -${pending.toStringAsFixed(0)}');
    }

    lines.add('Sale total: ${saleTotal.toStringAsFixed(0)}');
    if (appliedFromAccount > 0) {
      lines.add('Applied from customer balance: ${appliedFromAccount.toStringAsFixed(0)}');
      lines.add('Customer balance after sale: +${availableAfter.toStringAsFixed(0)}');
    } else if (available > 0) {
      lines.add('Customer balance after sale: +${availableAfter.toStringAsFixed(0)}');
    }

    final unpaid = saleTotal - amountPaid - appliedFromAccount;
    if (unpaid > 0.00001) {
      lines.add('Credit added from this sale: ${unpaid.toStringAsFixed(0)}');
    }
    if (pendingAfter > 0) {
      lines.add('Customer balance after sale: -${pendingAfter.toStringAsFixed(0)}');
    }

    return lines.isEmpty ? null : lines.join('\n');
  }

  double get _subtotal => _cart.fold(0.0, (sum, it) => sum + it.lineTotal);

  double get _discount {
    final sub = _subtotal;
    final val = double.tryParse(_discountValue.text.trim()) ?? 0;
    if (_discountType == 'percentage' && val > 0) {
      return (sub * val / 100).clamp(0, sub);
    }
    if (_discountType == 'fixed' && val > 0) {
      return val.clamp(0, sub);
    }
    return 0;
  }

  double get _total => _subtotal - _discount;
  bool get _requiresCustomer => _paymentMethod == 'CREDIT';
  int get _cartQty => _cart.fold<int>(0, (sum, item) => sum + item.qty);

  String get _amountLabel {
    if (_paymentMethod == 'CREDIT') return 'Initial payment (optional)';
    return 'Amount received';
  }

  List<Map<String, dynamic>> _availableBales(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final stock = _toDouble(row['current_stock']) > 0
          ? _toDouble(row['current_stock'])
          : _toDouble(row['on_hand']);
      return _toInt(row['product_id']) > 0 && stock > 0;
    }).toList();
  }

  Map<String, dynamic> _productAsBale(Product product) {
    return {
      'id': product.id,
      'product_id': product.id,
      'product_name': product.name,
      'bale_code': product.barcode,
      'sell_price': product.sellPrice,
      'cost_price': product.costPrice,
      'current_stock': 0,
      'category_name': '',
      'label_name': '',
      'grade': '',
      'unit_of_measure': '',
      'unit_quantity': '',
    };
  }

  Product _productFromBale(Map<String, dynamic> bale) {
    return Product(
      id: _toInt(bale['product_id'] ?? bale['id']),
      name: (bale['product_name'] ?? bale['name'] ?? 'Bale item').toString(),
      barcode: (bale['bale_code'] ?? bale['barcode'])?.toString(),
      sellPrice: _toDouble(bale['sell_price']),
      costPrice: _toDouble(bale['cost_price']),
      reorderLevel: 0,
    );
  }

  double _positiveDouble(dynamic primary, dynamic secondary) {
    final first = _toDouble(primary);
    if (first > 0) return first;
    return _toDouble(secondary);
  }

  Map<String, dynamic> _catalogRowFromProduct(
    Map<String, dynamic> productRow, {
    Map<String, dynamic>? baleSnapshot,
  }) {
    final productId = _toInt(productRow['id'] ?? productRow['product_id']);
    final onHand = _toDouble(productRow['on_hand']);
    final productName = (productRow['name'] ?? productRow['product_name'] ?? 'Bale item')
        .toString()
        .trim();
    final categoryName = (baleSnapshot?['category_name'] ??
            productRow['category_name'] ??
            productRow['category'] ??
            '')
        .toString()
        .trim();
    final labelName =
        (baleSnapshot?['label_name'] ?? productRow['label'] ?? '').toString().trim();
    final totalStockFromSnapshot = _toDouble(baleSnapshot?['total_stock']);

    return {
      'id': _toInt(baleSnapshot?['id'] ?? productId),
      'product_id': productId,
      'product_name': productName.isEmpty ? 'Bale item' : productName,
      'name': productName,
      'bale_code': (baleSnapshot?['bale_code'] ?? productRow['barcode'] ?? '').toString(),
      'barcode': (productRow['barcode'] ?? baleSnapshot?['bale_code'] ?? '').toString(),
      'category_name': categoryName,
      'label_name': labelName,
      'grade': _toInt(baleSnapshot?['grade']),
      'unit_of_measure': (baleSnapshot?['unit_of_measure'] ?? '').toString(),
      'unit_quantity': _positiveDouble(
        baleSnapshot?['unit_quantity'],
        productRow['unit_quantity'],
      ),
      'sell_price': _positiveDouble(
        baleSnapshot?['sell_price'],
        productRow['sell_price'],
      ),
      'cost_price': _positiveDouble(
        baleSnapshot?['cost_price'],
        productRow['cost_price'],
      ),
      'current_stock': onHand,
      'on_hand': onHand,
      'total_stock': totalStockFromSnapshot > 0 ? totalStockFromSnapshot : onHand,
    };
  }

  List<Map<String, dynamic>> _mergeStockedProductsWithBales(
    List<Map<String, dynamic>> productRows,
    List<Map<String, dynamic>> baleRows,
  ) {
    final bestBaleByProduct = <int, Map<String, dynamic>>{};
    for (final row in baleRows) {
      final bale = Map<String, dynamic>.from(row);
      final productId = _toInt(bale['product_id'] ?? bale['id']);
      if (productId <= 0) continue;
      final existing = bestBaleByProduct[productId];
      if (existing == null) {
        bestBaleByProduct[productId] = bale;
        continue;
      }
      final existingStock = _availableStock(existing);
      final nextStock = _availableStock(bale);
      final existingHasPrice = _toDouble(existing['sell_price']) > 0;
      final nextHasPrice = _toDouble(bale['sell_price']) > 0;
      if (nextStock > existingStock || (nextHasPrice && !existingHasPrice)) {
        bestBaleByProduct[productId] = bale;
      }
    }

    final mergedByProduct = <int, Map<String, dynamic>>{};
    for (final row in productRows) {
      final productRow = Map<String, dynamic>.from(row);
      final productId = _toInt(productRow['id'] ?? productRow['product_id']);
      if (productId <= 0) continue;
      final merged = _catalogRowFromProduct(
        productRow,
        baleSnapshot: bestBaleByProduct[productId],
      );
      if (_availableStock(merged) > 0) {
        mergedByProduct[productId] = merged;
      }
    }

    for (final row in baleRows) {
      final bale = Map<String, dynamic>.from(row);
      final productId = _toInt(bale['product_id'] ?? bale['id']);
      if (productId <= 0) continue;
      final existing = mergedByProduct[productId];
      if (existing == null) {
        if (_availableStock(bale) > 0) {
          bale['product_id'] = productId;
          bale['product_name'] =
              (bale['product_name'] ?? bale['name'] ?? 'Bale item').toString();
          bale['total_stock'] = _toDouble(bale['total_stock']) > 0
              ? _toDouble(bale['total_stock'])
              : _availableStock(bale);
          mergedByProduct[productId] = bale;
        }
        continue;
      }

      if ((existing['category_name'] ?? '').toString().trim().isEmpty &&
          (bale['category_name'] ?? '').toString().trim().isNotEmpty) {
        existing['category_name'] = bale['category_name'];
      }
      if ((existing['label_name'] ?? '').toString().trim().isEmpty &&
          (bale['label_name'] ?? '').toString().trim().isNotEmpty) {
        existing['label_name'] = bale['label_name'];
      }
      if (_toDouble(existing['sell_price']) <= 0 && _toDouble(bale['sell_price']) > 0) {
        existing['sell_price'] = bale['sell_price'];
      }
      if (_toDouble(existing['cost_price']) <= 0 && _toDouble(bale['cost_price']) > 0) {
        existing['cost_price'] = bale['cost_price'];
      }
      if (_toDouble(existing['unit_quantity']) <= 0 && _toDouble(bale['unit_quantity']) > 0) {
        existing['unit_quantity'] = bale['unit_quantity'];
      }
      if ((existing['unit_of_measure'] ?? '').toString().trim().isEmpty &&
          (bale['unit_of_measure'] ?? '').toString().trim().isNotEmpty) {
        existing['unit_of_measure'] = bale['unit_of_measure'];
      }
      if (_toDouble(bale['total_stock']) > _toDouble(existing['total_stock'])) {
        existing['total_stock'] = bale['total_stock'];
      }
      if (_toInt(existing['grade']) <= 0 && _toInt(bale['grade']) > 0) {
        existing['grade'] = bale['grade'];
      }
    }

    final merged = mergedByProduct.values.toList();
    merged.sort((a, b) {
      final stockCompare = _availableStock(b).compareTo(_availableStock(a));
      if (stockCompare != 0) return stockCompare;
      return (a['product_name'] ?? '').toString().toLowerCase().compareTo(
            (b['product_name'] ?? '').toString().toLowerCase(),
          );
    });
    return merged;
  }

  String _baleMeta(Map<String, dynamic> bale) {
    final parts = <String>[];
    final category = (bale['category_name'] ?? '').toString().trim();
    final label = (bale['label_name'] ?? '').toString().trim();
    final grade = _toInt(bale['grade']);
    final unitQty = _toDouble(bale['unit_quantity']);
    final unit = (bale['unit_of_measure'] ?? '').toString().trim().toUpperCase();
    final stock = _toDouble(bale['current_stock']);
    if (category.isNotEmpty) parts.add(category);
    if (label.isNotEmpty) parts.add(label);
    if (grade > 0) parts.add('Grade $grade');
    if (unit.isNotEmpty && unitQty > 0) {
      parts.add('${unit == 'PCS' ? unitQty.toInt() : unitQty.toStringAsFixed(0)} $unit');
    }
    if (stock > 0) parts.add('Stock ${stock.toStringAsFixed(0)}');
    return parts.join(' - ');
  }

  String _quickBaleMeta(Map<String, dynamic> bale) {
    final parts = <String>[];
    final category = (bale['category_name'] ?? '').toString().trim();
    final label = (bale['label_name'] ?? '').toString().trim();
    final stock = _toDouble(bale['current_stock']);
    if (category.isNotEmpty) {
      parts.add(category);
    } else if (label.isNotEmpty) {
      parts.add(label);
    }
    if (stock > 0) {
      parts.add('${stock.toStringAsFixed(0)} in stock');
    }
    return parts.join(' • ');
  }

  String _quickBaleMetaCompact(Map<String, dynamic> bale) {
    final parts = <String>[];
    final category = (bale['category_name'] ?? '').toString().trim();
    final label = (bale['label_name'] ?? '').toString().trim();
    final stock = _toDouble(bale['current_stock']);
    if (category.isNotEmpty) {
      parts.add(category);
    } else if (label.isNotEmpty) {
      parts.add(label);
    }
    if (stock > 0) {
      parts.add('${stock.toStringAsFixed(0)} in stock');
    }
    return parts.join(' - ');
  }

  String _formatUnitSummary(Map<String, dynamic> bale) {
    final qty = _toDouble(bale['unit_quantity']);
    final unit = (bale['unit_of_measure'] ?? '').toString().trim().toLowerCase();
    if (qty <= 0 || unit.isEmpty) return '-';
    final displayQty = unit == 'pcs' ? qty.toInt().toString() : qty.toStringAsFixed(0);
    return '$displayQty $unit';
  }

  double _availableStock(Map<String, dynamic> bale) {
    final stock = _toDouble(bale['current_stock']);
    if (stock > 0) return stock;
    return _toDouble(bale['on_hand']);
  }

  double _totalStock(Map<String, dynamic> bale) {
    final stock = _toDouble(bale['total_stock']);
    if (stock > 0) return stock;
    return _availableStock(bale);
  }

  Future<void> _openQuickQtyDialog(Map<String, dynamic> bale) async {
    final qtyCtrl = TextEditingController(text: '1');
    try {
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Add ${(bale['product_name'] ?? 'Bale').toString()}'),
          content: TextField(
            controller: qtyCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _toInt(qtyCtrl.text)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (picked == null || picked <= 0) return;
      _addToCartFromBale(bale, qty: picked);
    } finally {
      qtyCtrl.dispose();
    }
  }

  Future<void> _openSaleDiscountDialog() async {
    var type = _discountType;
    final valueCtrl = TextEditingController(
      text: _discountType == 'none' ? '' : _discountValue.text.trim(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Sale Discount'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Discount type'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('No discount')),
                    DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
                  ],
                  onChanged: (value) => setDialogState(() => type = value ?? 'none'),
                ),
                if (type != 'none') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: type == 'percentage' ? 'Discount %' : 'Discount amount',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _discountType = type;
        _discountValue.text = type == 'none' ? '' : valueCtrl.text.trim();
      });
    }
    valueCtrl.dispose();
  }

  Widget _buildCartBadgeAction() {
    return IconButton(
      onPressed: _cart.isEmpty ? null : _openCheckoutPage,
      tooltip: _cart.isEmpty ? 'Cart is empty' : 'Checkout',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 28),
          if (_cartQty > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$_cartQty',
                  style: const TextStyle(
                    color: Color(0xFFE31B23),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addToCartFromBale(Map<String, dynamic> bale, {int qty = 1}) {
    final nextQty = qty <= 0 ? 1 : qty;
    final product = _productFromBale(bale);
    final existing = _cart.where((item) => item.product.id == product.id).toList();
    if (existing.isNotEmpty) {
      setState(() {
        existing.first.qty += nextQty;
      });
    } else {
      setState(() {
        _cart.add(CartItem(product: product, qty: nextQty));
      });
    }
  }

  void _updateCartQty(CartItem item, int nextQty) {
    setState(() {
      if (nextQty <= 0) {
        _cart.removeWhere((row) => row.product.id == item.product.id);
      } else {
        item.qty = nextQty;
      }
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _amount.clear();
      _discountValue.clear();
      _discountType = 'none';
      _paymentMethod = 'CASH';
      _secondaryMethod = 'CASH';
      _selectedCustomer = null;
      _customerAvailablePrepayment = 0;
      _customerPendingBalance = 0;
    });
  }

  String _locationLabel(int? id) {
    for (final location in widget.appState.accessibleLocations) {
      if (location.id == id) {
        return '${location.name} (${location.type})';
      }
    }
    return 'No store selected';
  }

  Future<bool> _confirmCheckout({
    required double enteredAmount,
    required double prepaymentApplied,
    required double creditAdded,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Sale'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items: ${_cart.length}'),
              const SizedBox(height: 6),
              Text('Customer: ${_selectedCustomer?.name ?? 'Walk-in customer'}'),
              const SizedBox(height: 6),
              Text('Payment: $_paymentMethod'),
              const SizedBox(height: 6),
              Text('Total: ${_total.toStringAsFixed(0)}'),
              if (enteredAmount > 0) ...[
                const SizedBox(height: 6),
                Text('Amount received: ${enteredAmount.toStringAsFixed(0)}'),
              ],
              if (_customerAvailablePrepayment > 0) ...[
                const SizedBox(height: 6),
                Text('Customer balance available: ${_customerAvailablePrepayment.toStringAsFixed(0)}'),
              ],
              if (prepaymentApplied > 0) ...[
                const SizedBox(height: 6),
                Text('Applied from customer balance: ${prepaymentApplied.toStringAsFixed(0)}'),
              ],
              if (_customerPendingBalance > 0) ...[
                const SizedBox(height: 6),
                Text('Existing customer debt: ${_customerPendingBalance.toStringAsFixed(0)}'),
              ],
              if (creditAdded > 0) ...[
                const SizedBox(height: 6),
                Text('Credit to add after sale: ${creditAdded.toStringAsFixed(0)}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      _loadCatalog(search: _search.text.trim(), quiet: true);
    });
  }

  Future<void> _loadCachedCatalog(String term) async {
    final cached = term.isEmpty
        ? await LocalDb.instance.getCachedProducts(limit: 40)
        : await LocalDb.instance.searchCachedProducts(term);
    if (!mounted) return;
    setState(() {
      final mapped = cached.map(_productAsBale).toList();
      _featuredBales = term.isEmpty ? mapped.take(40).toList() : const [];
      _results = term.isEmpty ? const [] : mapped;
      _catalogError = null;
    });
  }

  Future<void> _syncProductsForOfflineSilently() async {
    if (!_online) return;
    try {
      final all = await api.getProducts(all: false, limit: 1200);
      await LocalDb.instance.cacheProducts(all);
    } catch (_) {
      // Keep offline sync silent. Sales should continue even if refresh fails.
    }
  }

  Future<void> _loadCatalog({String? search, bool quiet = false}) async {
    final term = (search ?? _search.text).trim();
    if (!quiet) {
      setState(() {
        _loading = true;
        _catalogError = null;
      });
    }
    try {
      if (_online) {
        final baleRows = await api.getBales(
          search: term,
          locationId: _locationId,
          limit: term.isEmpty ? 400 : 200,
        );
        final productRows = await api.getProductRows(
          search: term.isEmpty ? null : term,
          locationId: _locationId,
          inStockOnly: true,
          limit: term.isEmpty ? 400 : 200,
        );
        final mergedRows = _mergeStockedProductsWithBales(productRows, baleRows);
        if (!mounted) return;
        setState(() {
          if (term.isEmpty) {
            _featuredBales = mergedRows.take(40).toList();
          }
          _results = term.isEmpty ? const [] : mergedRows;
          _catalogError = null;
        });
      } else {
        await _loadCachedCatalog(term);
      }
    } catch (e) {
      if (_looksLikeConnectivityIssue(e)) {
        await _loadCachedCatalog(term);
        if (!mounted) return;
        setState(() {
          _catalogError = _friendlyLoadError(
            e,
            fallback: 'You are offline right now. Refresh when the network is back.',
          );
        });
      } else {
        if (!mounted) return;
        setState(() {
          _catalogError = _friendlyLoadError(
            e,
            fallback: 'Could not load bale items right now. Refresh to try again.',
          );
        });
      }
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (code == null) return;
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? bale;
      if (_online) {
        final baleRows = await api.getBales(
          search: code,
          locationId: _locationId,
          limit: 40,
        );
        final productRows = await api.getProductRows(
          barcode: code,
          locationId: _locationId,
          inStockOnly: true,
          limit: 20,
        );
        final merged = _mergeStockedProductsWithBales(productRows, baleRows);
        if (merged.isNotEmpty) {
          bale = merged.first;
        }
      } else {
        final product = await LocalDb.instance.getCachedByBarcode(code);
        if (product != null) bale = _productAsBale(product);
      }
      if (bale == null) {
        _showMessage('No bale item was found for barcode: $code', error: true);
      } else {
        _addToCartFromBale(bale);
      }
    } catch (e) {
      _showMessage(
        _friendlyError(e, fallback: 'Could not scan and load that bale right now.'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncProductsForOffline() async {
    if (!_online) {
      _showMessage('Go online to sync products.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final all = await api.getProducts(all: true);
      await LocalDb.instance.cacheProducts(all);
      _showMessage('Cached ${all.length} products for offline.');
    } catch (e) {
      _showMessage(
        _friendlyError(e, fallback: 'Could not refresh offline products right now.'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesSearch(Map<String, dynamic> bale, String term) {
    final q = term.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      bale['product_name'],
      bale['category_name'],
      bale['label_name'],
      bale['bale_code'],
      bale['barcode'],
      bale['grade'],
      bale['unit_of_measure'],
      bale['unit_quantity'],
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  Future<void> _syncQueue() async {
    if (!_online) {
      _showMessage('Offline. Cannot sync now.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await SyncService.syncQueuedSales(api);
      _showMessage('Synced ${res.synced}, remaining ${res.remaining}');
    } catch (e) {
      _showMessage(
        _friendlyError(e, fallback: 'Could not sync queued sales right now.'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomer() async {
    final searchCtrl = TextEditingController(text: _selectedCustomer?.name ?? '');
    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) {
        var initialized = false;
        var loading = false;
        List<Customer> customers = [];

        Future<void> loadCustomers(StateSetter setModalState, String q) async {
          setModalState(() => loading = true);
          try {
            customers = await api.getCustomers(search: q);
          } catch (_) {
            customers = [];
          } finally {
            if (ctx.mounted) setModalState(() => loading = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized) {
              initialized = true;
              unawaited(loadCustomers(setModalState, searchCtrl.text.trim()));
            }
            return AlertDialog(
              scrollable: true,
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Search customer',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => loadCustomers(setModalState, value.trim()),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const LinearProgressIndicator()
                    else if (customers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No matching customers found.'),
                      )
                    else
                      ...customers.take(20).map(
                        (customer) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(customer.name),
                          subtitle: Text(
                            [customer.phone ?? '', customer.email ?? '']
                                .where((value) => value.isNotEmpty)
                                .join(' - '),
                          ),
                          onTap: () => Navigator.pop(ctx, customer),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                if (_selectedCustomer != null)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, Customer(id: -1, name: '')),
                    child: const Text('Clear'),
                  ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedCustomer = picked.id < 0 ? null : picked);
  }

  Future<void> _openCheckoutPage() async {
    if (_cart.isEmpty) {
      _showMessage('Cart is empty.', error: true);
      return;
    }
    final result = await Navigator.of(context).push<_SaleCheckoutResult>(
      MaterialPageRoute(
        builder: (_) => _SaleCheckoutScreen(
          appState: widget.appState,
          initialCustomer: _selectedCustomer,
          initialPaymentMethod: _paymentMethod,
          initialSecondaryMethod: _secondaryMethod,
          initialAmount: _amount.text.trim(),
          total: _total,
          requiresCustomer: _requiresCustomer,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _paymentMethod = result.paymentMethod;
      _secondaryMethod = result.secondaryMethod;
      _amount.text = result.amountText;
      _selectedCustomer = result.customer;
      _customerAvailablePrepayment = result.availablePrepayment;
      _customerPendingBalance = result.pendingBalance;
    });
    await _checkout(collectLater: result.collectLater);
  }

  Future<void> _checkout({bool collectLater = false}) async {
    if (_cart.isEmpty) {
      _showMessage('Cart is empty.', error: true);
      return;
    }
    final locId = _locationId;
    if (locId == null || locId <= 0) {
      _showMessage('No location selected.', error: true);
      return;
    }
    if (_requiresCustomer && _selectedCustomer == null) {
      _showMessage('Choose a customer for this credit sale.', error: true);
      return;
    }
    final amount = double.tryParse(_amount.text.trim()) ?? 0.0;
    final availablePrepayment = _selectedCustomer == null ? 0.0 : _customerAvailablePrepayment;
    final prepaymentApplied = _selectedCustomer == null
        ? 0.0
        : ((_total - amount) > 0
            ? ((_total - amount).clamp(0, availablePrepayment) as num).toDouble()
            : 0.0);
    final creditToAdd = (_total - amount - prepaymentApplied) > 0
        ? (_total - amount - prepaymentApplied)
        : 0.0;
    if (creditToAdd > 0 && _selectedCustomer == null) {
      _showMessage(
        'Select a customer so the remaining balance can be saved as credit automatically.',
        error: true,
      );
      return;
    }
    if (!await _confirmCheckout(
      enteredAmount: amount,
      prepaymentApplied: prepaymentApplied,
      creditAdded: creditToAdd,
    )) {
      return;
    }

    final receiptItems = _snapshotCartItems();
    final receiptCustomerName = _selectedCustomer?.name;
    final receiptCustomerPhone = _selectedCustomer?.phone;
    final receiptCustomerEmail = _selectedCustomer?.email;
    final receiptCustomerAddress = _selectedCustomer?.address;
    final receiptPaymentMethod = _paymentMethod == 'CREDIT' ? _secondaryMethod : _paymentMethod;
    final receiptDiscount = _discount;
    final receiptTotal = _total;
    var receiptAccountNotePreview = _buildReceiptAccountNote(
      saleTotal: receiptTotal,
      amountPaid: amount,
    );
    if (collectLater) {
      final pieces = <String>[
        if ((receiptAccountNotePreview ?? '').trim().isNotEmpty) receiptAccountNotePreview!,
        'Collection status: Collect later',
      ];
      receiptAccountNotePreview = pieces.join('\n');
    }
    final clientId = const Uuid().v4();
    final saleMode = (_paymentMethod == 'CREDIT' || creditToAdd > 0) ? 'CREDIT' : 'CASH';
    final payments = <Map<String, dynamic>>[];
    if (amount > 0) {
      payments.add({
        'method': _paymentMethod == 'CREDIT' ? _secondaryMethod : _paymentMethod,
        'amount': amount,
      });
    }

    final payload = {
      'location_id': locId,
      'client_sale_id': clientId,
      'sale_mode': saleMode,
      if (_selectedCustomer != null) 'customer_id': _selectedCustomer!.id,
      'items': _cart.map((item) => {'product_id': item.product.id, 'qty': item.qty}).toList(),
      'payments': payments,
      if (_discountType != 'none') 'discount_type': _discountType,
      if (_discountType != 'none') 'discount_value': double.tryParse(_discountValue.text.trim()) ?? 0,
    };

    setState(() => _loading = true);
    try {
      Map<String, dynamic>? data;
      if (_online) {
        try {
          data = await api.createSale(payload);
        } catch (e) {
          if (!_looksLikeConnectivityIssue(e)) {
            _showMessage(
              _friendlyError(e, fallback: 'Sale could not be completed right now.'),
              error: true,
            );
            return;
          }
        }
      }

      if (data == null) {
        await LocalDb.instance.enqueueSale(clientId, payload);
        final pdfPath = await _printOfflineReceipt(
          clientId,
          items: receiptItems,
          total: receiptTotal,
          customerName: receiptCustomerName,
          customerPhone: receiptCustomerPhone,
          customerEmail: receiptCustomerEmail,
          customerAddress: receiptCustomerAddress,
          paymentMethod: receiptPaymentMethod,
          amountPaid: amount,
          discount: receiptDiscount,
          note: receiptAccountNotePreview,
        );
        _clearCart();
        _showMessage('Sale queued offline.');
        if (pdfPath.isNotEmpty) {
          await _showReceiptActions(
            saleNumber: clientId,
            pdfPath: pdfPath,
            items: receiptItems,
            total: receiptTotal,
            customerName: receiptCustomerName,
            customerPhone: receiptCustomerPhone,
            customerEmail: receiptCustomerEmail,
            customerAddress: receiptCustomerAddress,
            paymentMethod: receiptPaymentMethod,
            amountPaid: amount,
            discount: receiptDiscount,
            note: receiptAccountNotePreview,
            queued: true,
          );
        }
        return;
      }

      final saleNo = ((data['sale'] as Map?)?['sale_number'] ?? '').toString();
      final resolvedSaleMode = (((data['sale'] as Map?)?['sale_mode'] ?? saleMode).toString()).toUpperCase();
      final accountSummary = Map<String, dynamic>.from((data['account_summary'] as Map?) ?? const {});
      var resolvedReceiptAccountNote = _buildReceiptAccountNote(
        saleTotal: receiptTotal,
        amountPaid: amount,
        accountSummary: accountSummary,
      );
      if (collectLater) {
        final pieces = <String>[
          if ((resolvedReceiptAccountNote ?? '').trim().isNotEmpty) resolvedReceiptAccountNote!,
          'Collection status: Collect later',
        ];
        resolvedReceiptAccountNote = pieces.join('\n');
      }
      var pdfPath = '';
      try {
        pdfPath = await _printReceipt(
          saleNo,
          items: receiptItems,
          total: receiptTotal,
          customerName: receiptCustomerName,
          customerPhone: receiptCustomerPhone,
          customerEmail: receiptCustomerEmail,
          customerAddress: receiptCustomerAddress,
          paymentMethod: resolvedSaleMode == 'CREDIT' ? 'CREDIT' : receiptPaymentMethod,
          amountPaid: amount,
          discount: receiptDiscount,
          note: resolvedReceiptAccountNote,
        );
      } catch (e) {
        _showMessage(
          _friendlyError(
            e,
            fallback: 'Sale was saved, but the receipt export could not finish right now.',
          ),
          error: true,
        );
      }
      _clearCart();
      _showMessage('Sale done: $saleNo');
      if (pdfPath.isNotEmpty) {
        await _showReceiptActions(
          saleNumber: saleNo,
          pdfPath: pdfPath,
          items: receiptItems,
          total: receiptTotal,
          customerName: receiptCustomerName,
          customerPhone: receiptCustomerPhone,
          customerEmail: receiptCustomerEmail,
            customerAddress: receiptCustomerAddress,
            paymentMethod: resolvedSaleMode == 'CREDIT' ? 'CREDIT' : receiptPaymentMethod,
            amountPaid: amount,
            discount: receiptDiscount,
            note: resolvedReceiptAccountNote,
          );
      }
    } catch (e) {
      _showMessage(
        _friendlyError(
          e,
          fallback: 'Could not complete the sale right now. The app will keep working offline when possible.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _printReceipt(
    String saleNumber, {
    required List<CartItem> items,
    required double total,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
    String? note,
  }) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return '';
    final printer = PrinterService();
    final pdfPath = await printer.saveReceiptPdf(
      tenant: tenant,
      title: paymentMethod == 'CREDIT' ? 'CREDIT SALE RECEIPT' : 'SALE RECEIPT',
      saleNumber: saleNumber,
      items: items,
      total: total,
      cashierName: widget.appState.user?.name,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      discount: discount,
      note: note,
    );
    return pdfPath;
  }

  Future<String> _printOfflineReceipt(
    String clientId, {
    required List<CartItem> items,
    required double total,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
    String? note,
  }) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return '';
    final printer = PrinterService();
    return printer.saveReceiptPdf(
      tenant: tenant,
      title: 'OFFLINE QUEUED',
      saleNumber: clientId,
      items: items,
      total: total,
      cashierName: widget.appState.user?.name,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      discount: discount,
      note: note,
    );
  }

  Future<void> _shareReceiptPdf(String pdfPath, String saleNumber) async {
    await Share.shareXFiles(
      [XFile(pdfPath)],
      text: 'Receipt $saleNumber from T.One Bales',
    );
  }

  Future<void> _printSavedReceipt({
    required String saleNumber,
    required List<CartItem> items,
    required double total,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
    String? note,
    bool queued = false,
  }) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) throw Exception('tenant_not_loaded');

    final printer = PrinterService();
    final savedMac = await printer.getSavedPrinterMac();
    if (savedMac == null || savedMac.trim().isEmpty) {
      throw Exception('No receipt printer is configured in Settings.');
    }
    if (!(await printer.isConnected())) {
      final connected = await printer.connect(savedMac);
      if (!connected) {
        throw Exception('Could not connect to the saved printer.');
      }
    }

    await printer.printReceipt(
      tenant: tenant,
      title: queued ? 'OFFLINE QUEUED' : (paymentMethod == 'CREDIT' ? 'CREDIT SALE RECEIPT' : 'SALE RECEIPT'),
      saleNumber: saleNumber,
      items: items,
      total: total,
      cashierName: widget.appState.user?.name,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      discount: discount,
      note: [
        if (note != null && note.trim().isNotEmpty) note.trim(),
        if (queued) 'Queued until the server is reachable.',
      ].where((line) => line.isNotEmpty).join('\n\n'),
    );
  }

  Future<void> _showReceiptActions({
    required String saleNumber,
    required String pdfPath,
    required List<CartItem> items,
    required double total,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
    String? note,
    bool queued = false,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                queued ? 'Queued Receipt Ready' : 'Receipt Ready',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                queued
                    ? 'The sale was saved offline. You can still share the PDF receipt or print it now.'
                    : 'You can share the receipt PDF or print it using the configured Bluetooth printer.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await _shareReceiptPdf(pdfPath, saleNumber);
                    } catch (e) {
                      _showMessage(
                        _friendlyError(e, fallback: 'Could not share the receipt PDF right now.'),
                        error: true,
                      );
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Share Receipt PDF'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await _printSavedReceipt(
                        saleNumber: saleNumber,
                        items: items,
                        total: total,
                        customerName: customerName,
                        customerPhone: customerPhone,
                        customerEmail: customerEmail,
                        customerAddress: customerAddress,
                        paymentMethod: paymentMethod,
                        amountPaid: amountPaid,
                        discount: discount,
                        note: note,
                        queued: queued,
                      );
                      _showMessage('Receipt sent to printer');
                    } catch (e) {
                      _showMessage(
                        _friendlyError(e, fallback: 'Could not print the receipt right now.'),
                        error: true,
                      );
                    }
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Print Receipt'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _baleShortcutCard(Map<String, dynamic> bale) {
    return SizedBox(
      width: 326,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _addToCartFromBale(bale),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFD),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE9E1DA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (bale['product_name'] ?? 'Bale').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: const Color(0xFFEEE7E1)),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _saleStat(
                      'Avail Stock',
                      _availableStock(bale).toStringAsFixed(0),
                      valueColor: const Color(0xFF1B9E4B),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _saleStat(
                      'Total Stock',
                      _totalStock(bale).toStringAsFixed(0),
                      valueColor: const Color(0xFFC62828),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _saleStat(
                      'Price',
                      '\$${_toDouble(bale['sell_price']).toStringAsFixed(2)}',
                      valueColor: const Color(0xFF14213D),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _saleStat(
                      'Weight',
                      _formatUnitSummary(bale),
                      valueColor: Colors.black,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openQuickQtyDialog(bale),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE31B23),
                        side: const BorderSide(color: Color(0xFFE31B23), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Qty',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openSaleDiscountDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE31B23),
                        side: const BorderSide(color: Color(0xFFE31B23), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Discount',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    height: 58,
                    child: FilledButton(
                      onPressed: () => _addToCartFromBale(bale),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF169536),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Icon(Icons.add_rounded, size: 30),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saleStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _resultCard(Map<String, dynamic> bale) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (bale['product_name'] ?? 'Bale').toString(),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _baleMeta(bale),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _toDouble(bale['sell_price']).toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE31B23),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _addToCartFromBale(bale),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Add To Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartRow(CartItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qty: ${item.qty} @ \$${item.product.sellPrice.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '\$${item.lineTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _updateCartQty(item, 0),
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE31B23)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  onPressed: () => _updateCartQty(item, item.qty - 1),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                IconButton(
                  onPressed: () => _updateCartQty(item, item.qty + 1),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F3F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Line total \$${item.lineTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchActive = _search.text.trim().isNotEmpty;
    final visibleFeaturedBales = _featuredBales
        .where((bale) => _matchesSearch(bale, _search.text))
        .toList();
    final visibleMenuBales = searchActive ? _results : visibleFeaturedBales;

    return MobilePageScaffold(
      title: 'Make a Sale',
      subtitle: 'Add bales to cart to process a sale',
      actions: [
        _buildCartBadgeAction(),
      ],
      child: RefreshIndicator(
        onRefresh: _loadCatalog,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: MobileSearchField(
                        controller: _search,
                        hintText: 'Search bale details',
                        onChanged: (_) {},
                        onSubmitted: (_) => _loadCatalog(),
                        showActionButton: false,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 60,
                  width: 60,
                  child: FilledButton(
                    onPressed: _loading ? null : _scan,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE31B23),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading && visibleMenuBales.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_catalogError != null && visibleMenuBales.isEmpty)
              MobileRetryState(
                icon: Icons.cloud_off_rounded,
                title: 'Bale Items Are Offline',
                message: _catalogError!,
                onRetry: _loadCatalog,
              )
            else
              SizedBox(
                height: 330,
                child: visibleMenuBales.isEmpty
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              searchActive
                                  ? 'No bale items match what you typed yet.'
                                  : 'No bale shortcuts are available yet.',
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleMenuBales.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, index) => _baleShortcutCard(visibleMenuBales[index]),
                      ),
              ),
            if (_catalogError != null && visibleMenuBales.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : _loadCatalog,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry refresh'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.shopping_cart_checkout_rounded,
              title: 'Current Sale',
              trailing: IconButton(
                onPressed: _cart.isEmpty ? null : _clearCart,
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE31B23)),
                tooltip: 'Clear cart',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_cart.isEmpty)
                    const Text('The cart is empty. Add bale items from the menu above.')
                  else
                    ..._cart.map(_cartRow),
                  const SizedBox(height: 8),
                  if (_discount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          MobileMetricChip('Discount \$${_discount.toStringAsFixed(2)}'),
                          TextButton.icon(
                            onPressed: _openSaleDiscountDialog,
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('Edit discount'),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Qty: $_cartQty',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Total Price: \$${_total.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  if (_cart.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _openCheckoutPage,
                        icon: const Icon(Icons.payments_rounded),
                        label: const Text('Complete Sale'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE31B23),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SaleCheckoutResult {
  final String paymentMethod;
  final String secondaryMethod;
  final String amountText;
  final Customer? customer;
  final double availablePrepayment;
  final double pendingBalance;
  final bool collectLater;

  const _SaleCheckoutResult({
    required this.paymentMethod,
    required this.secondaryMethod,
    required this.amountText,
    required this.customer,
    required this.availablePrepayment,
    required this.pendingBalance,
    required this.collectLater,
  });
}

class _SaleCheckoutScreen extends StatefulWidget {
  final AppState appState;
  final Customer? initialCustomer;
  final String initialPaymentMethod;
  final String initialSecondaryMethod;
  final String initialAmount;
  final double total;
  final bool requiresCustomer;

  const _SaleCheckoutScreen({
    required this.appState,
    required this.initialCustomer,
    required this.initialPaymentMethod,
    required this.initialSecondaryMethod,
    required this.initialAmount,
    required this.total,
    required this.requiresCustomer,
  });

  @override
  State<_SaleCheckoutScreen> createState() => _SaleCheckoutScreenState();
}

class _SaleCheckoutScreenState extends State<_SaleCheckoutScreen> {
  late String _paymentMethod;
  late String _secondaryMethod;
  late TextEditingController _amountCtrl;
  Customer? _selectedCustomer;
  double _availablePrepayment = 0;
  double _pendingBalance = 0;
  bool _loadingCustomerStatus = false;
  bool _collectLater = false;

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _paymentMethod = widget.initialPaymentMethod == 'CREDIT'
        ? widget.initialSecondaryMethod
        : widget.initialPaymentMethod;
    _secondaryMethod = widget.initialSecondaryMethod;
    _amountCtrl = TextEditingController(text: widget.initialAmount);
    _selectedCustomer = widget.initialCustomer;
    if (_selectedCustomer != null) {
      unawaited(_loadCustomerStatus(_selectedCustomer!));
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? ''}') ?? 0.0;

  bool get _requiresCustomer => _paymentMethod == 'CREDIT';

  String get _amountLabel {
    return 'Amount Tendered';
  }

  bool get _willCreateCreditBalance {
    if (_paymentMethod == 'CREDIT') return true;
    final amount = _enteredAmount;
    return (widget.total - amount - _availablePrepayment) > 0.00001;
  }

  double get _enteredAmount {
    final typed = double.tryParse(_amountCtrl.text.trim());
    if (typed != null) return typed;
    return 0.0;
  }

  double get _creditAddedPreview {
    final unpaid = widget.total - _enteredAmount - _availablePrepayment;
    return unpaid > 0 ? unpaid : 0.0;
  }

  double get _prepaymentRemainingPreview {
    final remaining = _availablePrepayment -
        ((widget.total - _enteredAmount) > 0 ? (widget.total - _enteredAmount) : 0.0);
    return remaining > 0 ? remaining : 0.0;
  }

  double get _prepaymentAppliedPreview {
    final needed = widget.total - _enteredAmount;
    if (needed <= 0) return 0.0;
    return needed.clamp(0, _availablePrepayment);
  }

  double get _pendingAfterSalePreview => _pendingBalance + _creditAddedPreview;

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFC62828) : null,
        ),
      );
  }

  Future<void> _loadCustomerStatus(Customer customer) async {
    setState(() => _loadingCustomerStatus = true);
    try {
      final data = await _api.getCustomerAccountStatus(customer.id);
      final account = Map<String, dynamic>.from((data['account'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _availablePrepayment = _toDouble(account['available_prepayment']);
        _pendingBalance = _toDouble(account['pending_balance']);
      });
    } catch (_) {
      try {
        final responses = await Future.wait([
          _api.getCustomerBalances(
            search: customer.name,
            locationId: widget.appState.defaultLocationId,
          ),
          _api.getPrepayments(),
        ]);
        final balances = Map<String, dynamic>.from(responses[0] as Map);
        final prepayments = Map<String, dynamic>.from(responses[1] as Map);
        final rows = ((balances['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        Map<String, dynamic>? balanceRow;
        for (final row in rows) {
          if ((row['customer_id']?.toString() ?? '') == customer.id.toString()) {
            balanceRow = row;
            break;
          }
        }
        final prepaymentRows = (((prepayments['prepayments'] as List?) ?? const []))
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => (row['customer_id']?.toString() ?? '') == customer.id.toString())
            .toList();
        final availablePrepayment = prepaymentRows.fold<double>(
          0,
          (sum, row) => sum + (double.tryParse('${row['available_balance'] ?? row['amount'] ?? 0}') ?? 0),
        );
        final pendingBalance = balanceRow == null
            ? 0.0
            : (double.tryParse('${balanceRow['balance_due'] ?? 0}') ?? 0.0);
        if (!mounted) return;
        setState(() {
          _availablePrepayment = availablePrepayment;
          _pendingBalance = pendingBalance;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _availablePrepayment = 0;
          _pendingBalance = 0;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCustomerStatus = false);
      }
    }
  }

  Future<void> _pickCustomer() async {
    final searchCtrl = TextEditingController(text: _selectedCustomer?.name ?? '');
    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) {
        var initialized = false;
        var loading = false;
        List<Customer> customers = [];

        Future<void> loadCustomers(StateSetter setModalState, String q) async {
          setModalState(() => loading = true);
          try {
            customers = await _api.getCustomers(search: q);
          } catch (_) {
            customers = [];
          } finally {
            if (ctx.mounted) {
              setModalState(() => loading = false);
            }
          }
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized) {
              initialized = true;
              unawaited(loadCustomers(setModalState, searchCtrl.text.trim()));
            }
            return AlertDialog(
              scrollable: true,
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MobileSearchField(
                      controller: searchCtrl,
                      hintText: 'Search customer',
                      onChanged: (value) => loadCustomers(setModalState, value.trim()),
                      onSubmitted: (_) => loadCustomers(setModalState, searchCtrl.text.trim()),
                      showActionButton: false,
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const LinearProgressIndicator()
                    else if (customers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No matching customers found.'),
                      )
                    else
                      ...customers.take(20).map(
                        (customer) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(customer.name),
                          subtitle: Text(
                            [customer.phone ?? '', customer.email ?? '']
                                .where((value) => value.isNotEmpty)
                                .join(' - '),
                          ),
                          onTap: () => Navigator.pop(ctx, customer),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedCustomer = picked);
    await _loadCustomerStatus(picked);
  }

  Future<Contact?> _pickPhonebookContact(List<Contact> contacts) async {
    final searchCtrl = TextEditingController();
    final sorted = [...contacts]
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    try {
      return await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          var filtered = sorted;
          return StatefulBuilder(
            builder: (ctx, setSheetState) => FractionallySizedBox(
              heightFactor: 0.88,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pick From Phonebook',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      MobileSearchField(
                        controller: searchCtrl,
                        hintText: 'Search phonebook contact',
                        onChanged: (value) {
                          final q = value.trim().toLowerCase();
                          setSheetState(() {
                            filtered = q.isEmpty
                                ? sorted
                                : sorted.where((contact) {
                                    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                                    final email = contact.emails.isNotEmpty ? contact.emails.first.address : '';
                                    final hay = '${contact.displayName} $phone $email'.toLowerCase();
                                    return hay.contains(q);
                                  }).toList();
                          });
                        },
                        showActionButton: false,
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: filtered.isEmpty
                            ? const MobileEmptyState(
                                icon: Icons.contacts_rounded,
                                title: 'No contacts found',
                                message: 'Try a different name, phone number, or email.',
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, index) {
                                  final contact = filtered[index];
                                  final phone = contact.phones.isNotEmpty ? contact.phones.first.number.trim() : '';
                                  final email = contact.emails.isNotEmpty ? contact.emails.first.address.trim() : '';
                                  return MobileActionTile(
                                    icon: Icons.person_add_alt_1_rounded,
                                    title: contact.displayName.trim().isEmpty
                                        ? 'Unnamed Contact'
                                        : contact.displayName.trim(),
                                    subtitle: [phone, email]
                                        .where((value) => value.isNotEmpty)
                                        .join(' - '),
                                    onTap: () => Navigator.pop(ctx, contact),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  Future<void> _pickCustomerFromPhonebook() async {
    try {
      var granted = await FlutterContacts.requestPermission(readonly: true);
      var status = await Permission.contacts.status;
      if (!granted && !status.isGranted) {
        status = await Permission.contacts.request();
        granted = status.isGranted;
        if (!granted) {
          granted = await FlutterContacts.requestPermission(readonly: true);
        }
      }
      if (!granted) {
        _showMessage(
          'Phonebook permission was not granted. Allow Contacts access, then try again.',
          error: true,
        );
        if (status.isPermanentlyDenied || status.isRestricted) {
          await openAppSettings();
        }
        return;
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      if (contacts.isEmpty) {
        _showMessage('No phonebook contacts were found on this device.', error: true);
        return;
      }

      final selected = await _pickPhonebookContact(contacts);
      if (selected == null) return;

      final name = selected.displayName.trim();
      final phone = selected.phones.isNotEmpty ? selected.phones.first.number.trim() : '';
      final email = selected.emails.isNotEmpty ? selected.emails.first.address.trim() : '';
      final address = selected.addresses.isNotEmpty
          ? [
              selected.addresses.first.address,
              selected.addresses.first.city,
              selected.addresses.first.state,
              selected.addresses.first.country,
            ].where((part) => part.trim().isNotEmpty).join(', ')
          : '';

      if (name.isEmpty) {
        _showMessage('The selected contact does not have a usable name.', error: true);
        return;
      }

      final searchTerms = <String>[
        if (phone.isNotEmpty) phone,
        name,
      ];
      for (final term in searchTerms) {
        final matches = await _api.searchCustomers(term);
        if (matches.isNotEmpty) {
          setState(() => _selectedCustomer = matches.first);
          await _loadCustomerStatus(matches.first);
          _showMessage('Customer selected from phonebook.');
          return;
        }
      }

      final createdId = await _api.createCustomer({
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
      });
      final createdCustomer = Customer(
        id: createdId,
        name: name,
        phone: phone.isEmpty ? null : phone,
        email: email.isEmpty ? null : email,
        address: address.isEmpty ? null : address,
      );
      setState(() => _selectedCustomer = createdCustomer);
      await _loadCustomerStatus(createdCustomer);
      _showMessage('Phonebook contact saved and selected.');
    } catch (e) {
      _showMessage(
        ApiClient.friendlyError(
          e,
          fallback: 'Could not import that phonebook contact right now.',
        ),
        error: true,
      );
    }
  }

  void _submit() {
    if (_requiresCustomer && _selectedCustomer == null) {
      _showMessage('Choose a customer for this credit sale.', error: true);
      return;
    }
    if (_willCreateCreditBalance && _selectedCustomer == null) {
      _showMessage(
        'Choose a customer so the remaining balance can be saved as credit.',
        error: true,
      );
      return;
    }
    Navigator.of(context).pop(
      _SaleCheckoutResult(
        paymentMethod: _paymentMethod,
        secondaryMethod: _paymentMethod,
        amountText: _amountCtrl.text.trim(),
        customer: _selectedCustomer,
        availablePrepayment: _availablePrepayment,
        pendingBalance: _pendingBalance,
        collectLater: _collectLater,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentMethods = const ['CASH', 'ECOCASH', 'TRANSFER', 'CARD'];
    final netTotal = (widget.total - _prepaymentAppliedPreview).clamp(0, double.infinity);

    Widget pillButton({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Color selectedColor = const Color(0xFFE31B23),
      Color selectedTextColor = Colors.white,
      IconData? icon,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? selectedColor : const Color(0xFFE4DED9),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? selectedTextColor : Colors.black54),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? selectedTextColor : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget summaryRow(String label, String value, {Color? valueColor, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 18 : 16,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: bold ? 18 : 16,
                fontWeight: FontWeight.w900,
                color: valueColor ?? Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Confirm Sale',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE4DED9)),
              ),
              child: Column(
                children: [
                  summaryRow('Sale Total:', '\$${widget.total.toStringAsFixed(2)}'),
                  const Divider(height: 1),
                  summaryRow(
                    'Prepayment Applied:',
                    '-\$${_prepaymentAppliedPreview.toStringAsFixed(2)}',
                  ),
                  const Divider(height: 1),
                  summaryRow(
                    'Net Total:',
                    '\$${netTotal.toStringAsFixed(2)}',
                    valueColor: const Color(0xFFE31B23),
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Amount Tendered',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFE31B23), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFE31B23), width: 2),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4DED9)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Credit:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '\$${_creditAddedPreview.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF39C12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'PhoneBook Customer Contact',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedCustomer == null
                        ? 'No customer selected'
                        : [
                            _selectedCustomer!.name,
                            _selectedCustomer!.phone ?? '',
                            _selectedCustomer!.email ?? '',
                          ].where((value) => value.isNotEmpty).join(' - '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _pickCustomerFromPhonebook,
                  icon: const Icon(
                    Icons.contact_phone_rounded,
                    color: Color(0xFF1FAA00),
                    size: 34,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pickCustomer,
                  icon: const Icon(Icons.person_search_rounded),
                  label: Text(_selectedCustomer == null ? 'Select Customer' : 'Change Customer'),
                ),
                if (_selectedCustomer != null)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _selectedCustomer = null;
                      _availablePrepayment = 0;
                      _pendingBalance = 0;
                    }),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            if (_selectedCustomer != null) ...[
              const SizedBox(height: 12),
              if (_loadingCustomerStatus)
                const LinearProgressIndicator()
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_availablePrepayment > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Customer balance +${_availablePrepayment.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    if (_pendingBalance > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Customer balance -${_pendingBalance.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Color(0xFFB71C1C),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Collection Status:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                pillButton(
                  label: 'Collect Now',
                  selected: !_collectLater,
                  onTap: () => setState(() => _collectLater = false),
                ),
                pillButton(
                  label: 'Collect Later',
                  selected: _collectLater,
                  onTap: () => setState(() => _collectLater = true),
                  selectedColor: const Color(0xFFF6F3F0),
                  selectedTextColor: Colors.black87,
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Mode of Payment:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: paymentMethods
                  .map(
                    (method) => pillButton(
                      label: method,
                      selected: _paymentMethod == method,
                      onTap: () => setState(() {
                        _paymentMethod = method;
                        _secondaryMethod = method;
                      }),
                    ),
                  )
                  .toList(),
            ),
            if (_willCreateCreditBalance) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'If the amount tendered is less than the net total, the remaining amount will be added to the customer account automatically.',
                  style: TextStyle(
                    color: Color(0xFF8D4E00),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF169536),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Confirm & Print Receipt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
