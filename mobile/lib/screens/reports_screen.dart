import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../theme/brand.dart';
import '../widgets/simple_line_chart.dart';

class ReportsScreen extends StatefulWidget {
  final AppState appState;
  const ReportsScreen({super.key, required this.appState});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  final _saleTransactionsKey = GlobalKey();
  final _closeShiftKey = GlobalKey();
  final _stockDistributionKey = GlobalKey();
  final _stockOrdersKey = GlobalKey();
  final _stockReceivablesKey = GlobalKey();
  final _debtorsKey = GlobalKey();
  final _pricesKey = GlobalKey();
  bool _loading = false;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  int? _locationId;
  Map<String, dynamic>? _bundle;

  ApiClient get api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getBaleReportsDashboard(
        from: _fmt.format(_from),
        to: _fmt.format(_to),
        locationId: _locationId,
      );
      if (!mounted) return;
      setState(() => _bundle = data);
    } catch (e) {
      _showMessage(
        ApiClient.friendlyError(
          e,
          fallback: 'Check your internet connection and tap Reload to try again.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is List) {
      return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  double _num(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0.0;
  }
  String _money(dynamic value) => '\$${_num(value).toStringAsFixed(2)}';
  String _count(dynamic value) => _num(value).toStringAsFixed(0);
  String _seriesDate(Map<String, dynamic> row) {
    return (row['date'] ??
            row['business_date'] ??
            row['expense_date'] ??
            row['period_date'] ??
            row['d'] ??
            '')
        .toString();
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

  Future<void> _jumpTo(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  pw.Widget _pdfMetric(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _shareReportPdf() async {
    if (_bundle == null) {
      _showMessage('Generate bale reports first.', error: true);
      return;
    }

    try {
      final summary = _map(_bundle?['summary']);
      final stockDistribution = _map(_bundle?['stock_distribution']);
      final stockOrders = _map(_bundle?['stock_orders']);
      final stockReceivables = _map(_bundle?['stock_receivables']);
      final creditors = _map(_bundle?['creditors']);
      final debtors = _map(_bundle?['debtors']);
      final prices = _map(_bundle?['prices']);
      final saleTransactions = _map(_bundle?['sale_transactions']);
      final closeShift = _map(_bundle?['close_shift']);
      String? locationName;
      for (final row in widget.appState.accessibleLocations) {
        if (row.id == _locationId) {
          locationName = row.name;
          break;
        }
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text(
        'T.One - Bale Reports',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Period: ${_fmt.format(_from)} to ${_fmt.format(_to)}'),
            pw.Text('Location: ${locationName ?? 'All locations'}'),
            pw.SizedBox(height: 16),
            pw.Header(level: 1, text: 'Overview'),
            _pdfMetric('Sales', _money(summary['total_sales'])),
            _pdfMetric('Net Profit', _money(summary['net_profit'])),
            _pdfMetric('Transactions', _count(_map(saleTransactions['summary'])['transactions_count'])),
            _pdfMetric('Stock Value', _money(_map(stockDistribution['summary'])['stock_value'])),
            pw.SizedBox(height: 12),
            pw.Header(level: 1, text: 'Close Shift'),
            _pdfMetric('Sessions', _count(_map(closeShift['summary'])['sessions_total'])),
            _pdfMetric('Bales Sold', _count(_map(closeShift['summary'])['bales_sold'])),
            _pdfMetric('Cash In Hand', _money(_map(closeShift['summary'])['total_cash_inhand'])),
            _pdfMetric('Credit Sales', _money(_map(closeShift['summary'])['total_credit_sales'])),
            pw.SizedBox(height: 12),
            pw.Header(level: 1, text: 'Stock'),
            _pdfMetric('Distribution Units', _count(_map(stockDistribution['summary'])['units'])),
            _pdfMetric('Orders Outstanding', _count(_map(stockOrders['summary'])['quantity_outstanding'])),
            _pdfMetric('Open Stock Orders', _count(_map(stockReceivables['summary'])['open_orders'])),
            _pdfMetric('Received Bales', _count(_map(stockReceivables['summary'])['received_bales'])),
            pw.SizedBox(height: 12),
            pw.Header(level: 1, text: 'Balances'),
            _pdfMetric('Creditors', _money(_map(creditors['summary'])['outstanding_value'])),
            _pdfMetric('Debtors', _money(_map(debtors['summary'])['outstanding_value'])),
            pw.SizedBox(height: 12),
            pw.Header(level: 1, text: 'Prices'),
            _pdfMetric('Items', _count(_map(prices['summary'])['item_count'])),
            _pdfMetric('Average Cost', _money(_map(prices['summary'])['avg_cost'])),
            _pdfMetric('Average Sell', _money(_map(prices['summary'])['avg_sell'])),
          ],
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/bale_report_${_fmt.format(_from)}_${_fmt.format(_to)}.pdf');
      await file.writeAsBytes(await pdf.save(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Bale report for ${_fmt.format(_from)} to ${_fmt.format(_to)}',
      );
    } catch (error) {
      _showMessage('Could not share bale reports: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _map(_bundle?['summary']);
    final series = _rows(_bundle?['series']);
    final byLocation = _rows(_bundle?['by_location']);
    final saleTransactions = _map(_bundle?['sale_transactions']);
    final closeShift = _map(_bundle?['close_shift']);
    final stockDistribution = _map(_bundle?['stock_distribution']);
    final stockOrders = _map(_bundle?['stock_orders']);
    final stockReceivables = _map(_bundle?['stock_receivables']);
    final creditors = _map(_bundle?['creditors']);
    final debtors = _map(_bundle?['debtors']);
    final prices = _map(_bundle?['prices']);

    final overviewSales = series.map((row) => _num(row['sales'])).toList();
    final overviewNetProfit = series.map((row) => _num(row['net_profit'])).toList();
    final overviewExpenses = series.map((row) => _num(row['expenses'])).toList();
    final overviewDates = series.map(_seriesDate).toList();
    final closeShiftDaily = _rows(closeShift['daily_cash']);
    final shiftCash = closeShiftDaily.map((row) => _num(row['counted_cash'])).toList();
    final shiftCashDates = closeShiftDaily.map(_seriesDate).toList();
    final stockOrderRows = _rows(stockOrders['timeline']);
    final stockOrderTrend = stockOrderRows.map((row) => _num(row['quantity_ordered'])).toList();
    final stockOrderDates = stockOrderRows.map(_seriesDate).toList();
    final stockReceiptRows = _rows(stockReceivables['receipt_timeline']);
    final stockReceiptsTrend = stockReceiptRows.map((row) => _num(row['received_bales'])).toList();
    final stockReceiptDates = stockReceiptRows.map(_seriesDate).toList();
    final collectionRows = _rows(debtors['collections']);
    final collectionsTrend = collectionRows.map((row) => _num(row['collected_amount'])).toList();
    final collectionDates = collectionRows.map(_seriesDate).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 204,
              backgroundColor: BrandColors.primary,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [BrandColors.primary, BrandColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 68, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'Bale Reports',
                        style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sales, shifts, stock, balances, and pricing from your web system.',
                        style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 14, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Report Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _DateButton(label: 'From', value: _fmt.format(_from), onTap: _pickFrom)),
                                const SizedBox(width: 10),
                                Expanded(child: _DateButton(label: 'To', value: _fmt.format(_to), onTap: _pickTo)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int?>(
                              value: _locationId,
                              decoration: const InputDecoration(labelText: 'Location'),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('All locations')),
                                ...widget.appState.accessibleLocations.map(
                                  (location) => DropdownMenuItem<int?>(
                                    value: location.id,
                                    child: Text('${location.name} (${location.type})'),
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(() => _locationId = value),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _loading ? null : _load,
                                    icon: const Icon(Icons.bar_chart_rounded),
                                    label: const Text('Generate'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      backgroundColor: const Color(0xFFE31B23),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _loading || _bundle == null ? null : _shareReportPdf,
                                    icon: const Icon(Icons.picture_as_pdf_rounded),
                                    label: const Text('Export PDF'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      backgroundColor: const Color(0xFF2E7D32),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(onPressed: () => _jumpTo(_saleTransactionsKey), child: const Text('Sale Transactions')),
                                OutlinedButton(onPressed: () => _jumpTo(_closeShiftKey), child: const Text('Close Shift')),
                                OutlinedButton(onPressed: () => _jumpTo(_stockDistributionKey), child: const Text('Stock Distribution')),
                                OutlinedButton(onPressed: () => _jumpTo(_stockOrdersKey), child: const Text('Stock Orders')),
                                OutlinedButton(onPressed: () => _jumpTo(_stockReceivablesKey), child: const Text('Stock Receivables')),
                                OutlinedButton(onPressed: () => _jumpTo(_debtorsKey), child: const Text('Debtors')),
                                OutlinedButton(onPressed: () => _jumpTo(_pricesKey), child: const Text('Prices')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                  ],
                ),
              ),
            ),
            if (!_loading && _bundle == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Run a report to load bale report data.'))),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(title: 'Sales', value: _money(summary['total_sales']), icon: Icons.payments_rounded, accent: const Color(0xFFE31B23)),
                          _MetricCard(title: 'Net Profit', value: _money(summary['net_profit']), icon: Icons.trending_up_rounded, accent: const Color(0xFF2E7D32)),
                          _MetricCard(title: 'Stock Value', value: _money(_map(stockDistribution['summary'])['stock_value']), icon: Icons.inventory_2_rounded, accent: const Color(0xFF1565C0)),
                          _MetricCard(title: 'Debtors', value: _money(_map(debtors['summary'])['outstanding_value']), icon: Icons.account_balance_wallet_rounded, accent: const Color(0xFF8E24AA)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.insights_rounded,
                        title: 'Overview',
                        subtitle: '${_fmt.format(_from)} to ${_fmt.format(_to)}',
                        child: Column(
                          children: [
                            SimpleLineChart(
                              values: overviewSales,
                              title: 'Sales',
                              xLabels: overviewDates,
                            ),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: overviewNetProfit,
                              title: 'Net Profit',
                              xLabels: overviewDates,
                            ),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: overviewExpenses,
                              title: 'Expenses',
                              xLabels: overviewDates,
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Sales by location',
                              rows: byLocation,
                              labelBuilder: (row) => (row['name'] ?? 'Location').toString(),
                              valueBuilder: (row) => _num(row['sales']),
                              valueFormatter: _money,
                              color: const Color(0xFFE31B23),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.receipt_long_rounded,
                        title: 'Sale Transactions',
                        subtitle: 'Gross, collected, and recent transactions',
                        key: _saleTransactionsKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Transactions: ${_count(_map(saleTransactions['summary'])['transactions_count'])}',
                              'Gross: ${_money(_map(saleTransactions['summary'])['gross_total'])}',
                              'Received: ${_money(_map(saleTransactions['summary'])['amount_received'])}',
                              'Outstanding: ${_money(_map(saleTransactions['summary'])['outstanding_balance'])}',
                            ]),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: _rows(saleTransactions['daily']).map((row) => _num(row['gross_total'])).toList(),
                              title: 'Sales total by day',
                              xLabels: _rows(saleTransactions['daily']).map(_seriesDate).toList(),
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Payment mix',
                              rows: _rows(saleTransactions['payment_mix']),
                              labelBuilder: (row) => (row['method'] ?? 'Unknown').toString(),
                              valueBuilder: (row) => _num(row['total_amount']),
                              valueFormatter: _money,
                              color: const Color(0xFF2E7D32),
                            ),
                            const SizedBox(height: 16),
                            _MiniDataTable(
                              headers: const ['Sale', 'Customer', 'Total', 'Paid'],
                              rows: _rows(saleTransactions['recent']).take(6).map((row) => [
                                (row['sale_number'] ?? '').toString(),
                                (row['customer_name'] ?? '').toString(),
                                _money(row['total']),
                                _money(row['amount_paid']),
                              ]).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.lock_clock_rounded,
                        title: 'Close Shift Report',
                        subtitle: 'Cash and shift performance',
                        key: _closeShiftKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Sessions: ${_count(_map(closeShift['summary'])['sessions_total'])}',
                              'Bales sold: ${_count(_map(closeShift['summary'])['bales_sold'])}',
                              'Returns: ${_count(_map(closeShift['summary'])['bales_returned'])}',
                              'Cash in hand: ${_money(_map(closeShift['summary'])['total_cash_inhand'])}',
                              'EcoCash: ${_money(_map(closeShift['summary'])['ecocash_received'])}',
                              'Credit sales: ${_money(_map(closeShift['summary'])['total_credit_sales'])}',
                            ]),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: shiftCash,
                              title: 'Closing cash trend',
                              xLabels: shiftCashDates,
                            ),
                            const SizedBox(height: 16),
                            _MiniDataTable(
                              headers: const ['Date', 'Location', 'Cash', 'Variance'],
                              rows: _rows(closeShift['sessions']).take(6).map((row) => [
                                (row['business_date'] ?? '').toString(),
                                (row['location_name'] ?? '').toString(),
                                _money(row['counted_cash']),
                                _money(row['variance_cash']),
                              ]).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.account_tree_rounded,
                        title: 'Stock Distribution',
                        subtitle: 'Current stock spread and value',
                        key: _stockDistributionKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Items: ${_count(_map(stockDistribution['summary'])['item_count'])}',
                              'Units: ${_count(_map(stockDistribution['summary'])['units'])}',
                              'Value: ${_money(_map(stockDistribution['summary'])['stock_value'])}',
                            ]),
                            const SizedBox(height: 14),
                            _BarSummaryList(
                              title: 'By location',
                              rows: _rows(stockDistribution['by_location']),
                              labelBuilder: (row) => (row['name'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['stock_value']),
                              valueFormatter: _money,
                              color: const Color(0xFF1565C0),
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Top categories',
                              rows: _rows(stockDistribution['by_category']),
                              labelBuilder: (row) => (row['category_name'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['units']),
                              valueFormatter: (value) => _count(value),
                              color: const Color(0xFF00897B),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.local_shipping_rounded,
                        title: 'Stock Orders',
                        subtitle: 'Ordered, received, and outstanding',
                        key: _stockOrdersKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Orders: ${_count(_map(stockOrders['summary'])['orders_count'])}',
                              'Ordered: ${_count(_map(stockOrders['summary'])['quantity_ordered'])}',
                              'Received: ${_count(_map(stockOrders['summary'])['quantity_received'])}',
                              'Outstanding: ${_count(_map(stockOrders['summary'])['quantity_outstanding'])}',
                            ]),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: stockOrderTrend,
                              title: 'Ordered quantity trend',
                              xLabels: stockOrderDates,
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Order statuses',
                              rows: _rows(stockOrders['status_rows']),
                              labelBuilder: (row) => (row['status'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['total_orders']),
                              valueFormatter: (value) => _count(value),
                              color: const Color(0xFF6A1B9A),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.move_down_rounded,
                        title: 'Stock Receivables',
                        subtitle: 'Outstanding bale receipts and received trend',
                        key: _stockReceivablesKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Open orders: ${_count(_map(stockReceivables['summary'])['open_orders'])}',
                              'Outstanding qty: ${_count(_map(stockReceivables['summary'])['quantity_outstanding'])}',
                              'Received bales: ${_count(_map(stockReceivables['summary'])['received_bales'])}',
                            ]),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: stockReceiptsTrend,
                              title: 'Received bales trend',
                              xLabels: stockReceiptDates,
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Outstanding by category',
                              rows: _rows(stockReceivables['outstanding_by_category']),
                              labelBuilder: (row) => (row['category_name'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['quantity_outstanding']),
                              valueFormatter: (value) => _count(value),
                              color: const Color(0xFFEF6C00),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.people_alt_rounded,
                        title: 'Creditors and Debtors',
                        subtitle: 'Who is owed and who still owes you',
                        key: _debtorsKey,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _InnerMetricBox(
                                    title: 'Creditors',
                                    primary: _money(_map(creditors['summary'])['outstanding_value']),
                                    secondary: '${_count(_map(creditors['summary'])['supplier_count'])} suppliers',
                                    accent: const Color(0xFFBF360C),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _InnerMetricBox(
                                    title: 'Debtors',
                                    primary: _money(_map(debtors['summary'])['outstanding_value']),
                                    secondary: '${_count(_map(debtors['summary'])['customer_count'])} customers',
                                    accent: const Color(0xFF8E24AA),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SimpleLineChart(
                              values: collectionsTrend,
                              title: 'Debt collections trend',
                              xLabels: collectionDates,
                            ),
                            const SizedBox(height: 16),
                            _BarSummaryList(
                              title: 'Top debtor balances',
                              rows: _rows(debtors['rows']),
                              labelBuilder: (row) => (row['customer_name'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['outstanding_value']),
                              valueFormatter: _money,
                              color: const Color(0xFF8E24AA),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        icon: Icons.sell_rounded,
                        title: 'Prices',
                        subtitle: 'Selling prices and margins',
                        key: _pricesKey,
                        child: Column(
                          children: [
                            _InfoWrap(values: [
                              'Items: ${_count(_map(prices['summary'])['item_count'])}',
                              'Average cost: ${_money(_map(prices['summary'])['avg_cost'])}',
                              'Average sell: ${_money(_map(prices['summary'])['avg_sell'])}',
                            ]),
                            const SizedBox(height: 14),
                            _BarSummaryList(
                              title: 'Average selling price by category',
                              rows: _rows(prices['category_averages']),
                              labelBuilder: (row) => (row['category_name'] ?? '').toString(),
                              valueBuilder: (row) => _num(row['avg_sell']),
                              valueFormatter: _money,
                              color: const Color(0xFF283593),
                            ),
                            const SizedBox(height: 16),
                            _MiniDataTable(
                              headers: const ['Item', 'Sell', 'Margin', 'Stock'],
                              rows: _rows(prices['rows']).take(8).map((row) => [
                                (row['product_name'] ?? '').toString(),
                                _money(row['sell_price']),
                                _money(row['margin_amount']),
                                _count(row['stock_on_hand']),
                              ]).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F6F3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFFE31B23)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accent.withOpacity(0.12),
                foregroundColor: accent,
                child: Icon(icon),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFFFEBEE),
                  foregroundColor: const Color(0xFFE31B23),
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoWrap extends StatelessWidget {
  final List<String> values;
  const _InfoWrap({required this.values});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          )
          .toList(),
    );
  }
}

class _InnerMetricBox extends StatelessWidget {
  final String title;
  final String primary;
  final String secondary;
  final Color accent;

  const _InnerMetricBox({
    required this.title,
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(primary, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(secondary, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _BarSummaryList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) labelBuilder;
  final double Function(Map<String, dynamic>) valueBuilder;
  final String Function(dynamic) valueFormatter;
  final Color color;

  const _BarSummaryList({
    required this.title,
    required this.rows,
    required this.labelBuilder,
    required this.valueBuilder,
    required this.valueFormatter,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final topRows = rows.take(6).toList();
    double maxValue = 0;
    for (final row in topRows) {
      final value = valueBuilder(row);
      if (value > maxValue) maxValue = value;
    }
    if (maxValue <= 0) maxValue = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (topRows.isEmpty)
          const Text('No data available')
        else
          ...topRows.map((row) {
            final value = valueBuilder(row);
            final ratio = (value / maxValue).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          labelBuilder(row),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(valueFormatter(value), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 10,
                      backgroundColor: color.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _MiniDataTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;

  const _MiniDataTable({
    required this.headers,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: headers
                  .map(
                    (header) => Expanded(
                      child: Text(
                        header,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No rows available'),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: row
                      .map(
                        (cell) => Expanded(
                          child: Text(
                            cell,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
