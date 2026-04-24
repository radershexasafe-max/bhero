import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class LocationManagementScreen extends StatefulWidget {
  final AppState appState;

  const LocationManagementScreen({super.key, required this.appState});

  @override
  State<LocationManagementScreen> createState() => _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';
  List<Location> _locations = [];

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    return ApiClient.friendlyError(
      error,
      fallback: 'Check your internet connection and tap Reload to try again.',
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.getLocations();
      if (!mounted) return;
      setState(() {
        _locations = rows;
      });
      widget.appState.locations = rows;
      widget.appState.notifyListeners();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openEditor([Location? location]) async {
    final nameCtrl = TextEditingController(text: location?.name ?? '');
    var type = (location?.type.isNotEmpty == true ? location!.type : 'SHOP').toUpperCase();
    var saving = false;
    String? dialogError;

    try {
      final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => StatefulBuilder(
          builder: (ctx, setSheetState) => FractionallySizedBox(
            heightFactor: 0.75,
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
                            location == null ? 'Add Store / Warehouse' : 'Edit Store / Warehouse',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 8),
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
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'Enter store or warehouse name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'SHOP', child: Text('Store / Shop')),
                        DropdownMenuItem(value: 'WAREHOUSE', child: Text('Warehouse')),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setSheetState(() => type = value ?? 'SHOP'),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (location != null) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final confirmed = await showMobileConfirmDialog(
                                        ctx,
                                        title: 'Delete ${location.type == 'WAREHOUSE' ? 'Warehouse' : 'Store'}',
                                        message: 'Delete ${location.name}?',
                                        confirmLabel: 'Delete',
                                        icon: Icons.delete_outline_rounded,
                                      );
                                      if (!confirmed) return;
                                      setSheetState(() {
                                        saving = true;
                                        dialogError = null;
                                      });
                                      try {
                                        await _api.deleteLocation(location.id);
                                        if (ctx.mounted) Navigator.pop(ctx, true);
                                      } catch (e) {
                                        setSheetState(() {
                                          saving = false;
                                          dialogError = _friendlyError(e);
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Delete'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) {
                                      setSheetState(() => dialogError = 'Enter a name first.');
                                      return;
                                    }
                                    final confirmed = await showMobileConfirmDialog(
                                      ctx,
                                      title: location == null ? 'Create ${type == 'WAREHOUSE' ? 'Warehouse' : 'Store'}' : 'Save Changes',
                                      message: location == null
                                          ? 'Create $name as a ${type == 'WAREHOUSE' ? 'warehouse' : 'store'}?'
                                          : 'Save changes to $name?',
                                      confirmLabel: 'Confirm',
                                      icon: Icons.check_circle_outline_rounded,
                                    );
                                    if (!confirmed) return;
                                    setSheetState(() {
                                      saving = true;
                                      dialogError = null;
                                    });
                                    try {
                                      if (location == null) {
                                        await _api.createLocation(name: name, type: type);
                                      } else {
                                        await _api.updateLocation(
                                          id: location.id,
                                          name: name,
                                          type: type,
                                        );
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx, true);
                                    } catch (e) {
                                      setSheetState(() {
                                        saving = false;
                                        dialogError = _friendlyError(e);
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
          ),
        ),
      );
      if (changed == true) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(location == null ? 'Location created' : 'Location updated'),
          ),
        );
      }
    } finally {
      nameCtrl.dispose();
    }
  }

  List<Location> get _filteredLocations {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _locations.where((location) {
      if (_filter != 'ALL' && location.type.toUpperCase() != _filter) {
        return false;
      }
      if (query.isEmpty) return true;
      final hay = '${location.name} ${location.type}'.toLowerCase();
      return hay.contains(query);
    }).toList()
      ..sort((a, b) {
        final typeCompare = a.type.compareTo(b.type);
        if (typeCompare != 0) return typeCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  int get _storeCount => _locations.where((location) => location.type.toUpperCase() == 'SHOP').length;
  int get _warehouseCount => _locations.where((location) => location.type.toUpperCase() == 'WAREHOUSE').length;

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFFFFE5E7),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected ? const Color(0xFFE31B23) : Colors.black87,
      ),
    );
  }

  Widget _locationTile(Location location) {
    final isWarehouse = location.type.toUpperCase() == 'WAREHOUSE';
    return MobileActionTile(
      icon: isWarehouse ? Icons.warehouse_rounded : Icons.storefront_rounded,
      title: location.name,
      subtitle: isWarehouse ? 'Warehouse' : 'Store',
      accentColor: isWarehouse ? const Color(0xFF6D4C41) : const Color(0xFF1565C0),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _openEditor(location),
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF1976D2)),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              final confirmed = await showMobileConfirmDialog(
                context,
                title: 'Delete ${isWarehouse ? 'Warehouse' : 'Store'}',
                message: 'Delete ${location.name}?',
                confirmLabel: 'Delete',
                icon: Icons.delete_outline_rounded,
              );
              if (!confirmed) return;
              try {
                await _api.deleteLocation(location.id);
                await _load();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location deleted')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_friendlyError(e)),
                    backgroundColor: const Color(0xFFC62828),
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE31B23)),
          ),
        ],
      ),
      onTap: () => _openEditor(location),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredLocations;
    return MobilePageScaffold(
      title: 'Stores & Warehouses',
      subtitle: '${_locations.length} locations configured',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MobileSearchField(
                      controller: _searchCtrl,
                      hintText: 'Search stores or warehouses',
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => setState(() {}),
                      showActionButton: false,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MobileMetricChip('Stores $_storeCount'),
                        MobileMetricChip('Warehouses $_warehouseCount'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _filterChip('All', 'ALL'),
                        _filterChip('Stores', 'SHOP'),
                        _filterChip('Warehouses', 'WAREHOUSE'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && rows.isEmpty)
              MobileRetryState(
                icon: Icons.cloud_off_rounded,
                title: 'Could Not Load Locations',
                message: _error!,
                onRetry: _load,
              )
            else if (rows.isEmpty)
              const MobileEmptyState(
                icon: Icons.storefront_outlined,
                title: 'No locations found',
                message: 'Add a store or warehouse to start managing stock movement.',
              )
            else
              ...rows.map(_locationTile),
          ],
        ),
      ),
    );
  }
}
