import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class ProductsScreen extends StatefulWidget {
  final AppState appState;
  const ProductsScreen({super.key, required this.appState});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _q = TextEditingController();
  bool _loading = false;
  List<Product> _products = [];
  String? _error;
  Timer? _searchDebounce;

  bool get _canManage {
    final role = (widget.appState.user?.role ?? 'TELLER').toUpperCase();
    return role != 'TELLER';
  }

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _q.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _q.removeListener(_handleSearchChanged);
    _q.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getProducts(
        search: _q.text.trim(),
        all: false,
        limit: _q.text.trim().isEmpty ? 800 : 1200,
      );
      setState(() => _products = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({Product? product}) async {
    final name = TextEditingController(text: product?.name ?? '');
    final barcode = TextEditingController(text: product?.barcode ?? '');
    final cost = TextEditingController(
      text: product != null ? (product.costPrice).toString() : '0',
    );
    final price = TextEditingController(
      text: product != null ? (product.sellPrice).toString() : '0',
    );
    final reorder = TextEditingController(
      text: product != null ? (product.reorderLevel).toString() : '0',
    );

    final qty = TextEditingController(text: '');
    final locs = widget.appState.accessibleLocations;
    int? stockLocId =
        widget.appState.defaultLocationId ?? (locs.isNotEmpty ? locs.first.id : null);
    bool updateStock = false;

    final addQty = TextEditingController(text: '');
    final addNote = TextEditingController(text: '');
    int? addStockLocId = stockLocId;
    bool addStockMode = false;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        String? dialogError;
        var saving = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final viewInsets = MediaQuery.of(ctx).viewInsets;
            return FractionallySizedBox(
              heightFactor: 0.94,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, viewInsets.bottom + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product == null ? 'Add Bale Product' : 'Edit Bale Product',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dialogError != null) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    dialogError!,
                                    style: const TextStyle(
                                      color: Color(0xFFB71C1C),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              TextField(
                                controller: name,
                                enabled: !saving,
                                decoration: const InputDecoration(labelText: 'Name'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: barcode,
                                enabled: !saving,
                                decoration: const InputDecoration(labelText: 'Barcode (optional)'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: cost,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Cost price'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: price,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Sell price'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: reorder,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Reorder level'),
                              ),
                              const SizedBox(height: 14),
                              const Divider(),
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                value: updateStock,
                                onChanged: saving ? null : (value) => setSheetState(() => updateStock = value),
                                title: const Text('Change stock quantity', style: TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: const Text('Sets the on-hand quantity for a location.'),
                              ),
                              if (updateStock) ...[
                                DropdownButtonFormField<int>(
                                  value: locs.any((location) => location.id == stockLocId) ? stockLocId : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Location'),
                                  items: locs
                                      .map(
                                        (location) => DropdownMenuItem<int>(
                                          value: location.id,
                                          child: Text('${location.name} (${location.type})'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: saving ? null : (value) => setSheetState(() => stockLocId = value),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: qty,
                                  enabled: !saving,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Quantity (on hand)'),
                                ),
                              ],
                              if (product != null) ...[
                                const SizedBox(height: 14),
                                const Divider(),
                                const SizedBox(height: 8),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  value: addStockMode,
                                  onChanged: saving ? null : (value) => setSheetState(() => addStockMode = value),
                                  title: const Text('Add stock', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: const Text('Increment stock by a quantity from a delivery.'),
                                ),
                                if (addStockMode) ...[
                                  DropdownButtonFormField<int>(
                                    value: locs.any((location) => location.id == addStockLocId) ? addStockLocId : null,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Location'),
                                    items: locs
                                        .map(
                                          (location) => DropdownMenuItem<int>(
                                            value: location.id,
                                            child: Text('${location.name} (${location.type})'),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: saving ? null : (value) => setSheetState(() => addStockLocId = value),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: addQty,
                                    enabled: !saving,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Quantity to add'),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: addNote,
                                    enabled: !saving,
                                    decoration: const InputDecoration(
                                      labelText: 'Note (optional)',
                                      hintText: 'e.g. Supplier delivery',
                                    ),
                                  ),
                                ],
                              ],
                              if (saving) ...[
                                const SizedBox(height: 12),
                                const LinearProgressIndicator(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (product != null) ...[
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: ctx,
                                        builder: (confirmCtx) => AlertDialog(
                                          title: const Text('Delete Bale Product'),
                                          content: Text('Delete ${product.name}?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(confirmCtx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(confirmCtx, true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(0xFFE31B23),
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) return;
                                      setSheetState(() {
                                        dialogError = null;
                                        saving = true;
                                      });
                                      try {
                                        await _api.deleteProduct(product.id);
                                        if (ctx.mounted) Navigator.pop(ctx, true);
                                      } catch (e) {
                                        setSheetState(() {
                                          dialogError = e.toString().replaceFirst('Exception: ', '');
                                          saving = false;
                                        });
                                      }
                                    },
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Color(0xFFE31B23), fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving ? null : () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final n = name.text.trim();
                                      if (n.isEmpty) {
                                        setSheetState(() => dialogError = 'Name required.');
                                        return;
                                      }
                                      setSheetState(() {
                                        dialogError = null;
                                        saving = true;
                                      });
                                      try {
                                        final c = double.tryParse(cost.text.trim()) ?? 0;
                                        final p = double.tryParse(price.text.trim()) ?? 0;
                                        final r = int.tryParse(reorder.text.trim()) ?? 0;
                                        if (product == null) {
                                          final newId = await _api.createProduct(
                                            name: n,
                                            barcode: barcode.text.trim(),
                                            costPrice: c,
                                            sellPrice: p,
                                            reorderLevel: r,
                                          );
                                          if (updateStock) {
                                            final locId = stockLocId;
                                            final q = double.tryParse(qty.text.trim());
                                            if (locId == null) {
                                              throw Exception('Select a location for stock quantity.');
                                            }
                                            if (q == null) {
                                              throw Exception('Enter a valid quantity (on hand).');
                                            }
                                            await _api.setStock(locationId: locId, productId: newId, onHand: q);
                                          }
                                        } else {
                                          await _api.updateProduct(
                                            id: product.id,
                                            name: n,
                                            barcode: barcode.text.trim(),
                                            costPrice: c,
                                            sellPrice: p,
                                            reorderLevel: r,
                                          );
                                          if (updateStock) {
                                            final locId = stockLocId;
                                            final q = double.tryParse(qty.text.trim());
                                            if (locId == null) {
                                              throw Exception('Select a location for stock quantity.');
                                            }
                                            if (q == null) {
                                              throw Exception('Enter a valid quantity (on hand).');
                                            }
                                            await _api.setStock(
                                              locationId: locId,
                                              productId: product.id,
                                              onHand: q,
                                            );
                                          }
                                          if (addStockMode) {
                                            final locId = addStockLocId;
                                            final q = int.tryParse(addQty.text.trim());
                                            if (locId == null) {
                                              throw Exception('Select a location for add stock.');
                                            }
                                            if (q == null || q <= 0) {
                                              throw Exception('Enter a valid quantity to add (> 0).');
                                            }
                                            await _api.addStock(
                                              locationId: locId,
                                              productId: product.id,
                                              quantity: q,
                                              note: addNote.text.trim(),
                                            );
                                          }
                                        }
                                        if (ctx.mounted) Navigator.pop(ctx, true);
                                      } catch (e) {
                                        setSheetState(() {
                                          dialogError = e.toString().replaceFirst('Exception: ', '');
                                          saving = false;
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE31B23),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(saving ? 'Saving...' : 'Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    name.dispose();
    barcode.dispose();
    cost.dispose();
    price.dispose();
    reorder.dispose();
    qty.dispose();
    addQty.dispose();
    addNote.dispose();

    if (changed == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileHeroCard(
            title: 'Bale Products',
            subtitle: 'Manage bale product names, pricing, and stock-ready items.',
            trailing: [
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
              if (_canManage)
                IconButton(
                  onPressed: _loading ? null : () => _openEditor(),
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  MobileSearchField(
                    controller: _q,
                    hintText: 'Search bale products',
                    onChanged: (_) {},
                    onSubmitted: (_) => _load(),
                    showPrefixIcon: false,
                    showActionButton: false,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MobileMetricChip('Items: ${_products.length}'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB71C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
            else if (_products.isEmpty)
              const MobileEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'No bale products found',
                message: 'Try a different search or add a new bale product.',
              )
            else
            ..._products.map(
              (product) => MobileActionTile(
                icon: Icons.inventory_2_rounded,
                accentColor: const Color(0xFF5D4037),
                title: product.name,
                subtitle: [
                  'Barcode: ${(product.barcode ?? '').isEmpty ? '-' : product.barcode!}',
                  'Sell: ${product.sellPrice.toStringAsFixed(2)}',
                  'Cost: ${product.costPrice.toStringAsFixed(2)}',
                  'Reorder: ${product.reorderLevel}',
                ].join(' - '),
                trailing: _canManage
                    ? const Icon(Icons.edit_rounded)
                    : const Icon(Icons.visibility_outlined),
                onTap: _canManage ? () => _openEditor(product: product) : null,
              ),
            ),
        ],
      ),
    );
  }
}
