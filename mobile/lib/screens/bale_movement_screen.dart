import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class BaleMovementScreen extends StatefulWidget {
  final AppState appState;
  const BaleMovementScreen({super.key, required this.appState});

  @override
  State<BaleMovementScreen> createState() => _BaleMovementScreenState();
}

class _BaleMovementScreenState extends State<BaleMovementScreen> {
  final _searchCtrl = TextEditingController();
  final _dateFmt = DateFormat('yyyy-MM-dd');
  Timer? _searchDebounce;
  bool _loading = true;
  bool _filtersExpanded = false;
  String? _error;
  int? _categoryId;
  int? _grade;
  DateTimeRange? _dateRange;
  Map<String, dynamic>? _bundle;
  List<Map<String, dynamic>> _userChoices = [];

  ApiClient get api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;
  double _toDouble(dynamic value) => double.tryParse('${value ?? ''}') ?? 0;
  int? _safeNullableInt(int? value, Iterable<int> allowedValues) =>
      (value != null && allowedValues.contains(value)) ? value : null;
  List<Map<String, dynamic>> _rows(dynamic value) => value is List ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [];

  String _friendlyLoadError(Object error) => ApiClient.friendlyError(
        error,
        fallback: 'Could not load bale movement right now. Check the connection and refresh to try again.',
      );

