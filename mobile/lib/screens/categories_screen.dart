import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';

class CategoriesScreen extends StatefulWidget {
  final AppState appState;
  const CategoriesScreen({super.key, required this.appState});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<ProductCategory> _categories = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  ApiClient get api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  String _friendlyError(Object error) => ApiClient.friendlyError(error);

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
      _categories = await api.getBaleCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showDialog([ProductCategory? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Category' : 'Edit Category'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (existing != null)
            TextButton(
              onPressed: () async {
                final confirmed = await showMobileConfirmDialog(
                  ctx,
                  title: 'Delete Category',
                  message: 'Delete ${existing.name}?',
                  confirmLabel: 'Delete',
                  icon: Icons.delete_outline_rounded,
                );
                if (!confirmed) return;
                await api.deleteBaleCategory(existing.id);
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
                title: existing == null ? 'Create Category' : 'Save Category',
                message: existing == null ? 'Create $name?' : 'Save changes to $name?',
                confirmLabel: 'Confirm',
                icon: Icons.folder_rounded,
              );
              if (!confirmed) return;
              try {
                if (existing != null) {
                  await api.updateBaleCategory(existing.id, name: name);
                } else {
                  await api.createBaleCategory(name: name);
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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final visibleCategories = _categories.where((category) {
      if (query.isEmpty) return true;
      return category.name.toLowerCase().contains(query);
    }).toList();
    return MobilePageScaffold(
      title: 'Bale Categories',
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
                  hintText: 'Search bale categories',
                  onChanged: (_) {},
                  onSubmitted: (_) {},
                  showActionButton: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_categories.isEmpty)
              const MobileEmptyState(
                icon: Icons.folder_off_rounded,
                title: 'No bale categories yet',
                message: 'Create your first bale category to organize bale items.',
              )
            else if (visibleCategories.isEmpty)
              const MobileEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No bale categories match',
                message: 'Try a different category search.',
              )
            else
              ...visibleCategories.map((category) => MobileActionTile(
                icon: Icons.folder_rounded,
                accentColor: const Color(0xFFB26A00),
                title: category.name,
                subtitle: '',
                onTap: () => _showDialog(category),
              )),
          ],
        ),
      ),
    );
  }
}
