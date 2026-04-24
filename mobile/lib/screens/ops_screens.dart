import 'dart:async';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import 'release_goods_screen.dart';
import '../widgets/mobile_ui.dart';

ApiClient _api(AppState appState) => ApiClient(baseUrl: appState.baseUrl, token: appState.token);

double _opsDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int _opsInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String _opsMoney(dynamic value) => _opsDouble(value).toStringAsFixed(0);

List<Map<String, dynamic>> _opsRows(dynamic value) {
  if (value is List) {
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
  return const [];
}

class SaleTransactionsScreen extends StatefulWidget {
  final AppState appState;
  const SaleTransactionsScreen({super.key, required this.appState});

  @override
  State<SaleTransactionsScreen> createState() => _SaleTransactionsScreenState();
}

class _SaleTransactionsScreenState extends State<SaleTransactionsScreen> {
  final _search = TextEditingController();
  final _fmt = DateFormat('yyyy-MM-dd');
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_handleSearchChanged);
    _load();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await _api(widget.appState).getSaleTransactions(
        search: _search.text.trim(),
        dateFrom: _dateFrom == null ? null : _fmt.format(_dateFrom!),
        dateTo: _dateTo == null ? null : _fmt.format(_dateTo!),
      );
      _error = null;
    } catch (e) {
      _error = ApiClient.friendlyError(
        e,
        fallback: 'Could not load sale transactions right now. Refresh to try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final current = from ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _opsRows(_data?['rows']);
    final totalSales = _opsMoney(_data?['total_sales']);
    return MobilePageScaffold(
      title: 'Sale Transactions',
      subtitle: 'Search live sale records, totals, and purchased bale items.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.search_rounded,
            accentColor: const Color(0xFF2E7D32),
            title: 'Find Transactions',
            subtitle: 'Search by sale number, customer, bale item, or salesperson.',
            child: MobileSearchField(
              controller: _search,
              hintText: 'Search sale details',
              onSearch: _load,
              onChanged: (_) {},
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.date_range_rounded),
                label: Text(_dateFrom == null ? 'Date from' : _fmt.format(_dateFrom!)),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.event_rounded),
                label: Text(_dateTo == null ? 'Date to' : _fmt.format(_dateTo!)),
              ),
              if (_dateFrom != null || _dateTo != null)
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                    });
                    await _load();
                  },
                  child: const Text('Clear Dates'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MobileMetricChip('Transactions: ${rows.length}'),
              MobileMetricChip('Total sales: $totalSales'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_error != null)
            MobileRetryState(
              icon: Icons.wifi_off_rounded,
              title: 'Could Not Load Sale Transactions',
              message: _error!,
              onRetry: _load,
            )
          else if (rows.isEmpty)
            const MobileEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No sale transactions',
              message: 'Sales in the selected search and date range will appear here.',
            )
          else ...rows.map((row) {
            final items = _opsRows(row['items']);
            return MobileSectionCard(
              icon: Icons.attach_money_rounded,
              accentColor: const Color(0xFF2E7D32),
              title: (row['sale_number'] ?? 'Sale').toString(),
              subtitle: '${row['customer_name'] ?? 'Walk-in'} | ${(row['customer_phone'] ?? '').toString()}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MobileMetricChip('Payment: ${(row['sale_mode'] ?? '-')}'),
                      MobileMetricChip('Amount received: ${_opsMoney(row['amount_received'] ?? row['amount_paid'])}'),
                      MobileMetricChip('Gross: ${_opsMoney(row['total'])}'),
                      MobileMetricChip('Sales person: ${(row['salesperson_name'] ?? '-')}'),
                      MobileMetricChip('Shop: ${(row['shop_name'] ?? '-')}'),
                      MobileMetricChip('Date: ${(row['created_at'] ?? '').toString().substring(0, ((row['created_at'] ?? '').toString().length >= 16) ? 16 : (row['created_at'] ?? '').toString().length)}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${item['product_name']} | ${item['qty']} x ${_opsMoney(item['unit_price'])}'),
                      )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CustomerBalancesScreen extends StatefulWidget {
  final AppState appState;
  const CustomerBalancesScreen({super.key, required this.appState});

  @override
  State<CustomerBalancesScreen> createState() => _CustomerBalancesScreenState();
}

class _CustomerBalancesScreenState extends State<CustomerBalancesScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  Map<String, dynamic>? _data;
  final _pdfExporter = PdfExportService();
  int? _locationId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_handleSearchChanged);
    _load();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await _api(widget.appState).getCustomerBalances(
        search: _search.text.trim(),
        locationId: _locationId,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _collect(Map row) async {
    final amount = TextEditingController(text: '${row['balance_due'] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await _api(widget.appState).collectCustomerBalance(
      customerId: int.tryParse('${row['customer_id']}') ?? 0,
      amount: double.tryParse(amount.text) ?? 0,
    );
    _load();
  }

  Future<void> _exportBalance(Map row) async {
    final tenant = widget.appState.tenant;
    if (tenant == null) return;
    try {
      final path = await _pdfExporter.saveCustomerBalancePdf(
        tenant: tenant,
        balanceRow: Map<String, dynamic>.from(row),
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Customer balance for ${row['customer_name'] ?? ''}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export balance PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _opsRows(_data?['rows']);
    return MobilePageScaffold(
      title: 'Customer Balances',
      subtitle: 'Customers with balances, payments received, and outstanding totals.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.search_rounded,
            title: 'Search',
            subtitle: 'Find customers with outstanding balances.',
            child: MobileSearchField(
              controller: _search,
              hintText: 'Customer name, phone, email',
              onSearch: _load,
              onChanged: (_) {},
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _locationId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Shop filter'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All shops')),
              ...widget.appState.accessibleLocations
                  .where((location) => location.type.toUpperCase() == 'SHOP')
                  .map(
                    (location) => DropdownMenuItem<int?>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                  ),
            ],
            onChanged: (value) async {
              setState(() => _locationId = value);
              await _load();
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MobileMetricChip('Customers: ${_opsInt(_data?['total_customers'])}'),
              MobileMetricChip('Balance: ${_opsMoney(_data?['total_balance_due'])}'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...rows.map((row) {
            final creditBalance = _opsDouble(row['credit_balance_due']);
            final availablePrepayment = _opsDouble(row['available_prepayment']);
            return MobileSectionCard(
              icon: Icons.account_balance_wallet_rounded,
              title: (row['customer_name'] ?? '').toString(),
              subtitle: (row['customer_phone'] ?? '').toString(),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _exportBalance(row),
                    child: const Text('PDF'),
                  ),
                  TextButton(
                    onPressed: creditBalance > 0 ? () => _collect(row) : null,
                    child: Text(creditBalance > 0 ? 'Record Credit Payment' : 'No Credit Due'),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: MobileLabelValue(label: 'Sale value', value: _opsMoney(row['total_sale_value']))),
                      Expanded(child: MobileLabelValue(label: 'Paid', value: _opsMoney(row['amount_paid']))),
                      Expanded(child: MobileLabelValue(label: 'Balance', value: _opsMoney(row['balance_due']))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: MobileLabelValue(label: 'Credit balance', value: _opsMoney(creditBalance))),
                      Expanded(child: MobileLabelValue(label: 'Available prepayment', value: _opsMoney(availablePrepayment))),
                      Expanded(child: MobileLabelValue(label: 'Net balance', value: _opsMoney(row['net_customer_balance']))),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CloseShiftScreen extends StatefulWidget {
  final AppState appState;
  final int? initialLocationId;
  final DateTime? initialBusinessDate;
  const CloseShiftScreen({
    super.key,
    required this.appState,
    this.initialLocationId,
    this.initialBusinessDate,
  });

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  bool _loading = true;
  Map<String, dynamic>? _data;
  late DateTime _businessDate;
  int? _locationId;

  @override
  void initState() {
    super.initState();
    _businessDate = widget.initialBusinessDate ?? DateTime.now();
    _locationId = widget.initialLocationId;
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
    final today = _fmt.format(_businessDate);
    final locationId = _locationId ?? widget.appState.defaultLocationId ?? 0;
    if (locationId <= 0) {
      if (mounted) {
        setState(() {
          _data = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      _data = await _api(widget.appState).getCloseShift(locationId: locationId, from: today, to: today, businessDate: today);
    } catch (e) {
      _showMessage('$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickBusinessDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _businessDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _businessDate = picked);
    await _load();
  }

  String _locationLabel(int? locationId) {
    for (final location in widget.appState.accessibleLocations) {
      if (location.id == locationId) {
        return '${location.name} (${location.type})';
      }
    }
    return 'No store selected';
  }

  Future<void> _addExpense() async {
    final locationId = _locationId ?? widget.appState.defaultLocationId ?? 0;
    if (locationId <= 0) {
      _showMessage('Choose a store first.', error: true);
      return;
    }
    final category = TextEditingController();
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
                    decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(14)),
                    child: Text(dialogError!, style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
                const SizedBox(height: 8),
                TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
                const SizedBox(height: 8),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });
                      try {
                        await _api(widget.appState).createExpense(
                          locationId: locationId,
                          category: category.text.trim(),
                          amount: double.tryParse(amount.text.trim()) ?? 0,
                          expenseDate: _fmt.format(_businessDate),
                          note: note.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          dialogError = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE31B23), foregroundColor: Colors.white),
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

  Future<void> _startShift() async {
    final locationId = _locationId ?? widget.appState.defaultLocationId ?? 0;
    if (locationId <= 0) {
      _showMessage('No store is assigned to this user.', error: true);
      return;
    }
    final openingCash = TextEditingController();
    final openingCard = TextEditingController();
    final openingEco = TextEditingController();
    String? dialogError;
    var saving = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Start Shift'),
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
                  controller: openingCash,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Opening cash'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: openingCard,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Opening card'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: openingEco,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Opening EcoCash'),
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
                        dialogError = null;
                        saving = true;
                      });
                      try {
                        await _api(widget.appState).startShift(
                          locationId: locationId,
                          businessDate: _fmt.format(_businessDate),
                          openingCash: double.tryParse(openingCash.text.trim()) ?? 0,
                          openingCard: double.tryParse(openingCard.text.trim()) ?? 0,
                          openingEcocash: double.tryParse(openingEco.text.trim()) ?? 0,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          dialogError = e.toString().replaceFirst('Exception: ', '');
                          saving = false;
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              child: Text(saving ? 'Starting...' : 'Start Shift'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    _showMessage('Shift started');
    await _load();
  }

  Future<void> _closeShift() async {
    final locationId = _locationId ?? widget.appState.defaultLocationId ?? 0;
    if (locationId <= 0) {
      _showMessage('No store is assigned to this user.', error: true);
      return;
    }
    final countedCash = TextEditingController();
    final countedCard = TextEditingController();
    final countedEco = TextEditingController();
    final otherCash = TextEditingController();
    String? dialogError;
    var saving = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Close Shift'),
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
                  controller: countedCash,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Counted cash'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: countedCard,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Counted card'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: countedEco,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Counted EcoCash'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: otherCash,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Other cash amount'),
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
                        dialogError = null;
                        saving = true;
                      });
                      try {
                        await _api(widget.appState).closeShift(
                          locationId: locationId,
                          businessDate: _fmt.format(_businessDate),
                          countedCash: (double.tryParse(countedCash.text.trim()) ?? 0) + (double.tryParse(otherCash.text.trim()) ?? 0),
                          countedCard: double.tryParse(countedCard.text.trim()) ?? 0,
                          countedEcocash: double.tryParse(countedEco.text.trim()) ?? 0,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          dialogError = e.toString().replaceFirst('Exception: ', '');
                          saving = false;
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              child: Text(saving ? 'Closing...' : 'Close Shift'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    _showMessage('Shift closed');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final accessibleLocations = widget.appState.accessibleLocations;
    final summary = Map<String, dynamic>.from((_data?['summary'] as Map?) ?? const {});
    final session = (_data?['session'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final salesIncluded = ((summary['sales_included'] as List?) ?? const []).cast<Map>();
    final selectedLocationId = _locationId ?? widget.appState.defaultLocationId;
    return MobilePageScaffold(
      title: 'Close Shift',
      subtitle: 'Sales performance, cash reconciliation, and shift sales in one place.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.play_circle_rounded,
            title: 'Shift Status',
            subtitle: session.isEmpty
                ? 'No shift is open for ${_fmt.format(_businessDate)}.'
                : 'Current status: ${session['status'] ?? 'OPEN'}',
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  value: selectedLocationId != null &&
                          accessibleLocations.any((location) => location.id == selectedLocationId)
                      ? selectedLocationId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Store'),
                  items: accessibleLocations
                      .map(
                        (location) => DropdownMenuItem<int>(
                          value: location.id,
                          child: Text('${location.name} (${location.type})'),
                        ),
                      )
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (value) {
                          setState(() => _locationId = value);
                          _load();
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MobileLabelValue(
                        label: 'Business date',
                        value: _fmt.format(_businessDate),
                      ),
                    ),
                    Expanded(
                      child: MobileLabelValue(
                        label: 'Opened by',
                        value: '${session['opened_by'] ?? '-'}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _startShift,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start Shift'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE31B23),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _closeShift,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Close Shift'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickBusinessDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(_fmt.format(_businessDate)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _addExpense,
                      icon: const Icon(Icons.add_card_rounded),
                      label: const Text('Add Expense'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Current store: ${_locationLabel(selectedLocationId)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            MobileSectionCard(
              icon: Icons.bar_chart_rounded,
              title: 'Sales Performance',
              child: Column(
                children: [
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Bales sold', value: '${_opsInt(summary['bales_sold'])}')), Expanded(child: MobileLabelValue(label: 'Bales returned', value: '${_opsInt(summary['bales_returned'])}'))]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Cancelled bales', value: '${_opsInt(summary['cancelled_bales'])}')), Expanded(child: MobileLabelValue(label: 'Sales amount', value: _opsMoney(summary['bale_sales_amount'])))]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.payments_rounded,
              title: 'Cash Reconciliation',
              child: Column(
                children: [
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Opening', value: _opsMoney(summary['opening_balance']))), Expanded(child: MobileLabelValue(label: 'Cash sales', value: _opsMoney(summary['cash_from_sales'])))]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Debt payments', value: _opsMoney(summary['debt_payments']))), Expanded(child: MobileLabelValue(label: 'Prepayments', value: _opsMoney(summary['prepayment_cash_received'])))]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Expenses', value: _opsMoney(summary['expenses_total']))), Expanded(child: MobileLabelValue(label: 'Cash in hand', value: _opsMoney(summary['total_cash_inhand'])))]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.account_balance_rounded,
              title: 'Digital And Credit Totals',
              child: Column(
                children: [
                  Row(children: [Expanded(child: MobileLabelValue(label: 'EcoCash', value: _opsMoney(summary['ecocash_received']))), Expanded(child: MobileLabelValue(label: 'Credit sales', value: _opsMoney(summary['total_credit_sales'])))]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: MobileLabelValue(label: 'Credit payments', value: _opsMoney(summary['credit_payments_total']))), Expanded(child: MobileLabelValue(label: 'Prepayment sales', value: _opsMoney(summary['total_prepayment_sales'])))]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.receipt_rounded,
              title: 'Sales Included In Shift',
              child: Column(
                children: salesIncluded.map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('${row['sale_number'] ?? '-'}')),
                      Expanded(child: Text('${row['customer_name'] ?? '-'}')),
                      Text(_opsMoney(row['total'])),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ShiftCollectionsScreen extends StatefulWidget {
  final AppState appState;
  const ShiftCollectionsScreen({super.key, required this.appState});

  @override
  State<ShiftCollectionsScreen> createState() => _ShiftCollectionsScreenState();
}

class _ShiftCollectionsScreenState extends State<ShiftCollectionsScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  late DateTime _from;
  late DateTime _to;
  int? _locationId;
  String _groupBy = 'date';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _load();
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _from = picked);
    await _load();
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(context: context, initialDate: _to, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _to = picked);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await _api(widget.appState).getShiftCollections(
        from: _fmt.format(_from),
        to: _fmt.format(_to),
        locationId: _locationId,
        groupBy: _groupBy,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCollections = _rows.fold<double>(0, (sum, row) => sum + _opsDouble(row['total_collections']));
    final totalExpenses = _rows.fold<double>(0, (sum, row) => sum + _opsDouble(row['total_expenses']));
    return MobilePageScaffold(
      title: 'Shift Collections',
      subtitle: 'Each shop record with collections, prepayments, and times.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSectionCard(
            icon: Icons.filter_alt_rounded,
            title: 'Filter Collections',
            child: Column(
              children: [
                DropdownButtonFormField<int?>(
                  value: widget.appState.accessibleLocations.any((location) => location.id == _locationId) ? _locationId : null,
                  decoration: const InputDecoration(labelText: 'Shop'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All shops')),
                    ...widget.appState.accessibleLocations.map((location) => DropdownMenuItem<int?>(value: location.id, child: Text('${location.name} (${location.type})'))),
                  ],
                  onChanged: (value) {
                    setState(() => _locationId = value);
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _DateQuickButton(label: 'From', value: _fmt.format(_from), onTap: _pickFrom)),
                    const SizedBox(width: 10),
                    Expanded(child: _DateQuickButton(label: 'To', value: _fmt.format(_to), onTap: _pickTo)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _groupBy,
                  decoration: const InputDecoration(labelText: 'Group / sort'),
                  items: const [
                    DropdownMenuItem(value: 'date', child: Text('By date')),
                    DropdownMenuItem(value: 'amount', child: Text('By amount')),
                  ],
                  onChanged: (value) {
                    setState(() => _groupBy = value ?? 'date');
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MobileMetricChip('Rows: ${_rows.length}'),
              MobileMetricChip('Collections: ${_opsMoney(totalCollections)}'),
              MobileMetricChip('Expenses: ${_opsMoney(totalExpenses)}'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ..._rows.map((row) => MobileSectionCard(
                icon: Icons.collections_bookmark_rounded,
                title: '${row['shop_name'] ?? '-'} | ${row['business_date'] ?? '-'}',
                subtitle: '${row['sales_person'] ?? '-'}',
                trailing: TextButton(
                  onPressed: () {
                    final locationId = _opsInt(row['location_id']);
                    final businessDateText = (row['business_date'] ?? '').toString();
                    final businessDate = DateTime.tryParse(businessDateText);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CloseShiftScreen(
                          appState: widget.appState,
                          initialLocationId: locationId > 0 ? locationId : null,
                          initialBusinessDate: businessDate,
                        ),
                      ),
                    );
                  },
                  child: const Text('View'),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Collections', value: _opsMoney(row['total_collections']))),
                        Expanded(child: MobileLabelValue(label: 'Sales', value: _opsMoney(row['total_sales_amount']))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Prepayments', value: _opsMoney(row['total_prepayments']))),
                        Expanded(child: MobileLabelValue(label: 'Credit payments', value: _opsMoney(row['total_credit_payments']))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Collections total', value: _opsMoney(row['total_collections']))),
                        Expanded(child: MobileLabelValue(label: 'Expenses', value: _opsMoney(row['total_expenses']))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: MobileLabelValue(label: 'Start time', value: '${row['start_time'] ?? '-'}')),
                        Expanded(child: MobileLabelValue(label: 'Closing time', value: '${row['closing_time'] ?? '-'}')),
                      ],
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DateQuickButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateQuickButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_rounded),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, overflow: TextOverflow.ellipsis),
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class PrepaymentsScreen extends StatefulWidget {
  final AppState appState;
  const PrepaymentsScreen({super.key, required this.appState});

  @override
  State<PrepaymentsScreen> createState() => _PrepaymentsScreenState();
}

class _PrepaymentsScreenState extends State<PrepaymentsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  final _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
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
      _data = await _api(widget.appState).getPrepayments();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Contact?> _pickPhonebookContact(List<Contact> contacts) async {
    final sorted = [...contacts]
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    final searchCtrl = TextEditingController();
    try {
      return await showDialog<Contact?>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final q = searchCtrl.text.trim().toLowerCase();
            final filtered = sorted.where((contact) {
              if (q.isEmpty) return true;
              final hay = [
                contact.displayName,
                ...contact.phones.map((phone) => phone.number),
                ...contact.emails.map((email) => email.address),
              ].join(' ').toLowerCase();
              return hay.contains(q);
            }).toList();
            return AlertDialog(
              title: const Text('Pick From Phonebook'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search phonebook contact',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? const Center(child: Text('No contacts found.'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final contact = filtered[index];
                                final subtitle = [
                                  if (contact.phones.isNotEmpty) contact.phones.first.number,
                                  if (contact.emails.isNotEmpty) contact.emails.first.address,
                                ].where((value) => value.trim().isNotEmpty).join(' | ');
                                return ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFFFEBEE),
                                    foregroundColor: Color(0xFFE31B23),
                                    child: Icon(Icons.contacts_rounded),
                                  ),
                                  title: Text(contact.displayName.isEmpty ? 'Unnamed contact' : contact.displayName),
                                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                                  onTap: () => Navigator.pop(ctx, contact),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  Future<Map<String, dynamic>?> _pickPhonebookCustomer() async {
    try {
      var permission = await Permission.contacts.request();
      var allowed = permission.isGranted;
      if (!allowed) {
        allowed = await FlutterContacts.requestPermission(readonly: true);
      }
      if (!allowed && !permission.isPermanentlyDenied) {
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
        return null;
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      if (contacts.isEmpty) {
        _showMessage('No phonebook contacts were found on this device.', error: true);
        return null;
      }
      final selected = await _pickPhonebookContact(contacts);
      if (selected == null) return null;

      final name = selected.displayName.trim();
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
      if (name.isEmpty) {
        _showMessage('The selected contact does not have a usable name.', error: true);
        return null;
      }

      await _api(widget.appState).importCustomersFromPhonebook([
        {
          'name': name,
          'phone': phone,
          'email': email,
          'address': address,
          'notes': 'Imported from phonebook',
        }
      ]);

      await _load();

      final searchTerm = phone.isNotEmpty ? phone : name;
      final matches = await _api(widget.appState).searchCustomers(searchTerm);
      Customer? chosen;
      for (final customer in matches) {
        final phoneMatch = phone.isNotEmpty &&
            (customer.phone ?? '').replaceAll(' ', '') == phone.replaceAll(' ', '');
        final nameMatch = customer.name.trim().toLowerCase() == name.toLowerCase();
        if (phoneMatch || nameMatch) {
          chosen = customer;
          break;
        }
      }
      chosen ??= matches.isNotEmpty ? matches.first : null;
      if (chosen == null) {
        _showMessage('The contact was imported, but could not be matched back to the customer list yet.', error: true);
        return null;
      }
      return {
        'id': chosen.id,
        'name': chosen.name,
        'phone': chosen.phone ?? '',
      };
    } catch (e) {
      _showMessage('Could not use the selected phonebook contact: $e', error: true);
      return null;
    }
  }

  Future<void> _add() async {
    final customers = _opsRows((_data?['lists'] as Map?)?['customers']);
    final shopLocations = widget.appState.accessibleLocations
        .where((location) => location.type.toUpperCase() == 'SHOP')
        .toList();
    var dialogCustomers = List<Map<String, dynamic>>.from(customers);
    int? customerId;
    int? locationId = widget.appState.defaultLocationId ??
        (shopLocations.isNotEmpty ? shopLocations.first.id : null);
    final amount = TextEditingController();
    final note = TextEditingController();
    final search = TextEditingController();
    String method = 'CASH';
    String? dialogError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final q = search.text.trim().toLowerCase();
          final filteredCustomers = dialogCustomers.where((customer) {
            if (q.isEmpty) return true;
            final hay = '${customer['name'] ?? ''} ${customer['phone'] ?? ''} ${customer['email'] ?? ''}'.toLowerCase();
            return hay.contains(q);
          }).toList();
          final customerOptions = filteredCustomers
              .map((customer) => _opsInt(customer['id']))
              .where((id) => id > 0)
              .toList();
          return AlertDialog(
            scrollable: true,
            title: const Text('Record Deposit'),
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          decoration: const InputDecoration(
                            labelText: 'Search customer',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Pick from phonebook',
                        onPressed: () async {
                          final imported = await _pickPhonebookCustomer();
                          if (imported == null) return;
                          final importedId = _opsInt(imported['id']);
                          final exists = dialogCustomers.any((row) => _opsInt(row['id']) == importedId);
                          if (!exists) {
                            dialogCustomers = [
                              ...dialogCustomers,
                              imported,
                            ];
                          }
                          setDialogState(() {
                            customerId = importedId;
                            search.text = (imported['name'] ?? '').toString();
                            dialogError = null;
                          });
                        },
                        icon: const Icon(Icons.contacts_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: customerOptions.contains(customerId) ? customerId : null,
                    isExpanded: true,
                    items: filteredCustomers
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: _opsInt(c['id']),
                            child: Text(
                              '${c['name']}${(c['phone'] ?? '').toString().trim().isNotEmpty ? ' | ${c['phone']}' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      customerId = v;
                      dialogError = null;
                    }),
                    decoration: const InputDecoration(labelText: 'Customer'),
                  ),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: shopLocations.any((location) => location.id == locationId) ? locationId : null,
                    isExpanded: true,
                    items: shopLocations
                        .map(
                          (location) => DropdownMenuItem<int>(
                            value: location.id,
                            child: Text('${location.name} (${location.type})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => locationId = v),
                    decoration: const InputDecoration(labelText: 'Store'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: method,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(value: 'CARD', child: Text('Card')),
                      DropdownMenuItem(value: 'ECOCASH', child: Text('EcoCash')),
                    ],
                    onChanged: (value) => setDialogState(() => method = value ?? 'CASH'),
                    decoration: const InputDecoration(labelText: 'Method'),
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
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (customerId == null || customerId! <= 0) {
                    setDialogState(() => dialogError = 'Choose a customer or pick one from the phonebook.');
                    return;
                  }
                  if (locationId == null || locationId! <= 0) {
                    setDialogState(() => dialogError = 'Choose the store receiving this deposit.');
                    return;
                  }
                  if ((double.tryParse(amount.text.trim()) ?? 0) <= 0) {
                    setDialogState(() => dialogError = 'Enter a valid deposit amount.');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || customerId == null || locationId == null) {
      search.dispose();
      amount.dispose();
      note.dispose();
      return;
    }
    final amountValue = double.tryParse(amount.text) ?? 0;
    final noteValue = note.text.trim();
    search.dispose();
    amount.dispose();
    note.dispose();
    await _api(widget.appState).createPrepayment({
      'location_id': locationId,
      'customer_id': customerId,
      'amount': amountValue,
      'method': method,
      if (noteValue.isNotEmpty) 'note': noteValue,
    });
    _showMessage('Deposit recorded');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = (((_data?['prepayments'] as List?) ?? const [])).cast<Map>();
    final releases = (((_data?['releases'] as List?) ?? const [])).cast<Map>();
    final filter = _filterCtrl.text.trim().toLowerCase();
    final filteredRows = rows.where((row) {
      if (filter.isEmpty) return true;
      final hay = '${row['customer_name'] ?? ''} ${row['location_name'] ?? ''} ${row['status'] ?? ''} ${row['method'] ?? ''}'.toLowerCase();
      return hay.contains(filter);
    }).toList();
    final availableTotal = filteredRows.fold<double>(
      0,
      (sum, row) => sum + _opsDouble(row['available_balance'] ?? row['amount']),
    );
    return MobilePageScaffold(
      title: 'Prepayments',
      subtitle: '',
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MobileSearchField(
                  controller: _filterCtrl,
                  hintText: 'Search deposits',
                  onSearch: () => setState(() {}),
                  onChanged: (_) {},
                  showActionButton: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Deposits: ${filteredRows.length}'),
                MobileMetricChip('Available: ${_opsMoney(availableTotal)}'),
                MobileMetricChip('Releases: ${releases.length}'),
              ],
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.inventory_rounded,
              title: 'Release Goods',
              trailing: FilledButton.tonal(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReleaseGoodsScreen(appState: widget.appState)),
                ).then((_) => _load()),
                child: const Text('Open'),
              ),
              child: Row(
                children: [
                  Expanded(child: MobileLabelValue(label: 'Deposits', value: '${rows.length}')),
                  Expanded(child: MobileLabelValue(label: 'Releases', value: '${releases.length}')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...filteredRows.map((row) => MobileSectionCard(
                  icon: Icons.payments_rounded,
                  title: '${row['customer_name'] ?? '-'}',
                  subtitle: '${row['location_name'] ?? '-'} | ${(row['method'] ?? 'CASH').toString()}',
                  child: Row(
                    children: [
                      Expanded(child: MobileLabelValue(label: 'Amount', value: '${row['amount'] ?? 0}')),
                      Expanded(child: MobileLabelValue(label: 'Available', value: '${row['available_balance'] ?? row['amount'] ?? 0}')),
                      Expanded(child: MobileLabelValue(label: 'Status', value: '${row['status'] ?? '-'}')),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class UsersPermissionsScreen extends StatefulWidget {
  final AppState appState;
  const UsersPermissionsScreen({super.key, required this.appState});

  @override
  State<UsersPermissionsScreen> createState() => _UsersPermissionsScreenState();
}

class _UsersPermissionsScreenState extends State<UsersPermissionsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await _api(widget.appState).getUsers();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    String role = 'TELLER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Add User'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: password, decoration: const InputDecoration(labelText: 'Temporary Password')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Tenant Admin')),
                  DropdownMenuItem(value: 'SHOP_ADMIN', child: Text('Shop Admin')),
                  DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                  DropdownMenuItem(value: 'TELLER', child: Text('Teller')),
                ],
                onChanged: (value) => role = value ?? 'TELLER',
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty || email.text.trim().isEmpty || password.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name, email, and temporary password are required.')),
        );
      }
      return;
    }
    if (password.text.trim().length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary passwords must be at least 8 characters.')),
        );
      }
      return;
    }
    try {
      await _api(widget.appState).createUser({
        'name': name.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
        'role': role,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Users and Permissions',
      subtitle: 'Manage live users and their role-based access.',
      floatingActionButton: FloatingActionButton(
        onPressed: _addUser,
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ..._rows.map((row) => MobileSectionCard(
                icon: Icons.admin_panel_settings_rounded,
                title: '${row['name'] ?? '-'}',
                subtitle: '${row['email'] ?? '-'}',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MobileMetricChip('Role: ${row['role'] ?? '-'}'),
                    MobileMetricChip('Active: ${row['active'] == 1 ? 'Yes' : 'No'}'),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
