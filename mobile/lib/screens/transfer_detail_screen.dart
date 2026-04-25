import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class TransferDetailScreen extends StatefulWidget {
  final AppState appState;
  final int transferId;
  const TransferDetailScreen({
    super.key,
    required this.appState,
    required this.transferId,
  });

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  bool _loading = false;
  Transfer? _transfer;
  List<TransferItem> _items = [];
  final Map<int, TextEditingController> _controllers = {};

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await api.getTransfer(widget.transferId);
      _transfer = res.transfer;
      _items = res.items;
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      for (final item in _items) {
        _controllers[item.productId] = TextEditingController(
          text: item.qtySent.toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dispatch() async {
    setState(() => _loading = true);
    try {
      await api.dispatchTransfer(widget.transferId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer dispatched.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receive() async {
    final payloadItems = <Map<String, dynamic>>[];
    for (final item in _items) {
      final txt = _controllers[item.productId]?.text ?? '0';
      final qty = int.tryParse(txt) ?? 0;
      payloadItems.add({
        'product_id': item.productId,
        'qty_received': qty,
      });
    }
    setState(() => _loading = true);
    try {
      await api.receiveTransfer(widget.transferId, payloadItems);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer received.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  MobileStatusBadge _badgeFor(String status) {
    switch (status) {
      case 'DISPATCHED':
        return const MobileStatusBadge(
          label: 'Dispatched',
          backgroundColor: Color(0xFFFFF3E0),
          foregroundColor: Color(0xFFEF6C00),
        );
      case 'RECEIVED':
        return const MobileStatusBadge(
          label: 'Received',
          backgroundColor: Color(0xFFE8F5E9),
          foregroundColor: Color(0xFF2E7D32),
        );
      default:
        return const MobileStatusBadge(
          label: 'Draft',
          backgroundColor: Color(0xFFFFEBEE),
          foregroundColor: Color(0xFFC62828),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;

    return MobilePageScaffold(
      title: 'Transfer #${widget.transferId}',
      subtitle: 'Review bale quantities and move the transfer from draft to dispatched to received.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (transfer != null) ...[
            MobileSectionCard(
              icon: Icons.compare_arrows_rounded,
              title: '${transfer.fromName} -> ${transfer.toName}',
              subtitle: 'Transfer overview',
              trailing: _badgeFor(transfer.status),
              child: Row(
                children: [
                  Expanded(
                    child: MobileLabelValue(
                      label: 'Created',
                      value: transfer.createdAt,
                    ),
                  ),
                  Expanded(
                    child: MobileLabelValue(
                      label: 'Status',
                      value: transfer.status,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          MobileSectionCard(
            icon: Icons.inventory_2_rounded,
            title: 'Transfer Items',
            subtitle: 'Adjust received quantities before finishing the transfer',
            child: _items.isEmpty
                ? const MobileEmptyState(
                    icon: Icons.inventory_outlined,
                    title: 'No transfer items found',
                    message: 'Items for this transfer will appear here.',
                  )
                : Column(
                    children: _items
                        .map(
                          (item) => Card(
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
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: MobileLabelValue(
                                          label: 'Sent',
                                          value: '${item.qtySent}',
                                        ),
                                      ),
                                      Expanded(
                                        child: MobileLabelValue(
                                          label: 'Received',
                                          value: '${item.qtyReceived}',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _controllers[item.productId],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Receive quantity',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (transfer != null) ...[
            const SizedBox(height: 16),
            if (transfer.status == 'DRAFT')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _dispatch,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFE31B23),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.local_shipping_rounded),
                  label: const Text('Dispatch Transfer'),
                ),
              ),
            if (transfer.status == 'DISPATCHED')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _receive,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFE31B23),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_rounded),
                  label: const Text('Receive Transfer'),
                ),
              ),
            if (transfer.status == 'RECEIVED')
              const MobileStatusBadge(
                label: 'Transfer completed',
                backgroundColor: Color(0xFFE8F5E9),
                foregroundColor: Color(0xFF2E7D32),
              ),
          ],
        ],
      ),
    );
  }
}
