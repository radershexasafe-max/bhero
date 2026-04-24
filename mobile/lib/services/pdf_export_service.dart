import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';

class PdfExportService {
  Future<Uint8List?> _fetchLogo(String? logoPath) async {
    if (logoPath == null || logoPath.trim().isEmpty) return null;
    try {
      final uri = Uri.tryParse(logoPath.trim());
      if (uri == null) return null;
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        final res = await http.get(uri);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return res.bodyBytes;
        }
      } else {
        final file = File(uri.toFilePath());
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> saveStockTakeReportPdf({
    required Tenant tenant,
    required Map<String, dynamic> stockTake,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> rows,
  }) async {
    final pdf = pw.Document();
    final logoBytes = await _fetchLogo(tenant.logoPath);
    final reportId = stockTake['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          _header(
            tenant: tenant,
            title: 'STOCK TAKE REPORT',
            subtitle: 'Report #$reportId',
            logoBytes: logoBytes,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metaCard('Location', '${stockTake['location_name'] ?? '-'}')),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _metaCard('Started', '${stockTake['started_at'] ?? '-'}')),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _metaCard('Finalized', '${stockTake['finalized_at'] ?? '-'}')),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metricCard('Total Items', '${summary['total_items'] ?? 0}')),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Counted', '${summary['counted_items'] ?? 0}')),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('With Variance', '${summary['variance_items'] ?? 0}')),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Variance Value', _money(summary['variance_value']))),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headers: const ['Product', 'System', 'Counted', 'Variance', 'Cost Price', 'Variance Value'],
            data: rows
                .map(
                  (row) => [
                    '${row['product_name'] ?? ''}',
                    '${row['system_qty'] ?? 0}',
                    row['counted_qty'] == null ? '-' : '${row['counted_qty']}',
                    row['variance'] == null ? '-' : '${row['variance']}',
                    _money(row['cost_price']),
                    _money(row['variance_value']),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    return _save(pdf, 'stock_take_$reportId.pdf');
  }

  Future<String> saveCustomerStatementPdf({
    required Tenant tenant,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> loyaltyHistory,
  }) async {
    final pdf = pw.Document();
    final logoBytes = await _fetchLogo(tenant.logoPath);
    final customerId = customer['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          _header(
            tenant: tenant,
            title: 'CUSTOMER STATEMENT',
            subtitle: '${customer['name'] ?? 'Customer'}',
            logoBytes: logoBytes,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metaCard('Phone', '${customer['phone'] ?? '-'}')),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _metaCard('Email', '${customer['email'] ?? '-'}')),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(child: _metaCard('Address', '${customer['address'] ?? '-'}')),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _metaCard('Joined', '${customer['created_at'] ?? '-'}')),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metricCard('Loyalty Points', '${customer['loyalty_points'] ?? 0}')),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Total Spent', _money(customer['total_spent']))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Visits', '${customer['visit_count'] ?? 0}')),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Customer History', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (history.isEmpty)
            pw.Text('No customer history available yet.')
          else
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
              headers: const ['Date', 'Reference', 'Type', 'Amount', 'Balance', 'Location'],
              data: history
                  .map(
                    (row) => [
                      '${row['created_at'] ?? ''}',
                      '${row['sale_number'] ?? row['reference_number'] ?? ''}',
                      _historyType(row['entry_type']),
                      _money(row['amount_paid'] ?? row['total']),
                      _money(row['balance_due']),
                      '${row['location_name'] ?? ''}',
                    ],
                  )
                  .toList(),
            ),
          if (loyaltyHistory.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Loyalty History', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
              headers: const ['Date', 'Type', 'Points', 'Note'],
              data: loyaltyHistory
                  .map(
                    (row) => [
                      '${row['created_at'] ?? ''}',
                      '${row['type'] ?? ''}',
                      '${row['points'] ?? 0}',
                      '${row['note'] ?? ''}',
                    ],
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );

    return _save(pdf, 'customer_statement_$customerId.pdf');
  }

  Future<String> saveCustomerBalancePdf({
    required Tenant tenant,
    required Map<String, dynamic> balanceRow,
  }) async {
    final pdf = pw.Document();
    final logoBytes = await _fetchLogo(tenant.logoPath);
    final customerId = balanceRow['customer_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          _header(
            tenant: tenant,
            title: 'CUSTOMER BALANCE',
            subtitle: '${balanceRow['customer_name'] ?? 'Customer'}',
            logoBytes: logoBytes,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metaCard('Phone', '${balanceRow['customer_phone'] ?? '-'}')),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _metaCard('Email', '${balanceRow['customer_email'] ?? '-'}')),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(child: _metricCard('Total Sale Value', _money(balanceRow['total_sale_value']))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Amount Paid', _money(balanceRow['amount_paid']))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Balance Due', _money(balanceRow['balance_due']))),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(child: _metricCard('Credit Balance', _money(balanceRow['credit_balance_due']))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Prepayment Balance', _money(balanceRow['available_prepayment']))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _metricCard('Net Balance', _money(balanceRow['net_customer_balance']))),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'This balance statement includes open credit sales and customer prepayments recorded in T.One Bales.',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return _save(pdf, 'customer_balance_$customerId.pdf');
  }

  Future<String> savePrepaymentDepositReceiptPdf({
    required Tenant tenant,
    required Map<String, dynamic> prepayment,
    required Map<String, dynamic> payment,
  }) async {
    final pdf = pw.Document();
    final logoBytes = await _fetchLogo(tenant.logoPath);
    final prepaymentNumber = '${prepayment['layby_number'] ?? 'PREPAYMENT'}';
    final paymentId = payment['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(
              tenant: tenant,
              title: 'PREPAYMENT DEPOSIT RECEIPT',
              subtitle: prepaymentNumber,
              logoBytes: logoBytes,
            ),
            pw.SizedBox(height: 16),
            _metaCard('Customer', '${prepayment['customer_name'] ?? 'Walk-in'}'),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _metricCard('Deposit', _money(payment['amount']))),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _metricCard('Method', '${payment['method'] ?? '-'}')),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _metricCard('Paid So Far', _money(prepayment['paid_amount']))),
                pw.SizedBox(width: 8),
                pw.Expanded(child: _metricCard('Balance', _money(prepayment['balance']))),
              ],
            ),
            pw.SizedBox(height: 10),
            _metaCard('Payment Date', '${payment['created_at'] ?? '-'}'),
            pw.SizedBox(height: 10),
            _metaCard('Receipt Ref', 'PP-$paymentId'),
          ],
        ),
      ),
    );

    return _save(pdf, 'prepayment_deposit_$paymentId.pdf');
  }

  Future<String> _save(pw.Document pdf, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file.path;
  }

  String _money(dynamic value) {
    final parsed = double.tryParse('${value ?? ''}') ?? 0.0;
    return parsed.toStringAsFixed(2);
  }

  String _historyType(dynamic value) {
    switch ('${value ?? ''}'.toUpperCase()) {
      case 'SALE':
        return 'Sale';
      case 'CREDIT_PAYMENT':
        return 'Credit Payment';
      case 'LAYBY':
        return 'Prepayment';
      case 'LAYBY_PAYMENT':
        return 'Prepayment Deposit';
      case 'PREPAYMENT':
        return 'Prepayment';
      case 'PREPAYMENT_USE':
        return 'Prepayment Use';
      default:
        return '${value ?? '-'}';
    }
  }

  pw.Widget _header({
    required Tenant tenant,
    required String title,
    required String subtitle,
    required Uint8List? logoBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (logoBytes != null)
          pw.Center(
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              height: 44,
              fit: pw.BoxFit.contain,
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            tenant.name,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
          ),
        ),
        pw.Center(child: pw.Text(subtitle)),
      ],
    );
  }

  pw.Widget _metricCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _metaCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
