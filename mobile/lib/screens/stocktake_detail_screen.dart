import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../services/pdf_export_service.dart';
import '../widgets/mobile_ui.dart';

class StockTakeDetailScreen extends StatefulWidget {
  final AppState appState;
  final int stockTakeId;
  const StockTakeDetailScreen({
    super.key,
    required this.appState,
    required this.stockTakeId,
  });

  @override
  State<StockTakeDetailScreen> createState() => _StockTakeDetailScreenState();
}

class _StockTakeDetailScreenState extends State<StockTakeDetailScreen> {
  bool _loading = false;
  Map<String, dynamic>? _stocktake;
  List<Map<String, dynamic>> _items = [];
  final Map<int, TextEditingController> _ctrl = {};
  String _filter = '';
  final _pdfExporter = PdfExportService();

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;

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
    for (final controller in _ctrl.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getStockTake(widget.stockTakeId);
      _stocktake = Map<String, dynamic>.from(data['stocktake'] as Map);
      _items = (data['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final controller in _ctrl.values) {
        controller.dispose();
      }
      _ctrl.clear();
      for (final item in _items) {
        final pid = _toInt(item['product_id']);
        _ctrl[pid] = TextEditingController(
          text: item['counted_qty'] == null ? '' : item['counted_qty'].toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _enteredCount {
    var count = 0;
    for (final item in _items) {
      final pid = _toInt(item['product_id']);
      final value = _ctrl[pid]?.text.trim() ?? '';
      if (value.isNotEmpty) count++;
    }
    return count;
  }

  Future<void> _finalize() async {
    final itemsPayload = <Map<String, dynamic>>[];
    for (final item in _items) {
      final pid = _toInt(item['product_id']);
      final txt = _ctrl[pid]?.text.trim() ?? '';
      if (txt.isEmpty) continue;
      final qty = int.tryParse(txt);
      if (qty == null) continue;
      itemsPayload.add({'product_id': pid, 'counted_qty': qty});
    }
    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No counted quantities entered.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalize Stock Take'),
        content: const Text(
          'This will adjust stock to match counted quantities. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
            ),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await api.finalizeStockTake(widget.stockTakeId, itemsPayload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock take finalized.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finalize failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return;
    setState(() => _loading = true);
    try {
      final data = await api.getStockTakeReport(widget.stockTakeId);
      final path = await _pdfExporter.saveStockTakeReportPdf(
        tenant: tenant,
        stockTake: Map<String, dynamic>.from(data['stock_take'] as Map),
        summary: Map<String, dynamic>.from(data['summary'] as Map),
        rows: (data['rows'] as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Completed stock take report #${widget.stockTakeId}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export stock take PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stocktake = _stocktake;
    final locName = stocktake?['location_name']?.toString() ?? '';
    final status = stocktake?['status']?.toString() ?? '';

    final filtered = _filter.isEmpty
        ? _items
        : _items
            .where(
              (item) => (item['product_name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(_filter.toLowerCase()),
            )
            .toList();

    return MobilePageScaffold(
      title: 'Stock Take #${widget.stockTakeId}',
      subtitle: 'Capture counted quantities and finalize the stock adjustment once you finish.',
      actions: [
        if (status == 'FINALIZED')
          IconButton(
            onPressed: _loading ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            tooltip: 'Export PDF',
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (stocktake != null) ...[
            MobileSectionCard(
              icon: Icons.fact_check_rounded,
              title: locName,
              subtitle: 'Stock take summary',
              trailing: status == 'IN_PROGRESS'
                  ? const MobileStatusBadge(
                      label: 'In progress',
                      backgroundColor: Color(0xFFFFF3E0),
                      foregroundColor: Color(0xFFEF6C00),
                    )
                  : const MobileStatusBadge(
                      label: 'Finalized',
                      backgroundColor: Color(0xFFE8F5E9),
                      foregroundColor: Color(0xFF2E7D32),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: MobileLabelValue(
                      label: 'Entered',
                      value: '$_enteredCount / ${_items.length}',
                    ),
                  ),
                  Expanded(
                    child: MobileLabelValue(
                      label: 'Status',
                      value: status,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          MobileSectionCard(
            icon: Icons.search_rounded,
            title: 'Find Product',
            subtitle: 'Search within this stock take by product name',
            child: TextField(
              decoration: const InputDecoration(labelText: 'Search product'),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const MobileEmptyState(
              icon: Icons.inventory_outlined,
              title: 'No matching items',
              message: 'Try another search term or continue entering counts.',
            )
          else
            ...filtered.map(
              (item) {
                final pid = _toInt(item['product_id']);
                final name = (item['product_name'] ?? '').toString();
                final systemQty = _toInt(item['system_qty']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
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
                                label: 'System Qty',
                                value: '$systemQty',
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _ctrl[pid],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Counted Qty',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (status == 'IN_PROGRESS') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _finalize,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFE31B23),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Finalize Stock Take'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
