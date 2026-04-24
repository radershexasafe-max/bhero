import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class BaleCreationScreen extends StatefulWidget {
  final AppState appState;

  const BaleCreationScreen({super.key, required this.appState});

  @override
  State<BaleCreationScreen> createState() => _BaleCreationScreenState();
}

class _BaleCreationScreenState extends State<BaleCreationScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  Timer? _errorTimer;
  Timer? _searchDebounce;

  List<ProductCategory> _categories = [];
  List<Product> _products = [];
  List<Map<String, dynamic>> _labels = [];
  List<Map<String, dynamic>> _bales = [];
  List<Map<String, dynamic>> _userChoices = [];

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;
  double _toDouble(dynamic value) => double.tryParse('${value ?? ''}') ?? 0.0;
  int? _safeChoice(int? value, Iterable<int> allowedIds) =>
      (value != null && allowedIds.contains(value)) ? value : null;
  double _dialogWidth(BuildContext context, [double maxWidth = 420]) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth > (maxWidth + 56) ? maxWidth : (screenWidth - 56);
  }

  List<Map<String, dynamic>> _uniqueRowsById(List<Map<String, dynamic>> rows) {
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final row in rows) {
      final id = _toInt(row['id']);
      if (id <= 0 || seen.add(id)) {
        out.add(row);
      }
    }
    return out;
  }

  void _mergeProducts(Iterable<Product> incoming) {
    final merged = <int, Product>{
      for (final item in _products)
        if (item.id > 0) item.id: item,
    };
    for (final item in incoming) {
      if (item.id > 0) {
        merged[item.id] = item;
      }
    }
    _products = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Map<String, dynamic>> _mapProductsToChoiceRows(Iterable<Product> products) {
    return products
        .map((item) => {
              'id': item.id,
              'label': item.name,
              'subtitle': (item.barcode ?? '').trim(),
              'keywords': '${item.name} ${item.barcode ?? ''}',
            })
        .toList();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('duplicate_bale')) {
      return 'This bale entry already exists.';
    }
    if (text.contains('duplicate_bale_order')) {
      return 'That bale order already exists.';
    }
    if (text.contains('quantity_order_required')) {
      return 'Enter the quantity to order.';
    }
    if (text.contains('received_by_required')) {
      return 'Select the user who should receive this order.';
    }
    if (text.toLowerCase().contains('not_found')) {
      return 'This action needs the latest server update. Upload the newest backend files and try again.';
    }
    return ApiClient.friendlyError(
      error,
      fallback: 'This bale action could not be completed right now.',
    );
  }

  void _setError(Object error, {bool autoClear = true}) {
    _errorTimer?.cancel();
    if (!mounted) return;
    setState(() => _error = _friendlyError(error));
    if (autoClear) {
      _errorTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _error = null);
        }
      });
    }
  }

  void _clearError() {
    _errorTimer?.cancel();
    if (!mounted) return;
    setState(() => _error = null);
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
      final categories = await api.getBaleCategories();
      final labels = await api.getBaleLabels();
      final products = await api.getProducts(
        all: false,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        limit: 120,
      );
      final bales = await api.getBales(
        search: _searchCtrl.text.trim(),
        limit: 160,
      );
      List<Map<String, dynamic>> userChoices = [];
      try {
        userChoices = await api.getUserChoices();
      } catch (_) {
        userChoices = const [];
      }
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _labels = labels;
        _mergeProducts(products);
        _bales = bales;
        _userChoices = _uniqueRowsById(userChoices);
        _error = null;
      });
    } catch (e) {
      _setError(e, autoClear: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _categoryChoiceRows => _categories
      .map((item) => {
            'id': item.id,
            'label': item.name,
            'keywords': item.name,
          })
      .toList();

  List<Map<String, dynamic>> get _productChoiceRows => _mapProductsToChoiceRows(_products);

  List<Map<String, dynamic>> get _labelChoiceRows => _labels
      .map((item) => {
            'id': _toInt(item['id']),
            'label': (item['name'] ?? '').toString(),
            'keywords': (item['name'] ?? '').toString(),
          })
      .where((item) => _toInt(item['id']) > 0)
      .toList();

  String _selectedChoiceLabel(int? selectedId, List<Map<String, dynamic>> rows) {
    if (selectedId == null || selectedId <= 0) return '';
    for (final row in rows) {
      if (_toInt(row['id']) == selectedId) {
        return (row['label'] ?? '').toString();
      }
    }
    return '';
  }

  String _selectedProductLabel(int? selectedId, [String fallback = '']) {
    final local = _selectedChoiceLabel(selectedId, _productChoiceRows);
    return local.isNotEmpty ? local : fallback;
  }

  Future<List<Map<String, dynamic>>> _searchProductChoiceRows(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty && _products.isNotEmpty) {
      return _productChoiceRows;
    }
    final products = await api.getProducts(
      search: trimmed.isEmpty ? null : trimmed,
      all: false,
      limit: 120,
    );
    if (mounted && products.isNotEmpty) {
      setState(() => _mergeProducts(products));
    }
    if (products.isEmpty && trimmed.isEmpty) {
      return _productChoiceRows;
    }
    return _mapProductsToChoiceRows(products);
  }

  Future<int?> _pickChoice({
    required String title,
    required String searchHint,
    required List<Map<String, dynamic>> rows,
    int? selectedId,
    bool allowClear = false,
    String clearLabel = 'Clear selection',
    Future<List<Map<String, dynamic>>> Function(String query)? remoteSearch,
  }) async {
    final searchCtrl = TextEditingController();
    final picked = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        var query = '';
        var loading = false;
        var initialized = false;
        var liveRows = List<Map<String, dynamic>>.from(rows);

        Future<void> refreshRows(StateSetter setModalState, String value) async {
          final normalized = value.trim().toLowerCase();
          if (remoteSearch == null) {
            setModalState(() => query = normalized);
            return;
          }
          setModalState(() {
            query = normalized;
            loading = true;
          });
          try {
            final next = await remoteSearch(value);
            if (!sheetCtx.mounted) return;
            setModalState(() {
              liveRows = next;
              loading = false;
            });
          } catch (_) {
            if (!sheetCtx.mounted) return;
            setModalState(() => loading = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized) {
              initialized = true;
              if (remoteSearch != null && rows.isEmpty) {
                unawaited(refreshRows(setModalState, searchCtrl.text));
              }
            }

            final filtered = remoteSearch != null
                ? liveRows
                : rows.where((row) {
                    if (query.isEmpty) return true;
                    final label = (row['label'] ?? '').toString().toLowerCase();
                    final subtitle = (row['subtitle'] ?? '').toString().toLowerCase();
                    final keywords = (row['keywords'] ?? '').toString().toLowerCase();
                    return label.contains(query) ||
                        subtitle.contains(query) ||
                        keywords.contains(query);
                  }).toList();
            return FractionallySizedBox(
              heightFactor: 0.88,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
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
                        hintText: searchHint,
                        onChanged: (value) => refreshRows(setModalState, value),
                        showPrefixIcon: false,
                        showActionButton: false,
                      ),
                      if (allowClear) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => Navigator.pop(ctx, -1),
                            icon: const Icon(Icons.clear_rounded),
                            label: Text(clearLabel),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : filtered.isEmpty
                            ? const Center(
                                child: Text('No matching items were found.'),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final row = filtered[index];
                                  final rowId = _toInt(row['id']);
                                  final subtitle = (row['subtitle'] ?? '').toString().trim();
                                  return ListTile(
                                    selected: selectedId != null && rowId == selectedId,
                                    leading: Icon(
                                      selectedId != null && rowId == selectedId
                                          ? Icons.check_circle_rounded
                                          : Icons.search_rounded,
                                      color: selectedId != null && rowId == selectedId
                                          ? const Color(0xFFE31B23)
                                          : Colors.black45,
                                    ),
                                    title: Text((row['label'] ?? '').toString()),
                                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                                    onTap: () => Navigator.pop(ctx, rowId),
                                  );
                                },
                              ),
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
    searchCtrl.dispose();
    return picked;
  }

  Widget _searchChoiceField({
    required String label,
    required String valueText,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool enabled = true,
  }) {
    final hasValue = valueText.trim().isNotEmpty;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: label,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasValue && onClear != null)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: enabled ? onClear : null,
                  icon: const Icon(Icons.clear_rounded),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.search_rounded),
              ),
            ],
          ),
        ),
        isEmpty: !hasValue,
        child: hasValue
            ? Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const SizedBox(height: 20),
      ),
    );
  }

  Widget _editorSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _editorPickerField({
    required String label,
    required String valueText,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool enabled = true,
  }) {
    final hasValue = valueText.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _editorSectionLabel(label),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F6F4),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE5DED8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? valueText : label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: hasValue ? Colors.black : Colors.black38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasValue && onClear != null)
                  IconButton(
                    onPressed: enabled ? onClear : null,
                    icon: const Icon(Icons.clear_rounded),
                  ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.black54),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _editorTextField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _editorSectionLabel(label),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F6F4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFE5DED8)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFE31B23), width: 1.4),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFE5DED8)),
            ),
          ),
        ),
      ],
    );
  }

  String _formatBaleDate(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return '${parsed.month}/${parsed.day}/${parsed.year}, ${parsed.hour}:${parsed.minute.toString().padLeft(2, '0')}:${parsed.second.toString().padLeft(2, '0')}';
  }

  Future<void> _openEditor([Map<String, dynamic>? bale]) async {
    final categoryOptions = _categories.map((item) => item.id).toList();
    final labelOptions = _labels.map((item) => _toInt(item['id'])).where((id) => id > 0).toList();

    final categoryId = ValueNotifier<int?>(
      _safeChoice(_toInt(bale?['category_id']) == 0 ? null : _toInt(bale?['category_id']), categoryOptions),
    );
    final productId = ValueNotifier<int?>(
      _toInt(bale?['product_id']) == 0 ? null : _toInt(bale?['product_id']),
    );
    final labelId = ValueNotifier<int?>(
      _safeChoice(_toInt(bale?['label_id']) == 0 ? null : _toInt(bale?['label_id']), labelOptions),
    );
    final grade = ValueNotifier<int>(
      _toInt(bale?['grade']) == 0 ? 1 : _toInt(bale?['grade']),
    );
    final unit = ValueNotifier<String>(
      ((bale?['unit_of_measure'] ?? 'KGS').toString()).toUpperCase(),
    );

    final qtyCtrl = TextEditingController(
      text: bale == null ? '' : '${bale['unit_quantity'] ?? ''}',
    );
    final costCtrl = TextEditingController(
      text: bale == null ? '' : '${bale['cost_price'] ?? ''}',
    );
    final sellCtrl = TextEditingController(
      text: bale == null ? '' : '${bale['sell_price'] ?? ''}',
    );

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
            final insets = MediaQuery.of(ctx).viewInsets;
            return FractionallySizedBox(
              heightFactor: 0.94,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, insets.bottom + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bale == null ? 'Add Bale' : 'Edit Bale',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close_rounded, size: 34),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (dialogError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB71C1C),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Expanded(
                        child: ListView(
                          children: [
                            ValueListenableBuilder<int?>(
                              valueListenable: categoryId,
                              builder: (_, value, __) => _editorPickerField(
                                label: 'Bale Category *',
                                valueText: _selectedChoiceLabel(value, _categoryChoiceRows),
                                enabled: !saving,
                                onTap: () async {
                                  final picked = await _pickChoice(
                                    title: 'Select Bale Category',
                                    searchHint: 'Search categories',
                                    rows: _categoryChoiceRows,
                                    selectedId: value,
                                  );
                                  if (picked != null && categoryOptions.contains(picked)) {
                                    categoryId.value = picked;
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<int?>(
                              valueListenable: productId,
                              builder: (_, value, __) => _editorPickerField(
                                label: 'Bale Product *',
                                valueText: _selectedProductLabel(
                                  value,
                                  (bale?['product_name'] ?? '').toString(),
                                ),
                                enabled: !saving,
                                onTap: () async {
                                  final picked = await _pickChoice(
                                    title: 'Select Bale Product',
                                    searchHint: 'Search bale products',
                                    rows: _productChoiceRows,
                                    selectedId: value,
                                    remoteSearch: _searchProductChoiceRows,
                                  );
                                  if (picked != null && picked > 0) {
                                    productId.value = picked;
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<int?>(
                              valueListenable: labelId,
                              builder: (_, value, __) => _editorPickerField(
                                label: 'Bale Label *',
                                valueText: _selectedChoiceLabel(value, _labelChoiceRows),
                                enabled: !saving,
                                onTap: () async {
                                  final picked = await _pickChoice(
                                    title: 'Select Bale Label',
                                    searchHint: 'Search bale labels',
                                    rows: _labelChoiceRows,
                                    selectedId: value,
                                  );
                                  if (picked != null && labelOptions.contains(picked)) {
                                    labelId.value = picked;
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<int>(
                              valueListenable: grade,
                              builder: (_, value, __) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _editorSectionLabel('Bale Grade *'),
                                  DropdownButtonFormField<int>(
                                    value: value,
                                    isExpanded: true,
                                    decoration: const InputDecoration(),
                                    items: const [
                                      DropdownMenuItem(value: 1, child: Text('#1')),
                                      DropdownMenuItem(value: 2, child: Text('#2')),
                                      DropdownMenuItem(value: 3, child: Text('#3')),
                                      DropdownMenuItem(value: 4, child: Text('#4')),
                                      DropdownMenuItem(value: 5, child: Text('#5')),
                                    ],
                                    onChanged: saving ? null : (v) => grade.value = v ?? 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<String>(
                              valueListenable: unit,
                              builder: (_, value, __) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _editorSectionLabel('Unit of Measure *'),
                                  DropdownButtonFormField<String>(
                                    value: value,
                                    isExpanded: true,
                                    decoration: const InputDecoration(),
                                    items: const [
                                      DropdownMenuItem(value: 'KGS', child: Text('kgs')),
                                      DropdownMenuItem(value: 'PCS', child: Text('pcs')),
                                    ],
                                    onChanged: saving ? null : (v) => unit.value = v ?? 'KGS',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<String>(
                              valueListenable: unit,
                              builder: (_, value, __) => _editorTextField(
                                label: value == 'KGS' ? 'Weight (kg) *' : 'Pieces *',
                                controller: qtyCtrl,
                                enabled: !saving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _editorTextField(
                              label: 'Bale Cost Price *',
                              controller: costCtrl,
                              enabled: !saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 14),
                            _editorTextField(
                              label: 'Bale Selling Price *',
                              controller: sellCtrl,
                              enabled: !saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (bale != null) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final confirmed = await showMobileConfirmDialog(
                                          ctx,
                                          title: 'Delete Bale',
                                          message: 'Delete ${(bale['product_name'] ?? 'this bale').toString()}?',
                                          confirmLabel: 'Delete',
                                          icon: Icons.delete_outline_rounded,
                                        );
                                        if (!confirmed) return;
                                        setSheetState(() {
                                          dialogError = null;
                                          saving = true;
                                        });
                                        try {
                                          await api.deleteBale(_toInt(bale['id']));
                                          if (ctx.mounted) Navigator.pop(ctx, true);
                                        } catch (e) {
                                          setSheetState(() {
                                            dialogError = _friendlyError(e);
                                            saving = false;
                                          });
                                        }
                                      },
                                child: const Text('Delete'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final qty = double.tryParse(qtyCtrl.text.trim());
                                      final cost = double.tryParse(costCtrl.text.trim());
                                      final sell = double.tryParse(sellCtrl.text.trim());
                                      if (categoryId.value == null) {
                                        setSheetState(() => dialogError = 'Select a bale category.');
                                        return;
                                      }
                                      if (productId.value == null) {
                                        setSheetState(() => dialogError = 'Select a bale product.');
                                        return;
                                      }
                                      if (labelId.value == null) {
                                        setSheetState(() => dialogError = 'Select a bale label.');
                                        return;
                                      }
                                      if (qty == null || qty <= 0) {
                                        setSheetState(() => dialogError = 'Enter a valid bale quantity.');
                                        return;
                                      }
                                      if (cost == null || cost < 0) {
                                        setSheetState(() => dialogError = 'Enter a valid bale cost price.');
                                        return;
                                      }
                                      if (sell == null || sell < 0) {
                                        setSheetState(() => dialogError = 'Enter a valid bale selling price.');
                                        return;
                                      }
                                      final confirmed = await showMobileConfirmDialog(
                                        ctx,
                                        title: bale == null ? 'Save Bale' : 'Update Bale',
                                        message: bale == null
                                            ? 'Save this bale item?'
                                            : 'Save changes to this bale item?',
                                        confirmLabel: 'Confirm',
                                        icon: Icons.check_circle_outline_rounded,
                                      );
                                      if (!confirmed) return;
                                      setSheetState(() {
                                        dialogError = null;
                                        saving = true;
                                      });
                                      try {
                                        final payload = {
                                          'category_id': categoryId.value,
                                          'product_id': productId.value,
                                          'label_id': labelId.value,
                                          'grade': grade.value,
                                          'unit_of_measure': unit.value,
                                          'unit_quantity': qtyCtrl.text.trim(),
                                          'cost_price': costCtrl.text.trim(),
                                          'sell_price': sellCtrl.text.trim(),
                                        };
                                        if (bale != null) {
                                          await api.updateBale(_toInt(bale['id']), payload);
                                        } else {
                                          await api.saveBale(payload);
                                        }
                                        if (ctx.mounted) Navigator.pop(ctx, true);
                                      } catch (e) {
                                        setSheetState(() {
                                          dialogError = _friendlyError(e);
                                          saving = false;
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE31B23),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
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
    if (changed == true) {
      _clearError();
      await _load();
    }
  }

  Future<void> _openOrderDialog(Map<String, dynamic> bale) async {
    final qtyCtrl = TextEditingController();
    final receiverNameCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final costCtrl = TextEditingController(
      text: _toDouble(bale['cost_price']).toStringAsFixed(2),
    );

    final currentUserId = widget.appState.user?.id;
    final receiverRows = _uniqueRowsById(_userChoices)
        .where((row) => _toInt(row['id']) > 0)
        .toList();
    final receiverOptions = receiverRows.map((row) => _toInt(row['id'])).toList();
    final defaultReceiverId = receiverRows.any((row) => _toInt(row['id']) == currentUserId) ? currentUserId : null;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        String? dialogError;
        var saving = false;
        var receiverId = _safeChoice(defaultReceiverId, receiverOptions);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
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
                          const Expanded(
                            child: Text(
                              'Make Bale Order',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                                  margin: const EdgeInsets.only(top: 4, bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    dialogError!,
                                    style: const TextStyle(
                                      color: Color(0xFFB71C1C),
                                      fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ] else
                                const SizedBox(height: 8),
                              _dialogLine('Bale name', (bale['product_name'] ?? '-').toString()),
                              _dialogLine('Category', (bale['category_name'] ?? '-').toString()),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 360;
                                  final unitStat = _infoStat(
                                    'Unit of measure',
                                    '${bale['unit_quantity'] ?? 0} ${(bale['unit_of_measure'] ?? '').toString()}',
                                  );
                                  final stockStat = _infoStat(
                                    'In stock',
                                    '${_toInt(bale['current_stock'])}',
                                  );
                                  return narrow
                                      ? Column(
                                          children: [
                                            unitStat,
                                            const SizedBox(height: 12),
                                            stockStat,
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(child: unitStat),
                                            const SizedBox(width: 12),
                                            Expanded(child: stockStat),
                                          ],
                                        );
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: costCtrl,
                                enabled: !saving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Custom cost price'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: qtyCtrl,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Quantity to order'),
                              ),
                              const SizedBox(height: 10),
                              if (receiverRows.isNotEmpty)
                                DropdownButtonFormField<int>(
                                  value: _safeChoice(receiverId, receiverOptions),
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'To be received by'),
                                  items: receiverRows
                                      .map(
                                        (row) => DropdownMenuItem<int>(
                                          value: _toInt(row['id']),
                                          child: Text(
                                            ((row['role_label'] ?? '').toString().trim().isNotEmpty)
                                                ? '${row['name']} - ${row['role_label']}'
                                                : '${row['name']}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: saving
                                      ? null
                                      : (value) => setDialogState(() => receiverId = value),
                                )
                              else
                                TextField(
                                  controller: receiverNameCtrl,
                                  enabled: !saving,
                                  decoration: const InputDecoration(labelText: 'To be received by'),
                                ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: supplierCtrl,
                                enabled: !saving,
                                decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: noteCtrl,
                                enabled: !saving,
                                decoration: const InputDecoration(labelText: 'Note (optional)'),
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
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
                                      final qty = _toInt(qtyCtrl.text);
                                      final customCost = double.tryParse(costCtrl.text.trim());
                                      if (qty <= 0) {
                                        setDialogState(() => dialogError = 'Enter the quantity to order.');
                                        return;
                                      }
                                      if (receiverRows.isNotEmpty && receiverId == null) {
                                        setDialogState(() => dialogError = 'Select the user who should receive the order.');
                                        return;
                                      }
                                      if (receiverRows.isEmpty && receiverNameCtrl.text.trim().isEmpty) {
                                        setDialogState(() => dialogError = 'Enter the person who should receive the order.');
                                        return;
                                      }
                                      if (customCost == null || customCost < 0) {
                                        setDialogState(() => dialogError = 'Enter a valid custom cost price.');
                                        return;
                                      }
                                      final confirmed = await showDialog<bool>(
                                        context: ctx,
                                        builder: (confirmCtx) => AlertDialog(
                                          title: const Text('Create Bale Order'),
                                          content: Text(
                                            'Create an order for ${(bale['product_name'] ?? 'this bale').toString()}?',
                                          ),
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
                                              child: const Text('Confirm'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) {
                                        return;
                                      }
                                      setDialogState(() {
                                        dialogError = null;
                                        saving = true;
                                      });
                                      try {
                                        final selectedReceiverName = receiverId != null && receiverId! > 0
                                            ? receiverRows.firstWhere((row) => _toInt(row['id']) == receiverId)['name'].toString()
                                            : receiverNameCtrl.text.trim();
                                        await api.createBaleOrderFromBale(
                                          baleId: _toInt(bale['id']),
                                          quantityOrdered: qty,
                                          orderedByName: widget.appState.user?.name ?? '',
                                          receivedByName: selectedReceiverName,
                                          receivedByUserId: receiverId,
                                          supplierName: supplierCtrl.text.trim(),
                                          note: noteCtrl.text.trim(),
                                          costPrice: customCost,
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx, true);
                                      } catch (e) {
                                        setDialogState(() {
                                          dialogError = _friendlyError(e);
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
    qtyCtrl.dispose();
    receiverNameCtrl.dispose();
    supplierCtrl.dispose();
    noteCtrl.dispose();
    costCtrl.dispose();
    if (created == true) {
      _clearError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bale order created')),
      );
      await _load();
    }
  }

  Future<void> _openOutOfStockDialog(Map<String, dynamic> bale) async {
    final currentStock = _toInt(bale['current_stock']);
    if (currentStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This bale product is already out of stock.')),
      );
      return;
    }
    final locationId = _toInt(bale['current_location_id']) > 0
        ? _toInt(bale['current_location_id'])
        : (widget.appState.defaultLocationId ?? 0);
    final productId = _toInt(bale['product_id']);
    if (productId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A valid bale product is required.')),
      );
      return;
    }

    final qtyCtrl = TextEditingController(text: '$currentStock');
    final noteCtrl = TextEditingController(
      text: 'Marked out of stock from bale creation',
    );
    final availableLocations = widget.appState.accessibleLocations;
    final availableLocationIds = availableLocations.map((location) => location.id).toList();
    final selectedLocation = ValueNotifier<int?>(
      _safeChoice(
        locationId > 0 ? locationId : (availableLocations.isNotEmpty ? availableLocations.first.id : null),
        availableLocationIds,
      ),
    );

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? dialogError;
        var saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('Out Of Stock'),
            content: SizedBox(
              width: _dialogWidth(ctx, 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      width: double.infinity,
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
                    const SizedBox(height: 10),
                  ],
                  _infoStat('Bale product', (bale['product_name'] ?? '-').toString()),
                  const SizedBox(height: 10),
                  _infoStat('Current stock', '$currentStock'),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int?>(
                    valueListenable: selectedLocation,
                    builder: (_, value, __) => DropdownButtonFormField<int>(
                      value: _safeChoice(value, availableLocationIds),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Location'),
                      items: availableLocations
                          .map(
                            (location) => DropdownMenuItem<int>(
                              value: location.id,
                              child: Text('${location.name} (${location.type})'),
                            ),
                          )
                          .toList(),
                      onChanged: saving ? null : (v) => selectedLocation.value = v,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity to remove'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final qty = _toInt(qtyCtrl.text);
                        if (selectedLocation.value == null || selectedLocation.value! <= 0) {
                          setDialogState(() => dialogError = 'Select the location to update.');
                          return;
                        }
                      if (qty <= 0) {
                          setDialogState(() => dialogError = 'Enter a valid quantity to remove.');
                          return;
                        }
                        final confirmed = await showMobileConfirmDialog(
                          ctx,
                          title: 'Out Of Stock',
                          message: 'Remove $qty from ${(bale['product_name'] ?? 'this bale').toString()}?',
                          confirmLabel: 'Confirm',
                          icon: Icons.remove_shopping_cart_rounded,
                        );
                        if (!confirmed) {
                          return;
                        }
                        setDialogState(() {
                          dialogError = null;
                          saving = true;
                        });
                        try {
                          await api.postStockOut(
                            locationId: selectedLocation.value!,
                            productId: productId,
                            quantity: qty,
                            note: noteCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setDialogState(() {
                            dialogError = _friendlyError(e);
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
            ],
          ),
        );
      },
    );
    if (updated == true) {
      _clearError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock updated')),
      );
      await _load();
    }
  }

  Widget _dialogLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _infoStat(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _baleStat(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: MobileLabelValue(label: label, value: value),
    );
  }

  Widget _cardActionIconButton({
    required IconData icon,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFB),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE7E2DE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: iconColor, size: 28),
      ),
    );
  }

  Widget _cardStatColumn(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black45,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Bale Creation Process',
      subtitle: '${_bales.length} bales in stock',
      actions: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 30),
          ),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bales',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE31B23),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 30),
                  label: const Text(
                    'Add Bale',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5DED8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.045),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: MobileSearchField(
                controller: _searchCtrl,
                hintText: 'Search bale details',
                onChanged: (_) {},
                onSubmitted: (_) => _load(),
                showActionButton: false,
              ),
            ),
            if (_error != null && _bales.isNotEmpty) ...[
              const SizedBox(height: 16),
              MobileSectionCard(
                icon: Icons.cloud_off_rounded,
                title: 'Could Not Load Bales',
                subtitle: _error!,
                accentColor: const Color(0xFFE31B23),
                trailing: TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Refresh'),
                ),
                child: const Text(
                        'Check your internet connection and tap Reload to try again.',
                  style: TextStyle(color: Colors.black54),
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
            else if (_bales.isEmpty)
              _error != null
                  ? MobileRetryState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Bales Are Offline Right Now',
                      message: _error!,
                      onRetry: _load,
                    )
                  : const MobileEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No bales found',
                      message: 'Add a bale or change the search and filters.',
                    )
            else
              ..._bales.map(
                (bale) => Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(0),
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
                                    (bale['category_name'] ?? bale['product_name'] ?? 'Bale').toString(),
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '${(bale['product_name'] ?? '-')} ${(bale['label_name'] ?? '').toString().trim().isEmpty ? '' : '${bale['label_name']} '}#${bale['grade'] ?? '-'}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    'Weight: ${_toDouble(bale['unit_quantity']).toStringAsFixed(0)} ${(bale['unit_of_measure'] ?? '').toString().toLowerCase()}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              children: [
                                _cardActionIconButton(
                                  onPressed: () => _openEditor(bale),
                                  icon: Icons.edit_outlined,
                                  iconColor: const Color(0xFF64A6F3),
                                ),
                                const SizedBox(height: 10),
                                _cardActionIconButton(
                                  onPressed: () async {
                                    final confirmed = await showMobileConfirmDialog(
                                      context,
                                      title: 'Delete Bale',
                                      message: 'Delete ${(bale['product_name'] ?? 'this bale').toString()}?',
                                      confirmLabel: 'Delete',
                                      icon: Icons.delete_outline_rounded,
                                    );
                                    if (!confirmed) return;
                                    try {
                                      await api.deleteBale(_toInt(bale['id']));
                                      _clearError();
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Bale deleted')),
                                      );
                                      await _load();
                                    } catch (e) {
                                      _setError(e);
                                    }
                                  },
                                  icon: Icons.delete_outline_rounded,
                                  iconColor: const Color(0xFFE6605C),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFF1ECE8)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _cardStatColumn('Current Stock', '${_toInt(bale['current_stock'])}'),
                            _cardStatColumn('Remaining Order', '${_toInt(bale['remaining_order'])}'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Cost Price',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black45,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '\$${_toDouble(bale['cost_price']).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 21,
                                        color: Color(0xFF1FAA00),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Selling Price',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black45,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '\$${_toDouble(bale['sell_price']).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 21,
                                        color: Color(0xFFE6605C),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _openOrderDialog(bale),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE4DB00),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 19),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: const Icon(Icons.shopping_cart_outlined, size: 24),
                                label: const Text(
                                  'Make Order',
                                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _openOutOfStockDialog(bale),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF08A1D),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 19),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: const Icon(Icons.remove_shopping_cart_rounded, size: 24),
                                label: const Text(
                                  'Out Stock',
                                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (((bale['location_stock_summary'] ?? '').toString()).trim().isNotEmpty) ...[
                          Text(
                            (bale['location_stock_summary'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: Colors.black45,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _formatBaleDate(bale['created_at']),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
