import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../services/printer_service.dart';
import '../theme/brand.dart';
import '../widgets/auth_ui.dart';
import '../widgets/mobile_ui.dart';

class SettingsScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.appState,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrl = TextEditingController();
  final _receiptPhone = TextEditingController();
  final _receiptEmail = TextEditingController();
  final _receiptAddress = TextEditingController();
  final _receiptLogoPath = TextEditingController();
  final printer = PrinterService();

  bool _loading = false;
  bool _showConnectionTools = false;
  String? _printerMac;
  bool _connected = false;
  int _cachedProducts = 0;
  ReceiptBranding _savedBranding = const ReceiptBranding();
  bool _receiptDetailsDirty = false;

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _baseUrl.text = widget.appState.baseUrl;
    _receiptPhone.addListener(_handleReceiptBrandingChanged);
    _receiptEmail.addListener(_handleReceiptBrandingChanged);
    _receiptAddress.addListener(_handleReceiptBrandingChanged);
    _receiptLogoPath.addListener(_handleReceiptBrandingChanged);
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _receiptPhone.dispose();
    _receiptEmail.dispose();
    _receiptAddress.dispose();
    _receiptLogoPath.dispose();
    super.dispose();
  }

  void _handleReceiptBrandingChanged() {
    final dirty =
        _receiptPhone.text.trim() != _savedBranding.phone.trim() ||
        _receiptEmail.text.trim() != _savedBranding.email.trim() ||
        _receiptAddress.text.trim() != _savedBranding.address.trim() ||
        _receiptLogoPath.text.trim() != _savedBranding.logoPath.trim();
    if (!mounted || dirty == _receiptDetailsDirty) return;
    setState(() => _receiptDetailsDirty = dirty);
  }

  Future<void> _load() async {
    final printerMac = await printer.getSavedPrinterMac();
    final connected = await printer.isConnected();
    final branding = await printer.getReceiptBranding();
    final db = await LocalDb.instance.db;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM cached_products'),
        ) ??
        0;
    if (!mounted) return;
    _receiptPhone.text = branding.phone;
    _receiptEmail.text = branding.email;
    _receiptAddress.text = branding.address;
    _receiptLogoPath.text = branding.logoPath;
    setState(() {
      _printerMac = printerMac;
      _connected = connected;
      _cachedProducts = count;
      _savedBranding = branding;
      _receiptDetailsDirty = false;
    });
  }

  Future<void> _saveBaseUrl() async {
    final confirmed = await showMobileConfirmDialog(
      context,
      title: 'Save Connection Settings',
      message: 'Save this connection endpoint on this device?',
      confirmLabel: 'Save',
      icon: Icons.language_rounded,
    );
    if (!confirmed) return;
    await widget.appState.setBaseUrl(_baseUrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection settings saved')),
    );
  }

  Future<void> _saveReceiptBranding() async {
    final confirmed = await showMobileConfirmDialog(
      context,
      title: 'Save Receipt Details',
      message: 'Save these receipt details and logo for this device?',
      confirmLabel: 'Save',
      icon: Icons.receipt_long_rounded,
      confirmColor: BrandColors.success,
    );
    if (!confirmed) return;
    setState(() => _loading = true);
    try {
      final branding = ReceiptBranding(
        phone: _receiptPhone.text,
        email: _receiptEmail.text,
        address: _receiptAddress.text,
        logoPath: _receiptLogoPath.text,
      );
      await printer.saveReceiptBranding(
        branding,
      );
      if (!mounted) return;
      setState(() {
        _savedBranding = branding;
        _receiptDetailsDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt details saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save receipt details: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.trim().isEmpty) return;
      setState(() => _receiptLogoPath.text = path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick logo right now: ${ApiClient.friendlyError(e)}')),
      );
    }
  }

  Future<void> _ensurePrinterPermissions() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (granted) return;
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
  }

  Future<void> _selectPrinter() async {
    setState(() => _loading = true);
    try {
      await _ensurePrinterPermissions();
      final devices = await printer.getPairedDevices();
      if (!mounted) return;

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No paired printers found. Pair the printer in Android Bluetooth settings first.',
            ),
          ),
        );
        return;
      }

      final selected = await showDialog<PairedPrinter>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select paired printer'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.macAddress),
                  onTap: () => Navigator.pop(ctx, device),
                );
              },
            ),
          ),
        ),
      );

      if (selected == null) return;
      if (selected.macAddress.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected printer does not have a usable Bluetooth address.')),
        );
        return;
      }

      final ok = await printer.connect(selected.macAddress);
      _printerMac = selected.macAddress;
      _connected = ok;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Printer connected' : 'Printer connection failed'),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load paired printers right now. Check Bluetooth, then try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printTest() async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return;

    setState(() => _loading = true);
    try {
      final mac = _printerMac ?? await printer.getSavedPrinterMac();
      if (mac != null && !(await printer.isConnected())) {
        final ok = await printer.connect(mac);
        _connected = ok;
      }

      await printer.printReceipt(
        tenant: tenant,
        title: 'TEST PRINT',
        items: const [],
        total: 0.0,
        note: 'If you can read this, printing is working.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print sent to printer')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the test receipt right now. Check the printer connection and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncProducts() async {
    final confirmed = await showMobileConfirmDialog(
      context,
      title: 'Sync Offline Products',
      message: 'Refresh the offline product cache on this device now?',
      confirmLabel: 'Sync',
      icon: Icons.download_rounded,
    );
    if (!confirmed) return;
    setState(() => _loading = true);
    try {
      final list = await api.getProducts(all: true);
      await LocalDb.instance.cacheProducts(list);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cached ${list.length} products for offline.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiClient.friendlyError(
              e,
              fallback: 'Could not refresh offline products right now.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showMobileConfirmDialog(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout from this device?',
      confirmLabel: 'Logout',
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await widget.appState.logout();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.appState.user;
    final previewLogoPath = resolveBrandLogoPath(
      overrideLogoPath: _receiptLogoPath.text,
      tenantLogoPath: widget.appState.tenant?.logoPath,
    );

    return MobilePageScaffold(
      title: 'Settings',
      subtitle:
          'Manage printing, offline data, and this device session.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          MobileSectionCard(
            icon: Icons.person_rounded,
            title: user?.name ?? 'User',
            subtitle: user?.email ?? '',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Role: ${user?.role ?? ''}'),
                MobileMetricChip('Cached products: $_cachedProducts'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MobileSectionCard(
            icon: Icons.language_rounded,
            title: 'Connection',
            subtitle: 'The app manages server access automatically. Advanced tools stay hidden unless needed.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wifi_tethering_rounded),
                  title: const Text('Automatic online and offline switching'),
                  subtitle: const Text(
                    'When the web system is reachable the app works online. If the network drops, cached data and queued sales keep working.',
                  ),
                  trailing: TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _showConnectionTools = !_showConnectionTools),
                    child: Text(_showConnectionTools ? 'Hide Advanced' : 'Advanced'),
                  ),
                ),
                if (_showConnectionTools) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(labelText: 'Connection endpoint'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _saveBaseUrl,
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save Connection Settings'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          MobileSectionCard(
            icon: Icons.print_rounded,
            title: 'Receipt Printer',
            subtitle:
                'Connect a paired Bluetooth thermal printer and test receipt printing.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MobileMetricChip(
                      _printerMac == null
                          ? 'No printer selected'
                          : 'Printer: $_printerMac',
                    ),
                    MobileMetricChip(
                      _connected ? 'Connected' : 'Not connected',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _selectPrinter,
                        icon: const Icon(Icons.bluetooth_searching_rounded),
                        label: const Text('Select Printer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _printTest,
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Test Print'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MobileSectionCard(
            icon: Icons.receipt_long_rounded,
            title: 'Receipt Details',
            subtitle: 'Business contact details and logo shown on receipts, login, and register pages.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _receiptPhone,
                  decoration: const InputDecoration(labelText: 'Business phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _receiptEmail,
                  decoration: const InputDecoration(labelText: 'Business email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _receiptAddress,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Business address'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _receiptLogoPath,
                  decoration: const InputDecoration(
                    labelText: 'Company logo path or URL',
                    helperText: 'Leave blank to use the bundled app logo. You can also use a file path on the device or a web URL.',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickLogo,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Upload Logo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_receiptLogoPath.text.trim().isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _receiptLogoPath.clear()),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Clear Logo'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _receiptLogoPath.text.trim().isEmpty
                            ? 'Login / Register Logo Preview (Default)'
                            : 'Login / Register Logo Preview',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: AuthLogo(
                          logoPath: previewLogoPath,
                          height: 90,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Receipt Preview',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          MobileMetricChip(_receiptDetailsDirty ? 'Unsaved changes' : 'Saved'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: AuthLogo(
                          logoPath: previewLogoPath,
                          height: 72,
                        ),
                      ),
                      const SizedBox(height: 12),
                      MobileLabelValue(
                        label: 'Phone',
                        value: _receiptPhone.text.trim().isEmpty ? '-' : _receiptPhone.text.trim(),
                      ),
                      const SizedBox(height: 8),
                      MobileLabelValue(
                        label: 'Email',
                        value: _receiptEmail.text.trim().isEmpty ? '-' : _receiptEmail.text.trim(),
                      ),
                      const SizedBox(height: 8),
                      MobileLabelValue(
                        label: 'Address',
                        value: _receiptAddress.text.trim().isEmpty ? '-' : _receiptAddress.text.trim(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _saveReceiptBranding,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.success,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Receipt Details'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MobileSectionCard(
            icon: Icons.cloud_sync_rounded,
            title: 'Offline Cache',
            subtitle: 'Refresh the local product cache for offline selling',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MobileLabelValue(
                  label: 'Cached products',
                  value: '$_cachedProducts',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _syncProducts,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Sync Products'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _logout,
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}
