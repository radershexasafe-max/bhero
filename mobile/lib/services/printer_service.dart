import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../theme/brand.dart';

class PairedPrinter {
  final String name;
  final String macAddress;

  const PairedPrinter({
    required this.name,
    required this.macAddress,
  });
}

class ReceiptBranding {
  final String phone;
  final String email;
  final String address;
  final String logoPath;

  const ReceiptBranding({
    this.phone = '',
    this.email = '',
    this.address = '',
    this.logoPath = '',
  });
}

class PrinterService {
  static const _kPrinterMac = 'printer_mac';
  static const _kReceiptPhone = 'receipt_phone';
  static const _kReceiptEmail = 'receipt_email';
  static const _kReceiptAddress = 'receipt_address';
  static const _kReceiptLogoPath = 'receipt_logo_path';

  Future<String?> getSavedPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPrinterMac);
  }

  Future<void> savePrinterMac(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrinterMac, mac);
  }

  Future<ReceiptBranding> getReceiptBranding() async {
    final prefs = await SharedPreferences.getInstance();
    return ReceiptBranding(
      phone: prefs.getString(_kReceiptPhone) ?? '',
      email: prefs.getString(_kReceiptEmail) ?? '',
      address: prefs.getString(_kReceiptAddress) ?? '',
      logoPath: prefs.getString(_kReceiptLogoPath) ?? '',
    );
  }

  Future<void> saveReceiptBranding(ReceiptBranding branding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReceiptPhone, branding.phone.trim());
    await prefs.setString(_kReceiptEmail, branding.email.trim());
    await prefs.setString(_kReceiptAddress, branding.address.trim());
    await prefs.setString(_kReceiptLogoPath, branding.logoPath.trim());
  }

  String _safePrinterName(dynamic device) {
    if (device is Map) {
      final name = (device['name'] ?? device['device_name'] ?? '').toString().trim();
      return name.isEmpty ? 'Unknown Printer' : name;
    }
    try {
      final name = '${device.name ?? ''}'.trim();
      return name.isEmpty ? 'Unknown Printer' : name;
    } catch (_) {
      return 'Unknown Printer';
    }
  }

  String _safePrinterMac(dynamic device) {
    if (device is Map) {
      return (device['macAdress'] ?? device['macAddress'] ?? device['address'] ?? '')
          .toString()
          .trim();
    }
    try {
      final mac = '${device.macAdress ?? ''}'.trim();
      if (mac.isNotEmpty) return mac;
    } catch (_) {}
    try {
      final mac = '${device.macAddress ?? ''}'.trim();
      if (mac.isNotEmpty) return mac;
    } catch (_) {}
    return '';
  }

  Future<List<PairedPrinter>> getPairedDevices() async {
    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return const [];
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      final devices = <PairedPrinter>[];
      for (final device in paired) {
        final macAddress = _safePrinterMac(device);
        if (macAddress.isEmpty) continue;
        devices.add(
          PairedPrinter(
            name: _safePrinterName(device),
            macAddress: macAddress,
          ),
        );
      }
      devices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return devices;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> connect(String mac) async {
    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return false;
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (ok) {
        await savePrinterMac(mac);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _fetchLogo(String? logoPath) async {
    final resolved = resolveBrandLogoPath(overrideLogoPath: logoPath);
    if (resolved.trim().isEmpty) return null;
    try {
      if (isBundledBrandAsset(resolved)) {
        final data = await rootBundle.load(resolved);
        return data.buffer.asUint8List();
      }
      final uri = Uri.tryParse(resolved);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final res = await http.get(uri);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return res.bodyBytes;
        }
      } else {
        final file = File(resolved);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> saveReceiptPdf({
    required Tenant tenant,
    required String title,
    required List<CartItem> items,
    required double total,
    String? saleNumber,
    String? note,
    String? cashierName,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
  }) async {
    final pdf = pw.Document();
    final branding = await getReceiptBranding();
    final receiptLogoPath = resolveBrandLogoPath(
      overrideLogoPath: branding.logoPath,
      tenantLogoPath: tenant.logoPath,
    );
    final logoBytes = await _fetchLogo(receiptLogoPath);
    final now = DateTime.now();
    final lineTotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logoBytes != null)
                pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    height: 42,
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
              if (branding.phone.trim().isNotEmpty)
                pw.Center(child: pw.Text(branding.phone.trim())),
              if (branding.email.trim().isNotEmpty)
                pw.Center(child: pw.Text(branding.email.trim())),
              if (branding.address.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    branding.address.trim(),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  title,
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Receipt: ${saleNumber ?? '-'}'),
              pw.Text('Date: ${now.toIso8601String().replaceFirst('T', ' ').substring(0, 16)}'),
              if ((cashierName ?? '').isNotEmpty) pw.Text('Cashier: $cashierName'),
              if ((customerName ?? '').isNotEmpty) pw.Text('Customer: $customerName'),
              if ((customerPhone ?? '').isNotEmpty) pw.Text('Phone: $customerPhone'),
              if ((customerEmail ?? '').isNotEmpty) pw.Text('Email: $customerEmail'),
              if ((customerAddress ?? '').isNotEmpty) pw.Text('Address: $customerAddress'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              ...items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(item.product.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${item.qty} x ${item.product.sellPrice.toStringAsFixed(2)}'),
                          pw.Text(item.lineTotal.toStringAsFixed(2)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              _pdfLine('Subtotal', lineTotal),
              if ((discount ?? 0) > 0) _pdfLine('Discount', -(discount ?? 0)),
              _pdfLine('Total', total, bold: true),
              if ((amountPaid ?? 0) > 0) _pdfLine('Amount Paid', amountPaid ?? 0),
              if ((paymentMethod ?? '').isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text('Payment: $paymentMethod'),
                ),
              if ((note ?? '').isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10),
                  child: pw.Text(note!),
                ),
              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                  'T.One',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                ),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/receipt_${saleNumber ?? now.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file.path;
  }

  pw.Widget _pdfLine(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value.toStringAsFixed(2), style: style),
      ],
    );
  }

  Future<void> printReceipt({
    required Tenant tenant,
    required String title,
    required List<CartItem> items,
    required double total,
    String? saleNumber,
    String? note,
    String? cashierName,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? paymentMethod,
    double? amountPaid,
    double? discount,
  }) async {
    final connected = await isConnected();
    if (!connected) return;
    final branding = await getReceiptBranding();

    const enter = '\n';
    final now = DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 16);
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    Future<void> write(String text, {int size = 1}) async {
      await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: size, text: '$text$enter'),
      );
    }

    await write(tenant.name, size: 3);
    if (branding.phone.trim().isNotEmpty) await write(branding.phone.trim());
    if (branding.email.trim().isNotEmpty) await write(branding.email.trim());
    if (branding.address.trim().isNotEmpty) await write(branding.address.trim());
    await write('T.One', size: 2);
    await write(title, size: 2);
    if ((saleNumber ?? '').isNotEmpty) await write('Receipt: $saleNumber');
    await write('Date: $now');
    if ((cashierName ?? '').isNotEmpty) await write('Cashier: $cashierName');
    if ((customerName ?? '').isNotEmpty) await write('Customer: $customerName');
    if ((customerPhone ?? '').isNotEmpty) await write('Phone: $customerPhone');
    if ((customerEmail ?? '').isNotEmpty) await write('Email: $customerEmail');
    if ((customerAddress ?? '').isNotEmpty) await write('Address: $customerAddress');
    await write('--------------------------------');
    for (final item in items) {
      await write(item.product.name);
      await write('${item.qty} x ${item.product.sellPrice.toStringAsFixed(2)} = ${item.lineTotal.toStringAsFixed(2)}');
    }
    await write('--------------------------------');
    await write('Subtotal: ${subtotal.toStringAsFixed(2)}');
    if ((discount ?? 0) > 0) await write('Discount: ${(discount ?? 0).toStringAsFixed(2)}');
    await write('Total: ${total.toStringAsFixed(2)}', size: 2);
    if ((amountPaid ?? 0) > 0) await write('Amount Paid: ${(amountPaid ?? 0).toStringAsFixed(2)}');
    if ((paymentMethod ?? '').isNotEmpty) await write('Payment: $paymentMethod');
    if ((note ?? '').isNotEmpty) await write(note!);
    await write('');
    await write('');
  }
}
