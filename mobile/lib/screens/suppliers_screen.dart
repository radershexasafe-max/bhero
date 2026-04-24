import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class SuppliersScreen extends StatefulWidget {
  final AppState appState;
  const SuppliersScreen({super.key, required this.appState});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Supplier> _suppliers = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  String _friendlyError(Object error) => ApiClient.friendlyError(error);

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _suppliers = await api.getSuppliers(search: _searchCtrl.text.trim());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showDialog([Supplier? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final contactCtrl = TextEditingController(text: existing?.contactPerson ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Supplier' : 'Edit Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Company Name *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Person'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (existing != null)
            TextButton(
              onPressed: () async {
                final confirmed = await showMobileConfirmDialog(
                  ctx,
                  title: 'Delete Supplier',
                  message: 'Delete ${existing.name}?',
                  confirmLabel: 'Delete',
                  icon: Icons.delete_outline_rounded,
                );
                if (!confirmed) return;
                try {
                  await api.deleteSupplier(existing.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(_friendlyError(e))),
                    );
                  }
                }
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final confirmed = await showMobileConfirmDialog(
                ctx,
                title: existing == null ? 'Create Supplier' : 'Save Supplier',
                message: existing == null ? 'Create $name?' : 'Save changes to $name?',
                confirmLabel: 'Confirm',
                icon: Icons.local_shipping_outlined,
              );
              if (!confirmed) return;
              try {
                final payload = {
                  'name': name,
                  'contact_person': contactCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'address': addressCtrl.text.trim(),
                };
                if (existing != null) {
                  await api.updateSupplier(existing.id, payload);
                } else {
                  await api.createSupplier(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(_friendlyError(e))),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Suppliers',
      subtitle: 'Manage bale suppliers, contacts, and ordering details from a cleaner mobile view.',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(),
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileSectionCard(
              icon: Icons.search_rounded,
              title: 'Find Supplier',
              subtitle: 'Search by company, contact person, phone, or email',
              child: Column(
                children: [
                  MobileSearchField(
                    controller: _searchCtrl,
                    hintText: 'Search suppliers',
                    onSearch: _load,
                    onChanged: (_) {},
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MobileMetricChip('Suppliers: ${_suppliers.length}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_suppliers.isEmpty)
              const MobileEmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'No suppliers found',
                message: 'Add a supplier or try a different search.',
              )
            else
              ..._suppliers.map(
                (supplier) => MobileActionTile(
                  icon: Icons.local_shipping_rounded,
                  title: supplier.name,
                  subtitle: [
                    supplier.contactPerson ?? '',
                    supplier.phone ?? '',
                    supplier.email ?? '',
                    supplier.address ?? '',
                  ].where((part) => part.isNotEmpty).join(' - '),
                  onTap: () => _showDialog(supplier),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
