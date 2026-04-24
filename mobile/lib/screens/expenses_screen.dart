import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class ExpensesScreen extends StatefulWidget {
  final AppState appState;
  const ExpensesScreen({super.key, required this.appState});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  final _categoryCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  String? _error;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _locationId;
  List<Map<String, dynamic>> _rows = const [];
  double _total = 0;

  ApiClient get _api => ApiClient(
        baseUrl: widget.appState.baseUrl,
        token: widget.appState.token,
      );

  @override
  void initState() {
    super.initState();
    _locationId = widget.appState.defaultLocationId;
    _categoryCtrl.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _categoryCtrl.removeListener(_handleSearchChanged);
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0;
  }

  String _money(dynamic value) => _num(value).toStringAsFixed(0);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getExpenses(
        from: _fmt.format(_from),
        to: _fmt.format(_to),
        locationId: _locationId,
        category: _categoryCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rows = ((data['expenses'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _total = _num(data['total']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.friendlyError(
          e,
          fallback: 'Could not load expenses right now. Refresh to try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  Future<void> _addExpense() async {
    final locationId = _locationId ?? widget.appState.defaultLocationId ?? 0;
    if (locationId <= 0) {
      _showMessage('Choose a location first.', error: true);
      return;
    }

    final category = TextEditingController(text: _categoryCtrl.text.trim());
    final amount = TextEditingController();
    final note = TextEditingController();
    String? dialogError;
    var saving = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Add Expense'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dialogError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      dialogError!,
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
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
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });
                      try {
                        await _api.createExpense(
                          locationId: locationId,
                          category: category.text.trim(),
                          amount: double.tryParse(amount.text.trim()) ?? 0,
                          expenseDate: _fmt.format(_to),
                          note: note.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          dialogError = ApiClient.friendlyError(e);
                        });
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save Expense'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      _showMessage('Expense added');
      await _load();
    }
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

  @override
  Widget build(BuildContext context) {
    final locations = widget.appState.accessibleLocations;
    return MobilePageScaffold(
      title: 'Expenses',
      subtitle: '',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileSectionCard(
              icon: Icons.payments_rounded,
              title: 'Expenses',
              subtitle: 'Review expense records and add new expenses from mobile.',
              accentColor: const Color(0xFFE31B23),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(true),
                          icon: const Icon(Icons.date_range_rounded),
                          label: Text('From ${_fmt.format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(false),
                          icon: const Icon(Icons.event_rounded),
                          label: Text('To ${_fmt.format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _locationId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All locations')),
                      ...locations.map(
                        (location) => DropdownMenuItem<int?>(
                          value: location.id,
                          child: Text('${location.name} (${location.type})'),
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      setState(() => _locationId = value);
                      await _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  MobileSearchField(
                    controller: _categoryCtrl,
                    hintText: 'Filter by category',
                    onSearch: _load,
                    onChanged: (_) {},
                    onSubmitted: (_) => _load(),
                    showActionButton: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Records: ${_rows.length}'),
                MobileMetricChip('Total: ${_money(_total)}'),
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
            else if (_error != null)
              MobileRetryState(
                icon: Icons.wifi_off_rounded,
                title: 'Could Not Load Expenses',
                message: _error!,
                onRetry: _load,
              )
            else if (_rows.isEmpty)
              const MobileEmptyState(
                icon: Icons.money_off_rounded,
                title: 'No expenses found',
                message: 'Expenses in the selected range will appear here.',
              )
            else
              ..._rows.map(
                (row) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (row['category'] ?? '-').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            MobileStatusBadge(
                              label: _money(row['amount']),
                              backgroundColor: const Color(0xFFFFEBEE),
                              foregroundColor: const Color(0xFFC62828),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            MobileMetricChip('Date: ${row['expense_date'] ?? '-'}'),
                            MobileMetricChip('Location: ${row['location_name'] ?? 'All'}'),
                          ],
                        ),
                        if ((row['note'] ?? '').toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text((row['note'] ?? '').toString()),
                        ],
                      ],
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
