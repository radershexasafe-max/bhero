import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../services/pdf_export_service.dart';
import '../widgets/mobile_ui.dart';
import 'stocktake_detail_screen.dart';

class StockTakeScreen extends StatefulWidget {
  final AppState appState;
  const StockTakeScreen({super.key, required this.appState});

  @override
  State<StockTakeScreen> createState() => _StockTakeScreenState();
}

class _StockTakeScreenState extends State<StockTakeScreen> {
  bool _loading = false;
  int? _locationId;
  List<Map<String, dynamic>> _stocktakes = [];

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;
  final _pdfExporter = PdfExportService();

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.defaultLocationId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stocktakes = await api.listStockTakes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final locId = _locationId;
    if (locId == null) return;
    setState(() => _loading = true);
    try {
      final id = await api.startStockTake(locId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockTakeDetailScreen(
            appState: widget.appState,
            stockTakeId: id,
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Start failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf(int stockTakeId) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return;
    setState(() => _loading = true);
    try {
      final data = await api.getStockTakeReport(stockTakeId);
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
        text: 'Completed stock take report #$stockTakeId',
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

  MobileStatusBadge _badgeFor(String status) {
    if (status == 'IN_PROGRESS') {
      return const MobileStatusBadge(
        label: 'In progress',
        backgroundColor: Color(0xFFFFF3E0),
        foregroundColor: Color(0xFFEF6C00),
      );
    }
    return const MobileStatusBadge(
      label: 'Finalized',
      backgroundColor: Color(0xFFE8F5E9),
      foregroundColor: Color(0xFF2E7D32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locations = widget.appState.accessibleLocations;
    final safeLocationId = locations.any((location) => location.id == _locationId) ? _locationId : null;
    final inProgressCount = _stocktakes
        .where((stocktake) => (stocktake['status'] ?? '') == 'IN_PROGRESS')
        .length;

    return MobilePageScaffold(
      title: 'Stock Take',
      subtitle: 'Start new counts, continue in-progress stock takes, and finalize adjustments cleanly.',
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileSectionCard(
              icon: Icons.playlist_add_check_rounded,
              title: 'Start Stock Take',
              subtitle: 'Choose the location you want to count',
              trailing: IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: safeLocationId,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location.id,
                            child: Text('${location.name} (${location.type})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _locationId = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _start,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE31B23),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Stock Take'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: MobileStatCard(
                    title: 'Total Sessions',
                    value: '${_stocktakes.length}',
                    icon: Icons.fact_check_rounded,
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: MobileStatCard(
                    title: 'In Progress',
                    value: '$inProgressCount',
                    icon: Icons.timelapse_rounded,
                    accent: const Color(0xFFEF6C00),
                  ),
                ),
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
            else if (_stocktakes.isEmpty)
              const MobileEmptyState(
                icon: Icons.fact_check_outlined,
                title: 'No stock takes yet',
                message: 'Start a stock take to begin counting bale quantities.',
              )
            else
              ..._stocktakes.map(
                (stocktake) {
                  final id = _toInt(stocktake['id']);
                  final status = (stocktake['status'] ?? '').toString();
                  final location = (stocktake['location_name'] ?? '').toString();
                  final started = (stocktake['started_at'] ?? '').toString();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StockTakeDetailScreen(
                              appState: widget.appState,
                              stockTakeId: id,
                            ),
                          ),
                        );
                        _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                                        'Stock Take #$id',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(location),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _badgeFor(status),
                                    if (status != 'IN_PROGRESS') ...[
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: _loading ? null : () => _exportPdf(id),
                                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                        label: const Text('PDF'),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            MobileLabelValue(
                              label: 'Started',
                              value: started,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
