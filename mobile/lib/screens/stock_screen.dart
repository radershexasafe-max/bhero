import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';
import 'stock_import_screen.dart';

class StockScreen extends StatefulWidget {
  final AppState appState;
  const StockScreen({super.key, required this.appState});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  int? _locationId;
  final _search = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = false;
  List<StockRow> _rows = [];
  bool _online = true;

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.defaultLocationId;
    _search.addListener(_handleSearchChanged);
    _refreshOnline();
    _load();
    Connectivity().onConnectivityChanged.listen((_) {
      _refreshOnline();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.removeListener(_handleSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  Future<void> _refreshOnline() async {
    final c = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _online = !c.contains(ConnectivityResult.none));
  }

  Future<void> _load() async {
    final locId = _locationId;
    if (locId == null) return;
    setState(() => _loading = true);
    try {
      if (!_online && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline: stock may be outdated.')),
        );
      }
      _rows = await api.getStock(
        locationId: locId,
        search: _search.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiClient.friendlyError(
              e,
              fallback: 'Could not load stock right now. Refresh to try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusBg(StockRow row) {
    if (row.onHand < 0) return const Color(0xFFFFEBEE);
    if (row.onHand <= row.reorderLevel) return const Color(0xFFFFF3E0);
    return const Color(0xFFE8F5E9);
  }

  Color _statusFg(StockRow row) {
    if (row.onHand < 0) return const Color(0xFFC62828);
    if (row.onHand <= row.reorderLevel) return const Color(0xFFEF6C00);
    return const Color(0xFF2E7D32);
  }

  String _statusLabel(StockRow row) {
    if (row.onHand < 0) return 'Negative';
    if (row.onHand <= row.reorderLevel) return 'Low';
    return 'OK';
  }

  @override
  Widget build(BuildContext context) {
    final locs = widget.appState.locations;
    final role = (widget.appState.user?.role ?? 'TELLER').toUpperCase();
    final canImport = role != 'TELLER';
    final lowCount = _rows.where((row) => row.onHand <= row.reorderLevel).length;
    final negativeCount = _rows.where((row) => row.onHand < 0).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileHeroCard(
            title: 'Stock',
            subtitle:
                'Check bale stock levels, switch locations, and watch low or negative stock before it causes trouble.',
            trailing: [
              MobileStatusBadge(
                label: _online ? 'Online' : 'Offline',
                backgroundColor:
                    _online ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                foregroundColor:
                    _online ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _locationId,
                          decoration: const InputDecoration(labelText: 'Location'),
                          items: locs
                              .map(
                                (l) => DropdownMenuItem(
                                  value: l.id,
                                  child: Text('${l.name} (${l.type})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() => _locationId = v);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MobileSearchField(
                    controller: _search,
                    hintText: 'Search bale stock',
                    onChanged: (_) {},
                    onSubmitted: (_) => _load(),
                    showPrefixIcon: false,
                    showActionButton: false,
                  ),
                  if (canImport) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockImportScreen(
                                appState: widget.appState,
                              ),
                            ),
                          );
                          if (context.mounted) _load();
                        },
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Open Stock Import'),
                      ),
                    ),
                  ],
                ],
              ),
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
                  title: 'Visible Rows',
                  value: '${_rows.length}',
                  icon: Icons.inventory_2_rounded,
                ),
              ),
              SizedBox(
                width: 160,
                child: MobileStatCard(
                  title: 'Low Stock',
                  value: '$lowCount',
                  icon: Icons.warning_amber_rounded,
                  accent: const Color(0xFFEF6C00),
                ),
              ),
              SizedBox(
                width: 160,
                child: MobileStatCard(
                  title: 'Negative',
                  value: '$negativeCount',
                  icon: Icons.trending_down_rounded,
                  accent: const Color(0xFFC62828),
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
          else if (_rows.isEmpty)
            const MobileEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No stock rows found',
              message: 'Try another search or switch to a different location.',
            )
          else
            ..._rows.map(
              (row) => Card(
                margin: const EdgeInsets.only(bottom: 12),
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
                                  row.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Barcode: ${(row.barcode ?? '').isEmpty ? '-' : row.barcode!}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          MobileStatusBadge(
                            label: _statusLabel(row),
                            backgroundColor: _statusBg(row),
                            foregroundColor: _statusFg(row),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: MobileLabelValue(
                              label: 'On Hand',
                              value: '${row.onHand}',
                            ),
                          ),
                          Expanded(
                            child: MobileLabelValue(
                              label: 'Reorder Level',
                              value: '${row.reorderLevel}',
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
    );
  }
}
