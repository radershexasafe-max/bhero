import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class RefundScreen extends StatefulWidget {
  final AppState appState;
  const RefundScreen({super.key, required this.appState});

  @override
  State<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends State<RefundScreen> {
  final _saleNumberCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  Timer? _lookupDebounce;
  bool _loading = false;
  String? _error;

  SaleDetail? _sale;
  final Map<int, int> _refundQtys = {};
  List<Refund> _refunds = [];
  bool _historyLoaded = false;

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _saleNumberCtrl.addListener(_handleSaleSearchChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _saleNumberCtrl.removeListener(_handleSaleSearchChanged);
    _saleNumberCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _handleSaleSearchChanged() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _lookupSale(fromTyping: true),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final list = await _api.getRefunds();
      if (!mounted) return;
      setState(() {
        _refunds = list;
        _historyLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  Future<void> _lookupSale({bool fromTyping = false}) async {
    final saleNum = _saleNumberCtrl.text.trim();
    if (saleNum.isEmpty) {
      setState(() {
        _error = fromTyping ? null : 'Enter a sale number.';
        _sale = null;
        _refundQtys.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _sale = null;
      _refundQtys.clear();
    });
    try {
      final sale = await _api.lookupSale(saleNumber: saleNum);
      setState(() => _sale = sale);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _refundTotal {
    if (_sale == null) return 0;
    double total = 0;
    for (final item in _sale!.items) {
      final qty = _refundQtys[item.id] ?? 0;
      if (qty > 0) total += qty * item.unitPrice;
    }
    return total;
  }

  Future<void> _processRefund() async {
    if (_sale == null) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Please enter a reason for the refund.');
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final item in _sale!.items) {
      final qty = _refundQtys[item.id] ?? 0;
      if (qty > 0) {
        items.add({'sale_item_id': item.id, 'qty': qty});
      }
    }

    if (items.isEmpty) {
      setState(() => _error = 'Select at least one item to refund.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.processRefund(
        saleId: _sale!.id,
        reason: reason,
        items: items,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund processed successfully.')),
      );
      setState(() {
        _sale = null;
        _refundQtys.clear();
        _reasonCtrl.clear();
        _saleNumberCtrl.clear();
      });
      _loadHistory();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Refunds',
      subtitle: 'Look up completed sales, issue refunds, and keep the refund history tidy.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.receipt_long_rounded,
            title: 'Lookup Sale',
            subtitle: 'Enter the sale number before selecting items to refund',
            trailing: IconButton(
              onPressed: _loading ? null : _loadHistory,
              icon: const Icon(Icons.refresh_rounded),
            ),
            child: Column(
              children: [
                MobileSearchField(
                  controller: _saleNumberCtrl,
                  hintText: 'Enter sale number',
                  onSearch: _lookupSale,
                  onChanged: (_) {},
                  onSubmitted: (_) => _lookupSale(),
                ),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
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
          if (_sale != null) ...[
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.undo_rounded,
              title: 'Refund Draft',
              subtitle: 'Select quantities and capture the reason for this refund',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 160,
                        child: MobileStatCard(
                          title: 'Sale Number',
                          value: _sale!.saleNumber,
                          icon: Icons.pin_rounded,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: MobileStatCard(
                          title: 'Sale Total',
                          value: _sale!.total.toStringAsFixed(2),
                          icon: Icons.payments_rounded,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: MobileStatCard(
                          title: 'Refund Total',
                          value: _refundTotal.toStringAsFixed(2),
                          icon: Icons.reply_all_rounded,
                          accent: const Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sale!.locationName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${_sale!.createdAt} - Cashier: ${_sale!.cashierName}'),
                          if (_sale!.discountAmount > 0) ...[
                            const SizedBox(height: 6),
                            Text('Discount used: ${_sale!.discountAmount.toStringAsFixed(2)}'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._sale!.items.map(
                    (item) {
                      final available = item.availableForRefund;
                      final refundQty = _refundQtys[item.id] ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: MobileLabelValue(label: 'Sold Qty', value: '${item.qty}')),
                                  Expanded(child: MobileLabelValue(label: 'Refunded', value: '${item.refundedQty}')),
                                  Expanded(child: MobileLabelValue(label: 'Unit Price', value: item.unitPrice.toStringAsFixed(2))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (available > 0)
                                TextFormField(
                                  initialValue: refundQty.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Refund quantity',
                                    hintText: '0-$available',
                                  ),
                                  onChanged: (v) {
                                    var n = int.tryParse(v) ?? 0;
                                    if (n < 0) n = 0;
                                    if (n > available) n = available;
                                    setState(() => _refundQtys[item.id] = n);
                                  },
                                )
                              else
                                const MobileStatusBadge(
                                  label: 'Fully refunded',
                                  backgroundColor: Color(0xFFF3F4F6),
                                  foregroundColor: Color(0xFF6B7280),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  TextField(
                    controller: _reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason for refund',
                      hintText: 'e.g. Customer returned damaged bale',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading || _refundTotal <= 0 ? null : _processRefund,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFE31B23),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.undo_rounded),
                      label: Text('Process Refund (${_refundTotal.toStringAsFixed(2)})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          MobileSectionCard(
            icon: Icons.history_rounded,
            title: 'Recent Refunds',
            subtitle: 'Latest processed refund records',
            child: !_historyLoaded
                ? const Center(child: CircularProgressIndicator())
                : _refunds.isEmpty
                    ? const MobileEmptyState(
                        icon: Icons.undo_outlined,
                        title: 'No refunds yet',
                        message: 'Processed refunds will appear here.',
                      )
                    : Column(
                        children: _refunds
                            .map(
                              (refund) => MobileActionTile(
                                icon: Icons.reply_all_rounded,
                                title: '${refund.refundNumber} - Sale ${refund.saleNumber ?? '-'}',
                                subtitle: [
                                  refund.locationName,
                                  refund.createdAt,
                                  'Items: ${refund.itemCount}',
                                  'Total: ${refund.totalAmount.toStringAsFixed(2)}',
                                  if ((refund.reason ?? '').isNotEmpty) 'Reason: ${refund.reason}',
                                ].join(' - '),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      refund.totalAmount.toStringAsFixed(2),
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      refund.refundedBy,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }
}
