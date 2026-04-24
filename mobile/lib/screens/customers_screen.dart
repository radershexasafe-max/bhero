import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/mobile_ui.dart';

class CustomersScreen extends StatefulWidget {
  final AppState appState;
  const CustomersScreen({super.key, required this.appState});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _customers = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  final _pdfExporter = PdfExportService();

  ApiClient get api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

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
    _searchDebounce = Timer(const Duration(milliseconds: 250), _load);
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('duplicate_customer')) {
      return 'This customer already exists. Check the name, phone number, or email.';
    }
    if (text.contains('customer_has_history')) {
      return 'This customer has transaction history and cannot be deleted.';
    }
    if (text.contains('customer_name_required')) {
      return 'Customer name is required.';
    }
    return text;
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
      _customers = await api.getCustomers(search: _searchCtrl.text.trim());
    } catch (e) {
      _showMessage('Error: ${_friendlyError(e)}', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _exportStatement(Customer customer) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return;
    _showMessage('Preparing customer statement...');
    try {
      final data = await api.getCustomer(customer.id);
      final payload = Map<String, dynamic>.from(data['customer'] as Map);
      final history = (payload['history'] as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final loyaltyHistory = (payload['loyalty_history'] as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final path = await _pdfExporter.saveCustomerStatementPdf(
        tenant: tenant,
        customer: payload,
        history: history,
        loyaltyHistory: loyaltyHistory,
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Customer statement for ${customer.name}',
      );
    } catch (e) {
      _showMessage('Could not export customer statement: ${_friendlyError(e)}', error: true);
    }
  }

  Future<void> _showAddEditDialog([Customer? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    bool saving = false;
    bool deleting = false;
    bool exporting = false;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(existing == null ? 'Add Customer' : 'Edit Customer'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                  ),
                  if (saving || deleting || exporting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: (saving || deleting || exporting) ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (existing != null)
              TextButton.icon(
                onPressed: (saving || deleting || exporting)
                    ? null
                    : () async {
                        setModalState(() => exporting = true);
                        await _exportStatement(existing);
                        if (ctx.mounted) {
                          setModalState(() => exporting = false);
                        }
                      },
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Statement PDF'),
              ),
            if (existing != null)
              TextButton(
                onPressed: (saving || deleting || exporting)
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (confirmCtx) => AlertDialog(
                            title: const Text('Delete Customer'),
                            content: Text('Delete ${existing.name}?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(confirmCtx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(confirmCtx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE31B23),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        setModalState(() => deleting = true);
                        try {
                          await api.deleteCustomer(existing.id);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, 'deleted');
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setModalState(() => deleting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(_friendlyError(e))),
                          );
                        }
                      },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: (saving || deleting || exporting)
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Customer name is required.')),
                        );
                        return;
                      }
                      final payload = {
                        'name': name,
                        'phone': phoneCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'address': addressCtrl.text.trim(),
                      };
                      setModalState(() => saving = true);
                      try {
                        if (existing != null) {
                          await api.updateCustomer(existing.id, payload);
                        } else {
                          await api.createCustomer(payload);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, existing == null ? 'created' : 'updated');
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setModalState(() => saving = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(_friendlyError(e))),
                        );
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
              child: Text(existing == null ? 'Save' : 'Update'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await _load();
    if (result == 'deleted') {
      _showMessage('Customer deleted');
    } else if (result == 'created') {
      _showMessage('Customer saved');
    } else if (result == 'updated') {
      _showMessage('Customer updated');
    }
  }

  Future<void> _importCustomerFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'vcf'],
      );
      final file = (picked != null && picked.files.isNotEmpty) ? picked.files.first : null;
      if (file == null || file.path == null) {
        return;
      }
      _showMessage('Importing customers...');
      final result = await api.importCustomersFile(
        filePath: file.path!,
        filename: file.name,
      );
      await _load();
      final created = int.tryParse('${result['created'] ?? 0}') ?? 0;
      final updated = int.tryParse('${result['updated'] ?? 0}') ?? 0;
      final errors = ((result['errors'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
      final suffix = errors.isEmpty ? '' : '\n${errors.take(2).join('\n')}';
      _showMessage('Customers imported. Created: $created, Updated: $updated$suffix');
    } catch (e) {
      _showMessage('Could not import customers: ${_friendlyError(e)}', error: true);
    }
  }

  Future<Contact?> _pickPhonebookContact(List<Contact> contacts) async {
    final searchCtrl = TextEditingController();
    final sorted = [...contacts]
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    try {
      return await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          var filtered = sorted;
          return StatefulBuilder(
            builder: (ctx, setSheetState) => FractionallySizedBox(
              heightFactor: 0.88,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pick From Phonebook',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search phonebook contact',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) {
                          final q = value.trim().toLowerCase();
                          setSheetState(() {
                            filtered = q.isEmpty
                                ? sorted
                                : sorted.where((contact) {
                                    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                                    final email = contact.emails.isNotEmpty ? contact.emails.first.address : '';
                                    final hay = '${contact.displayName} $phone $email'.toLowerCase();
                                    return hay.contains(q);
                                  }).toList();
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: filtered.isEmpty
                            ? const MobileEmptyState(
                                icon: Icons.contacts_rounded,
                                title: 'No contacts found',
                                message: 'Try a different name, phone number, or email.',
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, index) {
                                  final contact = filtered[index];
                                  final phone = contact.phones.isNotEmpty ? contact.phones.first.number.trim() : '';
                                  final email = contact.emails.isNotEmpty ? contact.emails.first.address.trim() : '';
                                  return MobileActionTile(
                                    icon: Icons.person_add_alt_1_rounded,
                                    title: contact.displayName.trim().isEmpty ? 'Unnamed Contact' : contact.displayName.trim(),
                                    subtitle: [phone, email].where((value) => value.isNotEmpty).join(' - '),
                                    onTap: () => Navigator.pop(ctx, contact),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  Future<void> _pickCustomerFromPhonebook() async {
    try {
      var allowed = await FlutterContacts.requestPermission(readonly: true);
      var permission = await Permission.contacts.status;
      if (!allowed && !permission.isGranted) {
        permission = await Permission.contacts.request();
        allowed = permission.isGranted;
        if (!allowed) {
          allowed = await FlutterContacts.requestPermission(readonly: true);
        }
      }
      if (!allowed) {
        _showMessage(
          'Phonebook permission was not granted. Allow Contacts access, then try again.',
          error: true,
        );
        if (permission.isPermanentlyDenied || permission.isRestricted) {
          await openAppSettings();
        }
        return;
      }
      _showMessage('Loading phonebook contacts...');
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      if (contacts.isEmpty) {
        _showMessage('No phonebook contacts were found on this device.', error: true);
        return;
      }
      final selected = await _pickPhonebookContact(contacts);
      if (selected == null) return;
      final phone = selected.phones.isNotEmpty ? selected.phones.first.number.trim() : '';
      final email = selected.emails.isNotEmpty ? selected.emails.first.address.trim() : '';
      final address = selected.addresses.isNotEmpty
          ? [
              selected.addresses.first.address,
              selected.addresses.first.city,
              selected.addresses.first.state,
              selected.addresses.first.country,
            ].where((part) => part.trim().isNotEmpty).join(', ')
          : '';
      final rows = <Map<String, dynamic>>[
        {
          'name': selected.displayName.trim(),
          'phone': phone,
          'email': email,
          'address': address,
          'notes': 'Imported from phonebook',
        }
      ].where((row) => (row['name'] ?? '').toString().trim().isNotEmpty).toList();
      if (rows.isEmpty) {
        _showMessage('The selected contact does not have a usable name.', error: true);
        return;
      }

      final result = await api.importCustomersFromPhonebook(rows);
      await _load();
      final created = int.tryParse('${result['created'] ?? 0}') ?? 0;
      final updated = int.tryParse('${result['updated'] ?? 0}') ?? 0;
      final errors = ((result['errors'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
      final suffix = errors.isEmpty ? '' : '\n${errors.take(2).join('\n')}';
      _showMessage('Phonebook contact saved. Created: $created, Updated: $updated$suffix');
    } catch (e) {
      _showMessage('Could not import the selected phonebook contact: ${_friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Customers',
      subtitle: 'Search, add, edit, and delete customer records from one place.',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
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
              title: 'Find Customer',
              subtitle: 'Search by name, phone, email, or address',
              child: MobileSearchField(
                controller: _searchCtrl,
                hintText: 'Search customers',
                onSearch: _load,
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Customers: ${_customers.length}'),
                ActionChip(
                  avatar: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Import CSV / Excel / VCF'),
                  onPressed: _importCustomerFile,
                ),
                ActionChip(
                  avatar: const Icon(Icons.contacts_rounded, size: 18),
                  label: const Text('Pick From Phonebook'),
                  onPressed: _pickCustomerFromPhonebook,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_customers.isEmpty)
              const MobileEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No customers found',
                message: 'Add a customer or try a different search.',
              )
            else
              ..._customers.map((customer) => MobileActionTile(
                    icon: Icons.person_rounded,
                    title: customer.name,
                    subtitle: [
                      customer.phone ?? '',
                      customer.email ?? '',
                      customer.address ?? '',
                    ].where((value) => value.isNotEmpty).join(' - '),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${customer.loyaltyPoints} pts', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${customer.visitCount} visits', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: () => _showAddEditDialog(customer),
                  )),
          ],
        ),
      ),
    );
  }
}
