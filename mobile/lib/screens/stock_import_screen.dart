import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class StockImportScreen extends StatefulWidget {
  final AppState appState;
  const StockImportScreen({super.key, required this.appState});

  @override
  State<StockImportScreen> createState() => _StockImportScreenState();
}

class _StockImportScreenState extends State<StockImportScreen> {
  int? _locationId;
  final _csv = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.locations.isNotEmpty
        ? widget.appState.locations.first.id
        : null;
  }

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  List<Map<String, dynamic>> _parseCsv(String text) {
    final normalized = text.replaceAll('\t', ',');
    final lines = normalized
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    List<String> headers = [];
    int start = 0;
    final first = lines.first.toLowerCase();
    if (first.contains('on_hand') ||
        first.contains('barcode') ||
        first.contains('product') ||
        first.contains('product_id')) {
      headers =
          lines.first.split(',').map((s) => s.trim().toLowerCase()).toList();
      start = 1;
    }

    final items = <Map<String, dynamic>>[];
    for (int i = start; i < lines.length; i++) {
      final parts = lines[i].split(',').map((s) => s.trim()).toList();
      if (parts.every((p) => p.isEmpty)) continue;

      final item = <String, dynamic>{};
      if (headers.isNotEmpty) {
        for (int j = 0; j < headers.length && j < parts.length; j++) {
          final key = headers[j];
          final val = parts[j];
          if (key == 'product_id' || key == 'id') {
            item['product_id'] = int.tryParse(val);
          } else if (key == 'barcode') {
            item['barcode'] = val;
          } else if (key == 'product' || key == 'name') {
            item['product'] = val;
          } else if (key == 'on_hand' || key == 'qty' || key == 'quantity') {
            item['on_hand'] = int.tryParse(val);
          }
        }
      } else {
        if (parts.length >= 3) {
          item['barcode'] = parts[0];
          item['product'] = parts[1];
          item['on_hand'] = int.tryParse(parts[2]);
        } else if (parts.length == 2) {
          item['barcode'] = parts[0];
          item['on_hand'] = int.tryParse(parts[1]);
        }
      }

      if (item['on_hand'] == null) continue;
      item.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
      items.add(item);
    }

    return items;
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final loc = _locationId;
      if (loc == null) throw Exception('Select a location');

      final items = _parseCsv(_csv.text);
      if (items.isEmpty) throw Exception('No valid rows found');

      final res = await _api.importStock(locationId: loc, items: items);
      setState(() {
        _result =
            'Updated: ${res['updated'] ?? 0} - Skipped: ${res['skipped'] ?? 0}';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Stock Import',
      subtitle:
          'Paste bale stock rows from a spreadsheet or CSV and update location stock in bulk.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.upload_file_rounded,
            title: 'Import Stock Rows',
            subtitle: 'Paste CSV data and choose the destination location',
            child: Column(
              children: [
                DropdownButtonFormField<int?>(
                  value: _locationId,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    for (final location in widget.appState.locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(location.name),
                      ),
                  ],
                  onChanged:
                      _busy ? null : (v) => setState(() => _locationId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _csv,
                  minLines: 8,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    labelText: 'Paste CSV rows',
                    hintText: 'barcode,product,on_hand\n12345,Bale A,10',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _result!,
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _import,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFE31B23),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Import / Update Stock'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const MobileSectionCard(
            icon: Icons.lightbulb_outline_rounded,
            title: 'CSV Tips',
            subtitle: 'Accepted formats',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Use columns like barcode, product, on_hand.'),
                SizedBox(height: 8),
                Text('You can also use product_id and on_hand if IDs are known.'),
                SizedBox(height: 8),
                Text('Tabs are automatically treated like commas.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
