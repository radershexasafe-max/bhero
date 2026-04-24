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
  bool _loading = true;
  Map<String, dynamic>? _data;
  final _searchCtrl = TextEditingController();

  ApiClient get _api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await _api.getPrepayments();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _release(Map row) async {
    final amount = TextEditingController(text: '${row['available_balance'] ?? row['amount'] ?? 0}');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Release Goods'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                readOnly: true,
                controller: TextEditingController(text: '${row['customer_name'] ?? '-'}'),
                decoration: const InputDecoration(labelText: 'Customer'),
              ),
              const SizedBox(height: 10),
              TextField(
                readOnly: true,
                controller: TextEditingController(text: '${row['available_balance'] ?? 0}'),
                decoration: const InputDecoration(labelText: 'Available balance'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount to release'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Release')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.releaseGoods(
        prepaymentId: int.tryParse('${row['id']}') ?? 0,
        amount: double.tryParse(amount.text.trim()) ?? 0,
        note: note.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goods released successfully.')));
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prepayments = (((_data?['prepayments'] as List?) ?? const [])).cast<Map>();
    final releases = (((_data?['releases'] as List?) ?? const [])).cast<Map>();
    final search = _searchCtrl.text.trim().toLowerCase();
    final available = prepayments.where((row) {
      final hasBalance = (double.tryParse('${row['available_balance'] ?? 0}') ?? 0) > 0;
      if (!hasBalance) return false;
      if (search.isEmpty) return true;
      final hay = '${row['customer_name'] ?? ''} ${row['location_name'] ?? ''} ${row['status'] ?? ''}'.toLowerCase();
      return hay.contains(search);
    }).toList();
    final filteredReleases = releases.where((row) {
      if (search.isEmpty) return true;
      final hay = '${row['customer_name'] ?? ''} ${row['location_name'] ?? ''} ${row['created_by_name'] ?? ''}'.toLowerCase();
      return hay.contains(search);
    }).toList();
    final availableTotal = available.fold<double>(
      0,
      (sum, row) => sum + (double.tryParse('${row['available_balance'] ?? 0}') ?? 0),
    );

    return MobilePageScaffold(
      title: 'Release Goods',
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MobileSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search release goods',
                  onSearch: () => setState(() {}),
                  onChanged: (_) => setState(() {}),
                  showActionButton: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Available: ${available.length}'),
                MobileMetricChip('Balance: ${availableTotal.toStringAsFixed(0)}'),
                MobileMetricChip('History: ${filteredReleases.length}'),
              ],
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.inventory_rounded,
              title: 'Available Prepayments',
              child: Column(
                children: available.isEmpty
                    ? [const Text('No available prepayments.')]
                    : available.map((row) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F6F3),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${row['customer_name'] ?? '-'}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: () => _release(row),
                                    child: const Text('Release Goods'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: MobileLabelValue(label: 'Total prepayment', value: '${row['amount'] ?? 0}')),
                                  Expanded(child: MobileLabelValue(label: 'Available', value: '${row['available_balance'] ?? 0}')),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: MobileLabelValue(label: 'Location', value: '${row['location_name'] ?? '-'}')),
                                  Expanded(child: MobileLabelValue(label: 'Status', value: '${row['status'] ?? '-'}')),
                                ],
                              ),
                            ],
                          ),
                        )).toList(),
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.history_rounded,
              title: 'Release History',
              child: Column(
                children: filteredReleases.isEmpty
                    ? [const Text('No release history yet.')]
                    : filteredReleases.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFFE31B23), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${row['customer_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${row['amount'] ?? 0} | ${row['location_name'] ?? '-'}'),
                                    Text('${row['created_at'] ?? '-'} | ${row['created_by_name'] ?? '-'}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
