import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class StockOutScreen extends StatefulWidget {
  final AppState appState;
  const StockOutScreen({super.key, required this.appState});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _targetCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _locationId;
  int? _productId;
  String _action = 'REMOVE';
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _movements = const [];

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.defaultLocationId;
    _searchCtrl.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _targetCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0;
  }

  int _int(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  String _money(dynamic value) => _num(value).toStringAsFixed(0);

  Map<String, dynamic>? get _selectedProduct {
    for (final row in _products) {
      if (_int(row['id']) == _productId) return row;
    }
    return null;
  }

  Future<void> _load() async {
    final locationId = _locationId;
    if (locationId == null || locationId <= 0) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Choose a location first.';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getStockOutData(
        locationId: locationId,
        search: _searchCtrl.text.trim(),
      );
      final products = ((data['products'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final movements = ((data['movements'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _products = products;
        _movements = movements;
        if (_selectedProduct == null) {
          _productId = products.isEmpty ? null : _int(products.first['id']);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.friendlyError(
          e,
          fallback: 'Could not load stock out right now. Refresh to try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final productId = _productId;
    final locationId = _locationId;
    if (productId == null || productId <= 0 || locationId == null || locationId <= 0) {
      _showMessage('Choose a bale product first.', error: true);
      return;
    }

    final current = _selectedProduct;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Stock Movement'),
        content: Text(
          current == null
              ? 'Save this stock movement?'
              : 'Save ${_action.toLowerCase()} for ${current['name']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _api.postStockOut(
        locationId: locationId,
        productId: productId,
        action: _action,
        quantity: _action == 'ADJUST' ? 0 : _int(_qtyCtrl.text),
        targetQty: _action == 'ADJUST' ? _int(_targetCtrl.text) : null,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      _noteCtrl.clear();
      _qtyCtrl.text = '1';
      _targetCtrl.text = '${_int(current?['on_hand'])}';
      _showMessage('Stock movement saved.');
      await _load();
    } catch (e) {
      _showMessage(ApiClient.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProduct;
    final locations = widget.appState.accessibleLocations;

    return MobilePageScaffold(
      title: 'Out Stock',
      subtitle: '',
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileSectionCard(
              icon: Icons.remove_shopping_cart_rounded,
              title: 'Stock Out And Corrections',
              subtitle: 'Remove stock, add missing stock, or correct balances just like the web screen.',
              accentColor: const Color(0xFFE31B23),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: _locationId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem<int>(
                            value: location.id,
                            child: Text('${location.name} (${location.type})'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      setState(() => _locationId = value);
                      await _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  MobileSearchField(
                    controller: _searchCtrl,
                    hintText: 'Search bale product, barcode, category, or label',
                    onSearch: _load,
                    onChanged: (_) {},
                    onSubmitted: (_) => _load(),
                    showActionButton: false,
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    )
                  else if (_error != null)
                    MobileRetryState(
                      icon: Icons.wifi_off_rounded,
                      title: 'Could Not Load Stock Out',
                      message: _error!,
                      onRetry: _load,
                    )
                  else ...[
                    DropdownButtonFormField<int>(
                      value: _productId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Bale product'),
                      items: _products
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _int(row['id']),
                              child: Text(
                                '${row['name']} | On hand: ${_int(row['on_hand'])}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _productId = value;
                          final current = _selectedProduct;
                          _targetCtrl.text = '${_int(current?['on_hand'])}';
                        });
                      },
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          MobileMetricChip('On hand: ${_int(selected['on_hand'])}'),
                          MobileMetricChip('Category: ${selected['category_name'] ?? '-'}'),
                          MobileMetricChip('Label: ${selected['label'] ?? '-'}'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in const ['REMOVE', 'ADD', 'ADJUST'])
                          ChoiceChip(
                            label: Text(action),
                            selected: _action == action,
                            onSelected: (_) {
                              setState(() => _action = action);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_action == 'ADJUST')
                      TextField(
                        controller: _targetCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Target on hand'),
                      )
                    else
                      TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quantity'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Reason / note'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving...' : 'Save Movement'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.history_rounded,
              title: 'Recent Stock Movements',
              subtitle: '',
              accentColor: const Color(0xFF6D4C41),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _movements.isEmpty
                      ? const MobileEmptyState(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'No stock movements',
                          message: 'Recent manual additions, removals, and corrections will appear here.',
                        )
                      : Column(
                          children: _movements
                              .map(
                                (row) => Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (row['product_name'] ?? '-').toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            MobileStatusBadge(
                                              label: (row['type'] ?? '-').toString(),
                                              backgroundColor: const Color(0xFFFFF3E0),
                                              foregroundColor: const Color(0xFFEF6C00),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            MobileMetricChip('Qty: ${_money(row['qty_delta'])}'),
                                            MobileMetricChip('Location: ${row['location_name'] ?? '-'}'),
                                            MobileMetricChip('By: ${row['user_name'] ?? '-'}'),
                                          ],
                                        ),
                                        if ((row['note'] ?? '').toString().trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text((row['note'] ?? '').toString()),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
