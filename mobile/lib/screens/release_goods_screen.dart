import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class ReleaseGoodsScreen extends StatefulWidget {
  final AppState appState;
  const ReleaseGoodsScreen({super.key, required this.appState});

  @override
  State<ReleaseGoodsScreen> createState() => _ReleaseGoodsScreenState();
}

class _ReleaseGoodsScreenState extends State<ReleaseGoodsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  ApiClient get _api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

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
  String _money(dynamic value) => _toDouble(value).toStringAsFixed(0);
  String _trimmed(dynamic value) => (value ?? '').toString().trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getReleaseGoods(search: _searchCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _rows = ((data['rows'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.friendlyError(
          e,
          fallback: 'Check your internet connection and tap Reload to try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _collect(Map<String, dynamic> row) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Goods'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _trimmed(row['sale_number']).isEmpty ? 'Pending collection' : _trimmed(row['sale_number']),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(_trimmed(row['customer_name']).isEmpty ? 'Walk-in customer' : _trimmed(row['customer_name'])),
              const SizedBox(height: 4),
              Text('Total: ${_money(row['total'])}'),
              const SizedBox(height: 4),
              Text('Paid: ${_money(row['amount_paid'])}'),
              const SizedBox(height: 4),
              Text('Balance: ${_money(row['balance_due'])}'),
              const SizedBox(height: 14),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Collection note (optional)',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to mark these goods as collected?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.collectReleaseGoods(
        saleId: _toInt(row['id']),
        note: noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goods released successfully.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPending = _rows.length;
    final totalValue = _rows.fold<double>(0, (sum, row) => sum + _toDouble(row['total']));

    return MobilePageScaffold(
      title: 'Release Goods',
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MobileSearchField(
                controller: _searchCtrl,
                hintText: 'Search sale number, customer, phone, or item',
                onSearch: _load,
                onChanged: (_) {},
                onSubmitted: (_) => _load(),
                showActionButton: false,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MobileMetricChip('Pending: $totalPending'),
              MobileMetricChip('Value: ${totalValue.toStringAsFixed(0)}'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            MobileRetryState(
              icon: Icons.wifi_off_rounded,
              title: 'Could Not Load Release Goods',
              message: _error!,
              onRetry: _load,
            )
          else if (_rows.isEmpty)
            const MobileEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No pending collections',
              message: 'Paid or credited sales waiting for collection will appear here.',
            )
          else
            ..._rows.map((row) {
              final items = ((row['items'] as List?) ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              final customerName = _trimmed(row['customer_name']).isEmpty
                  ? 'Walk-in customer'
                  : _trimmed(row['customer_name']);
              final phone = _trimmed(row['customer_phone']);
              final paymentStatus = _trimmed(row['payment_status']).isEmpty
                  ? '-'
                  : _trimmed(row['payment_status']);
              return MobileSectionCard(
                icon: Icons.local_shipping_outlined,
                title: _trimmed(row['sale_number']).isEmpty
                    ? 'Pending collection'
                    : _trimmed(row['sale_number']),
                trailing: FilledButton.tonal(
                  onPressed: () => _collect(row),
                  child: const Text('Release'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phone.isEmpty ? customerName : '$customerName | $phone',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Total', value: _money(row['total']))),
                        Expanded(child: MobileLabelValue(label: 'Paid', value: _money(row['amount_paid']))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Balance', value: _money(row['balance_due']))),
                        Expanded(child: MobileLabelValue(label: 'Payment', value: paymentStatus)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Shop', value: _trimmed(row['location_name']).isEmpty ? '-' : _trimmed(row['location_name']))),
                        Expanded(child: MobileLabelValue(label: 'Sold by', value: _trimmed(row['salesperson_name']).isEmpty ? '-' : _trimmed(row['salesperson_name']))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    MobileLabelValue(
                      label: 'Date',
                      value: _trimmed(row['created_at']).isEmpty ? '-' : _trimmed(row['created_at']),
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Items',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${_trimmed(item['product_name']).isEmpty ? 'Item' : _trimmed(item['product_name'])} | ${_toInt(item['qty'])} x ${_money(item['unit_price'])}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
