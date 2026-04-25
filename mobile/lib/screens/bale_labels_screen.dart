import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class BaleLabelsScreen extends StatefulWidget {
  final AppState appState;

  const BaleLabelsScreen({super.key, required this.appState});

  @override
  State<BaleLabelsScreen> createState() => _BaleLabelsScreenState();
}

class _BaleLabelsScreenState extends State<BaleLabelsScreen> {
  List<Map<String, dynamic>> _labels = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;
  String _friendlyError(Object error) => ApiClient.friendlyError(error);

  ApiClient get api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

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
      _labels = await api.getBaleLabels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showDialog([Map<String, dynamic>? existing]) {
    final nameCtrl = TextEditingController(text: (existing?['name'] ?? '').toString());
    final descriptionCtrl = TextEditingController(
      text: (existing?['description'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Bale Label' : 'Edit Bale Label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Label name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
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
                  title: 'Delete Bale Label',
                  message: 'Delete ${(existing['name'] ?? 'this label').toString()}?',
                  confirmLabel: 'Delete',
                  icon: Icons.delete_outline_rounded,
                );
                if (!confirmed) return;
                await api.deleteBaleLabel(_toInt(existing['id']));
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final confirmed = await showMobileConfirmDialog(
                ctx,
                title: existing == null ? 'Create Bale Label' : 'Save Bale Label',
                message: existing == null ? 'Create $name?' : 'Save changes to $name?',
                confirmLabel: 'Confirm',
                icon: Icons.label_rounded,
              );
              if (!confirmed) return;
              try {
                if (existing != null) {
                  await api.updateBaleLabel(
                    _toInt(existing['id']),
                    name: name,
                    description: descriptionCtrl.text.trim(),
                  );
                } else {
                  await api.createBaleLabel(
                    name: name,
                    description: descriptionCtrl.text.trim(),
                  );
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
    final query = _searchCtrl.text.trim().toLowerCase();
    final visibleLabels = _labels.where((label) {
      if (query.isEmpty) return true;
      final haystack = '${label['name'] ?? ''} ${label['description'] ?? ''}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
    return MobilePageScaffold(
      title: 'Bale Labels',
      subtitle: '',
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MobileSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search bale labels',
                  onChanged: (_) {},
                  onSubmitted: (_) {},
                  showActionButton: false,
                ),
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
            else if (_labels.isEmpty)
              const MobileEmptyState(
                icon: Icons.label_off_rounded,
                title: 'No bale labels yet',
                message: 'Create your first bale label or brand.',
              )
            else if (visibleLabels.isEmpty)
              const MobileEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No bale labels match',
                message: 'Try a different label search.',
              )
            else
              ...visibleLabels.map(
                (label) => MobileActionTile(
                  icon: Icons.label_rounded,
                  accentColor: const Color(0xFF00897B),
                  title: (label['name'] ?? '').toString(),
                  subtitle: '',
                  onTap: () => _showDialog(label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