  void _showMessage(Object message, {bool error = false}) {
    if (!mounted) return;
    final text = message is String
        ? message
        : ApiClient.friendlyError(
            message,
            fallback: 'This bale movement action could not be completed right now.',
          );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFFC62828) : null,
      ),
    );
  }

  List<Map<String, dynamic>> _userRows() {
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final row in _userChoices) {
      final id = _toInt(row['id']);
      if (id > 0 && seen.add(id)) {
        out.add(row);
      }
    }
    return out;
  }

  List<Location> _locationRows() {
    final out = <Location>[];
    final seen = <int>{};
    for (final row in widget.appState.accessibleLocations) {
      if (seen.add(row.id)) {
        out.add(row);
      }
    }
    return out;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.getBaleMovement(
        search: _searchCtrl.text.trim(),
        categoryId: _categoryId,
        grade: _grade,
        dateFrom: _dateRange == null ? null : _dateFmt.format(_dateRange!.start),
        dateTo: _dateRange == null ? null : _dateFmt.format(_dateRange!.end),
      );
      List<Map<String, dynamic>> userChoices = [];
      try {
        userChoices = await api.getUserChoices();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _bundle = data;
        _userChoices = userChoices;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyLoadError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reverseBale(Map<String, dynamic> receiptRow) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse Bale'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.reverseBaleMovement(_toInt(receiptRow['id']), reason: reasonCtrl.text.trim());
      if (!mounted) return;
      _showMessage('Bale reversed');
      await _load();
    } catch (e) {
      _showMessage(e, error: true);
    }
  }

  Future<Map<String, dynamic>> _fetchOrder(Map<String, dynamic> row) => api.getBaleOrder(_toInt(row['id']));

  Future<void> _openOrder(Map<String, dynamic> row) async {
    try {
      final order = await _fetchOrder(row);
      final items = _rows(order['items']);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text('${order['order_number'] ?? 'Bale Order'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('To be received by: ${(order['received_by_name'] ?? '-').toString()}'),
              Text('Order date: ${(order['order_date'] ?? '-').toString()}'),
              const SizedBox(height: 12),
              ...items.map(
                (item) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item['product_name'] ?? '-'} - ${item['category_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          runSpacing: 12,
                          children: [
                            MobileLabelValue(label: 'Unit', value: '${item['unit_quantity'] ?? 0} ${(item['unit_of_measure'] ?? '').toString()}'),
                            MobileLabelValue(label: 'Remaining', value: '${_toInt(item['quantity_remaining'])}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_toInt(item['quantity_remaining']) > 0)
                              FilledButton(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await _receiveOrder(order, item);
                                },
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
                                child: const Text('Receive'),
                              ),
                            OutlinedButton(onPressed: () async { Navigator.pop(ctx); await _editOrder(row); }, child: const Text('Edit')),
                            OutlinedButton(onPressed: () async { Navigator.pop(ctx); await _deleteOrder(row); }, child: const Text('Delete')),
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
    } catch (e) {
      _showMessage('Could not load order. ${ApiClient.friendlyError(e)}', error: true);
    }
  }

  Future<void> _editOrder(Map<String, dynamic> row) async {
    try {
      final order = await _fetchOrder(row);
      final itemRows = _rows(order['items']);
      if (itemRows.isEmpty) throw Exception('This order has no items.');
      final item = itemRows.first;
      final qtyCtrl = TextEditingController(text: '${_toInt(item['quantity_ordered'])}');
      final costCtrl = TextEditingController(text: _toDouble(item['cost_price']).toStringAsFixed(2));
      final sellCtrl = TextEditingController(text: _toDouble(item['sell_price']).toStringAsFixed(2));
      final receiverRows = _userRows();
      int? receiverId;
      for (final choice in receiverRows) {
        if ('${choice['name'] ?? ''}' == '${order['received_by_name'] ?? ''}') {
          receiverId = _toInt(choice['id']);
          break;
        }
      }
      final receiverIds = receiverRows.map((choice) => _toInt(choice['id'])).where((id) => id > 0).toList();
      final selectedReceiver = ValueNotifier<int?>(_safeNullableInt(receiverId, receiverIds));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: const Text('Edit Bale Order'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity ordered')),
                const SizedBox(height: 8),
                if (receiverRows.isNotEmpty)
                  ValueListenableBuilder<int?>(
                    valueListenable: selectedReceiver,
                    builder: (_, value, __) => DropdownButtonFormField<int>(
                      value: _safeNullableInt(value, receiverIds),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'To be received by'),
                      items: receiverRows.map((choice) => DropdownMenuItem<int>(value: _toInt(choice['id']), child: Text('${choice['name']}'))).toList(),
                      onChanged: (v) => selectedReceiver.value = v,
                    ),
                  ),
                if (receiverRows.isNotEmpty) const SizedBox(height: 8),
                TextField(controller: costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cost price')),
                const SizedBox(height: 8),
                TextField(controller: sellCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final payload = <String, dynamic>{
        'quantity_ordered': _toInt(qtyCtrl.text),
        'cost_price': _toDouble(costCtrl.text),
        'sell_price': _toDouble(sellCtrl.text),
      };
      if (selectedReceiver.value != null && selectedReceiver.value! > 0) {
        payload['received_by_user_id'] = selectedReceiver.value!;
        payload['received_by_name'] = receiverRows.firstWhere((choice) => _toInt(choice['id']) == selectedReceiver.value)['name'];
      }
      await api.updateBaleOrder(_toInt(order['id']), payload);
      if (!mounted) return;
      _showMessage('Bale order updated');
      await _load();
    } catch (e) {
      _showMessage(e, error: true);
    }
  }

  Future<void> _deleteOrder(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bale Order'),
        content: Text('Delete ${(row['order_number'] ?? 'this order').toString()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteBaleOrder(_toInt(row['id']));
      if (!mounted) return;
      _showMessage('Bale order deleted');
      await _load();
    } catch (e) {
      _showMessage(e, error: true);
    }
  }

  Future<void> _openReceiveFromOrdered(Map<String, dynamic> row) async {
    try {
      final order = await _fetchOrder(row);
      final items = _rows(order['items']);
      final item = items.firstWhere((entry) => _toInt(entry['quantity_remaining']) > 0, orElse: () => const <String, dynamic>{});
      if (item.isEmpty) {
        if (!mounted) return;
        _showMessage('This order is already fully received.', error: true);
        return;
      }
      await _receiveOrder(order, item);
    } catch (e) {
      _showMessage(e, error: true);
    }
  }

  Future<void> _receiveOrder(Map<String, dynamic> order, Map<String, dynamic> item) async {
    final locations = _locationRows();
    final locationIds = locations.map((row) => row.id).toList();
    final initialLocationId = locations.isEmpty ? null : locations.first.id;
    final selectedLocation = ValueNotifier<int?>(_safeNullableInt(initialLocationId, locationIds));
    final qtyCtrl = TextEditingController();
    final sellCtrl = TextEditingController(text: '${item['sell_price'] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Receive Order'),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${item['product_name'] ?? '-'} - ${item['category_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stat('KGs/PCs', '${item['unit_quantity'] ?? 0} ${(item['unit_of_measure'] ?? '').toString()}'),
                  _stat('In stock', '${_toInt(item['current_stock'])}'),
                  _stat('Unit value', _toDouble(item['cost_price']).toStringAsFixed(2)),
                  _stat('Order remaining', '${_toInt(item['quantity_remaining'])}'),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<int?>(
                valueListenable: selectedLocation,
                builder: (_, value, __) => DropdownButtonFormField<int>(
                  value: _safeNullableInt(value, locationIds),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Receiving location'),
                  items: locations.map((row) => DropdownMenuItem<int>(value: row.id, child: Text('${row.name} (${row.type})'))).toList(),
                  onChanged: (v) => selectedLocation.value = v,
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: sellCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price')),
              const SizedBox(height: 8),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity goods to receive')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || selectedLocation.value == null) return;
    final quantityReceived = _toInt(qtyCtrl.text);
    final remaining = _toInt(item['quantity_remaining']);
    if (quantityReceived <= 0) {
      _showMessage('Enter the quantity received.', error: true);
      return;
    }
    if (quantityReceived > remaining) {
      _showMessage('You cannot receive more than the remaining order quantity.', error: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Receiving'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${order['order_number'] ?? 'Bale Order'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('${item['product_name'] ?? '-'} - ${item['category_name'] ?? '-'}'),
              const SizedBox(height: 6),
              Text('Receive: $quantityReceived'),
              const SizedBox(height: 6),
              Text('Into: ${locations.firstWhere((row) => row.id == selectedLocation.value).name}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.receiveBaleOrderItem(
        _toInt(item['id']),
        locationId: selectedLocation.value!,
        quantityReceived: quantityReceived,
        sellPrice: _toDouble(sellCtrl.text),
        receivedByName: widget.appState.user?.name ?? '',
      );
      if (!mounted) return;
      _showMessage('Order received');
      await _load();
    } catch (e) {
      _showMessage(e, error: true);
    }
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF7F2EF), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _tabList(List<Widget> children) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: children),
      );

  String _joinedMeta(List<dynamic> values) => values.map((value) => (value ?? '').toString().trim()).where((value) => value.isNotEmpty).join(' - ');

  String _formatDateTime(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '-';
    return text.length >= 16 ? text.substring(0, 16) : text;
  }

  String _gradeLabel(Map<String, dynamic> row) {
    final grade = _toInt(row['bale_grade']) > 0 ? _toInt(row['bale_grade']) : _toInt(row['grade']);
    return grade > 0 ? 'Grade $grade' : '-';
  }

  String _unitLabel(Map<String, dynamic> row) {
    final qty = _toDouble(row['bale_unit_quantity']) > 0
        ? _toDouble(row['bale_unit_quantity'])
        : _toDouble(row['unit_quantity']);
    final unit = ((row['bale_unit_of_measure'] ?? row['unit_of_measure'] ?? '').toString()).trim().toUpperCase();
    if (qty <= 0 || unit.isEmpty) return '-';
    final qtyText = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
    return '$qtyText $unit';
  }

  Widget _orderedView(List<Map<String, dynamic>> rows) {
    if (_loading && _bundle == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return const MobileEmptyState(icon: Icons.assignment_outlined, title: 'No ordered bales', message: 'Ordered bale records will appear here.');
    }
    return _tabList(
      rows
          .map(
            (row) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${row['order_number'] ?? 'Order'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      _joinedMeta([
                        row['product_names'],
                        row['category_names'],
                        row['grade_names'],
                      ]),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        MobileLabelValue(label: 'Ordered by', value: (row['ordered_by_name'] ?? '-').toString()),
                        MobileLabelValue(label: 'To be received by', value: (row['received_by_name'] ?? '-').toString()),
                        MobileLabelValue(label: 'Ordered qty', value: '${_toInt(row['quantity_ordered'])}'),
                        MobileLabelValue(label: 'Received qty', value: '${_toInt(row['quantity_received'])}'),
                        MobileLabelValue(label: 'Remaining', value: '${_toInt(row['quantity_ordered']) - _toInt(row['quantity_received'])}'),
                        MobileLabelValue(label: 'Date', value: _formatDateTime(row['order_date'])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(onPressed: () => _openOrder(row), child: const Text('View')),
                        if (_toInt(row['quantity_ordered']) > _toInt(row['quantity_received']))
                          FilledButton(
                            onPressed: () => _openReceiveFromOrdered(row),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
                            child: const Text('Receive'),
                          ),
                        OutlinedButton(onPressed: () => _editOrder(row), child: const Text('Edit')),
                        OutlinedButton(onPressed: () => _deleteOrder(row), child: const Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _receivedView(List<Map<String, dynamic>> rows) {
    if (_loading && _bundle == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return const MobileEmptyState(icon: Icons.inventory_2_outlined, title: 'No received bales', message: 'Received bale records will appear here.');
    }
    return _tabList(
      rows
          .map(
            (row) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${row['receipt_number'] ?? row['bale_code'] ?? 'Received Bale'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      _joinedMeta([
                        row['order_number'],
                        row['product_name'],
                        row['category_name'],
                        row['label_name'],
                        _gradeLabel(row),
                        _unitLabel(row),
                      ]),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        MobileLabelValue(label: 'Ordered by', value: (row['ordered_by_name'] ?? '-').toString()),
                        MobileLabelValue(label: 'Received by', value: (row['received_by_name'] ?? '-').toString()),
                        MobileLabelValue(label: 'Received location', value: (row['received_location_name'] ?? '-').toString()),
                        MobileLabelValue(label: 'Qty received', value: '${_toInt(row['quantity_received'])}'),
                        MobileLabelValue(label: 'Received date', value: _formatDateTime(row['received_at'] ?? row['updated_at'])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_toInt(row['order_id']) > 0) OutlinedButton(onPressed: () => _openOrder({'id': row['order_id']}), child: const Text('View Order')),
                        OutlinedButton(onPressed: () => _reverseBale(row), child: const Text('Reverse Bale')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _singleTransferView(List<Map<String, dynamic>> rows) {
    if (_loading && _bundle == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return const MobileEmptyState(icon: Icons.swap_horiz_outlined, title: 'No bale transfers', message: 'Single-transfer history will appear here.');
    }
    return _tabList(
      rows
          .map(
            (row) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stats = [
                      MobileLabelValue(label: 'Current stock', value: '${row['bale_count'] ?? 0} bale(s)'),
                      MobileLabelValue(label: 'Created', value: (row['created_at'] ?? '-').toString()),
                      MobileLabelValue(label: 'Updated', value: (row['updated_at'] ?? '-').toString()),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['from_name'] ?? ''} -> ${row['to_name'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        if (constraints.maxWidth < 470)
                          Column(children: stats.map((widget) => Padding(padding: const EdgeInsets.only(bottom: 10), child: widget)).toList())
                        else
                          Wrap(spacing: 18, runSpacing: 12, children: stats),
                      ],
                    );
                  },
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _warehouseView(List<Map<String, dynamic>> warehouses, int grandWarehouseStock) {
    return _tabList([
      MobileSectionCard(
        icon: Icons.warehouse_rounded,
        title: 'Warehouse Transfer and History',
        subtitle: '${warehouses.length} warehouses - Grand total stock $grandWarehouseStock',
        child: Column(
          children: warehouses.isEmpty
              ? [const Text('No warehouses found.')]
              : warehouses
                  .map(
                    (row) => MobileActionTile(
                      icon: Icons.home_work_rounded,
                      title: (row['name'] ?? '').toString(),
                      subtitle: _joinedMeta([
                        'Total stock ${_toInt(row['total_stock'])}',
                        'Products ${_toInt(row['stocked_products'])}',
                        if ((row['updated_at'] ?? '').toString().trim().isNotEmpty)
                          'Updated ${_formatDateTime(row['updated_at'])}',
                      ]),
                    ),
                  )
                  .toList(),
        ),
      ),
    ]);
  }

  void _clearFilters() {
    setState(() {
      _categoryId = null;
      _grade = null;
      _dateRange = null;
      _searchCtrl.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _rows(_bundle?['categories']);
    final ordered = _rows(_bundle?['ordered_bales'])
        .where((row) => _toInt(row['quantity_ordered']) > _toInt(row['quantity_received']))
        .toList();
    final received = _rows(_bundle?['received_bales']);
    final transfers = _rows(_bundle?['transfers']);
    final warehouses = _rows(_bundle?['warehouses']);
    final grandWarehouseStock = _toInt(_bundle?['grand_warehouse_stock']);
    final hasFilters = _categoryId != null || _grade != null || _dateRange != null || _searchCtrl.text.trim().isNotEmpty;

    return MobilePageScaffold(
      title: 'Bale Movement',
      subtitle: 'Track ordered, received, and transferred bales.',
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  if (_error != null && _bundle != null) ...[
                    MobileSectionCard(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could Not Refresh Bale Movement',
                      subtitle: _error!,
                      accentColor: const Color(0xFFE31B23),
                      trailing: TextButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Refresh'),
                      ),
                      child: const Text(
                        'Check the connection, then tap refresh to try again.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  MobileSectionCard(
                    icon: Icons.filter_alt_rounded,
                    title: 'Search & Filters',
                    trailing: IconButton(
                      onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
                      icon: Icon(_filtersExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    ),
                    child: Column(
                      children: [
                        if (_filtersExpanded) ...[
                          MobileSearchField(
                            controller: _searchCtrl,
                            hintText: 'Search bale, order, label, location',
                            onSearch: _load,
                            onChanged: (_) {},
                            onSubmitted: (_) => _load(),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final categoryField = DropdownButtonFormField<int?>(
                                value: _categoryId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Category'),
                                items: [
                                  const DropdownMenuItem<int?>(value: null, child: Text('All categories')),
                                  ...categories.map((row) => DropdownMenuItem<int?>(value: _toInt(row['id']), child: Text((row['name'] ?? '').toString()))),
                                ],
                                onChanged: (value) {
                                  setState(() => _categoryId = value);
                                  _load();
                                },
                              );
                              final gradeField = DropdownButtonFormField<int?>(
                                value: _grade,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Grade'),
                                items: const [
                                  DropdownMenuItem<int?>(value: null, child: Text('All grades')),
                                  DropdownMenuItem<int?>(value: 1, child: Text('Grade 1')),
                                  DropdownMenuItem<int?>(value: 2, child: Text('Grade 2')),
                                  DropdownMenuItem<int?>(value: 3, child: Text('Grade 3')),
                                  DropdownMenuItem<int?>(value: 4, child: Text('Grade 4')),
                                  DropdownMenuItem<int?>(value: 5, child: Text('Grade 5')),
                                ],
                                onChanged: (value) {
                                  setState(() => _grade = value);
                                  _load();
                                },
                              );
                              if (constraints.maxWidth < 520) {
                                return Column(children: [categoryField, const SizedBox(height: 12), gradeField]);
                              }
                              return Row(children: [Expanded(flex: 7, child: categoryField), const SizedBox(width: 12), Expanded(flex: 3, child: gradeField)]);
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickDateRange,
                                  icon: const Icon(Icons.date_range_rounded),
                                  label: Text(
                                    _dateRange == null ? 'Any date range' : '${_dateFmt.format(_dateRange!.start)} to ${_dateFmt.format(_dateRange!.end)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (hasFilters) ...[
                                const SizedBox(width: 8),
                                TextButton(onPressed: _clearFilters, child: const Text('Clear')),
                              ],
                            ],
                          ),
                        ] else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                MobileMetricChip(
                                  _searchCtrl.text.trim().isEmpty
                                      ? 'Search: all'
                                      : 'Search active',
                                ),
                                MobileMetricChip(_categoryId == null ? 'Category: all' : 'Category set'),
                                MobileMetricChip(_dateRange == null ? 'Date: all' : 'Date range set'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: const TabBar(
                      isScrollable: true,
                      labelColor: Color(0xFFE31B23),
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: Color(0xFFE31B23),
                      tabs: [
                        Tab(text: 'Ordered Bales'),
                        Tab(text: 'Received Bales'),
                        Tab(text: 'Single Transfer & History'),
                        Tab(text: 'Warehouse Transfer & History'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_loading && _bundle != null) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LinearProgressIndicator()),
            Expanded(
              child: _error != null && _bundle == null
                  ? MobileRetryState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Bale Movement Is Offline Right Now',
                      message: _error!,
                      onRetry: _load,
                    )
                  : TabBarView(
                      children: [
                        _orderedView(ordered),
                        _receivedView(received),
                        _singleTransferView(transfers),
                        _warehouseView(warehouses, grandWarehouseStock),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
