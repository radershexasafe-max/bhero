import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';
import 'transfer_detail_screen.dart';

class TransfersScreen extends StatefulWidget {
  final AppState appState;
  const TransfersScreen({super.key, required this.appState});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  bool _loading = false;
  String _status = '';
  List<Transfer> _rows = [];

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFC62828) : null,
        ),
      );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await api.getTransfers(status: _status.isEmpty ? null : _status);
    } catch (e) {
      _showMessage(ApiClient.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateTransfer() async {
    final accessibleLocations = <Location>[];
    final seenLocationIds = <int>{};
    for (final location in widget.appState.accessibleLocations) {
      if (seenLocationIds.add(location.id)) {
        accessibleLocations.add(location);
      }
    }
    final initialFromLocation = accessibleLocations.any((location) => location.id == widget.appState.defaultLocationId)
        ? widget.appState.defaultLocationId
        : (accessibleLocations.isEmpty ? null : accessibleLocations.first.id);
    final fromLocation = ValueNotifier<int?>(initialFromLocation);
    final toLocation = ValueNotifier<int?>(null);
    final productId = ValueNotifier<int?>(null);
    final qtyCtrl = TextEditingController();
    bool saving = false;
    bool initialized = false;
    bool stockLoading = false;
    List<StockRow> stockRows = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> loadStock() async {
            final locId = fromLocation.value ?? 0;
            if (locId <= 0) {
              setModalState(() {
                stockRows = [];
                productId.value = null;
              });
              return;
            }
            setModalState(() => stockLoading = true);
            try {
              final rows = await api.getStock(locationId: locId);
              final deduped = <int, StockRow>{};
              for (final row in rows.where((entry) => entry.onHand > 0)) {
                deduped.putIfAbsent(row.productId, () => row);
              }
              stockRows = deduped.values.toList();
              if (productId.value != null && !stockRows.any((row) => row.productId == productId.value)) {
                productId.value = null;
              }
              if (toLocation.value != null && toLocation.value == fromLocation.value) {
                toLocation.value = null;
              }
            } catch (e) {
              stockRows = [];
              _showMessage(
                'Could not load source stock: ${ApiClient.friendlyError(e)}',
                error: true,
              );
            } finally {
              if (ctx.mounted) {
                setModalState(() => stockLoading = false);
              }
            }
          }

          if (!initialized) {
            initialized = true;
            Future.microtask(() => loadStock());
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Move Stock Between Locations'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accessibleLocations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('No stores are assigned to this user yet.'),
                    ),
                  ValueListenableBuilder<int?>(
                    valueListenable: fromLocation,
                    builder: (_, value, __) {
                      final safeValue = accessibleLocations.any((location) => location.id == value) ? value : null;
                      return DropdownButtonFormField<int>(
                        value: safeValue,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'From location'),
                        items: accessibleLocations
                            .map(
                              (location) => DropdownMenuItem<int>(
                                value: location.id,
                                child: Text('${location.name} (${location.type})'),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (v) {
                                fromLocation.value = v;
                                loadStock();
                              },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int?>(
                    valueListenable: toLocation,
                    builder: (_, value, __) {
                      final toLocations = accessibleLocations
                          .where((location) => location.id != fromLocation.value)
                          .toList();
                      final safeValue = toLocations.any((location) => location.id == value) ? value : null;
                      return DropdownButtonFormField<int>(
                        value: safeValue,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'To location'),
                        items: toLocations
                            .map(
                              (location) => DropdownMenuItem<int>(
                                value: location.id,
                                child: Text('${location.name} (${location.type})'),
                              ),
                            )
                            .toList(),
                        onChanged: saving ? null : (v) => toLocation.value = v,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int?>(
                    valueListenable: productId,
                    builder: (_, value, __) {
                      final safeValue = stockRows.any((row) => row.productId == value) ? value : null;
                      return DropdownButtonFormField<int>(
                        value: safeValue,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Bale item'),
                        items: stockRows
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: row.productId,
                                child: Text('${row.name} (Stock ${row.onHand})'),
                              ),
                            )
                            .toList(),
                        onChanged: saving ? null : (v) => productId.value = v,
                      );
                    },
                  ),
                  if (stockLoading) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity to move'),
                  ),
                  if (saving) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
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
                        if (fromLocation.value == null || toLocation.value == null || productId.value == null) {
                          _showMessage('Choose the source, destination, and bale item.', error: true);
                          return;
                        }
                        final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                        if (qty <= 0) {
                          _showMessage('Enter a quantity to move.', error: true);
                          return;
                        }
                        setModalState(() => saving = true);
                        try {
                          await api.createTransfer(
                            fromLocationId: fromLocation.value!,
                            toLocationId: toLocation.value!,
                            items: [
                              {'product_id': productId.value, 'qty_sent': qty},
                            ],
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, true);
                        } catch (e) {
                          setModalState(() => saving = false);
                          _showMessage(ApiClient.friendlyError(e), error: true);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE31B23),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      _showMessage('Transfer created');
      await _load();
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

  Future<void> _openTransfer(Transfer transfer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferDetailScreen(
          appState: widget.appState,
          transferId: transfer.id,
        ),
      ),
    );
    _load();
  }

  String _nextActionLabel(String status) {
    switch (status) {
      case 'DRAFT':
        return 'Dispatch';
      case 'DISPATCHED':
        return 'Receive';
      default:
        return 'View';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Transfers',
      subtitle: 'Track bale movement and move stock between locations.',
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _openCreateTransfer,
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        child: const Icon(Icons.compare_arrows_rounded),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileSectionCard(
              icon: Icons.filter_alt_rounded,
              title: 'Transfer Filter',
              subtitle: 'Draft -> Dispatched -> Received',
              trailing: IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Filter status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                  DropdownMenuItem(
                    value: 'DISPATCHED',
                    child: Text('Dispatched'),
                  ),
                  DropdownMenuItem(value: 'RECEIVED', child: Text('Received')),
                ],
                onChanged: (v) {
                  setState(() => _status = v ?? '');
                  _load();
                },
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Transfers: ${_rows.length}'),
                MobileMetricChip(
                  _status.isEmpty ? 'Showing all statuses' : 'Status: $_status',
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
                icon: Icons.compare_arrows_outlined,
                title: 'No transfers found',
                message: 'Transfers matching this filter will appear here.',
              )
            else
              ..._rows.map(
                (transfer) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await _openTransfer(transfer);
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
                                      'Transfer #${transfer.id}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${transfer.fromName} -> ${transfer.toName}'),
                                  ],
                                ),
                              ),
                              _badgeFor(transfer.status),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: MobileLabelValue(
                                  label: 'Created',
                                  value: transfer.createdAt,
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: _loading ? null : () => _openTransfer(transfer),
                                child: Text(_nextActionLabel(transfer.status)),
                              ),
                            ],
                          ),
                        ],
                      ),
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
