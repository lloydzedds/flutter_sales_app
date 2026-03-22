import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

class SaleBillService {
  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static String _formatCurrency(dynamic value) {
    return "Rs ${_formatAmount(_asDouble(value))}";
  }

  static String _safeFilePart(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  static Future<File> generatePdfBill({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
  }) async {
    final storeDetails = await DatabaseHelper.instance.getStoreDetails();
    final document = pw.Document();
    final billNumber =
        order['bill_number']?.toString().trim().isNotEmpty == true
        ? order['bill_number'].toString().trim()
        : "SALE-${order['id']}";
    final rawDate = order['date']?.toString() ?? '';

    document.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(28),
          pageFormat: PdfPageFormat.a4,
        ),
        build: (context) {
          return [
            pw.Text(
              storeDetails['store_name']?.trim().isNotEmpty == true
                  ? storeDetails['store_name']!.trim()
                  : 'Sales Manager',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            if (storeDetails['store_owner']?.trim().isNotEmpty == true)
              pw.Text('Owner: ${storeDetails['store_owner']!.trim()}'),
            if (storeDetails['store_phone']?.trim().isNotEmpty == true)
              pw.Text('Phone: ${storeDetails['store_phone']!.trim()}'),
            if (storeDetails['store_email']?.trim().isNotEmpty == true)
              pw.Text('Email: ${storeDetails['store_email']!.trim()}'),
            if (storeDetails['store_address']?.trim().isNotEmpty == true)
              pw.Text('Address: ${storeDetails['store_address']!.trim()}'),
            if (storeDetails['store_tax_id']?.trim().isNotEmpty == true)
              pw.Text('Tax ID: ${storeDetails['store_tax_id']!.trim()}'),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Invoice',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('Bill No: $billNumber'),
                  pw.Text('Date: $rawDate'),
                  pw.Text(
                    'Customer: ${order['customer_name']?.toString().trim().isNotEmpty == true ? order['customer_name'].toString().trim() : 'Walk-in Customer'}',
                  ),
                  if (order['customer_phone']?.toString().trim().isNotEmpty ==
                      true)
                    pw.Text(
                      'Phone: ${order['customer_phone'].toString().trim()}',
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF8B5FE8),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headers: const [
                'Product',
                'Qty',
                'Selling Price',
                'Discount',
                'Line Total',
              ],
              data: items.map((item) {
                return [
                  item['product_name']?.toString() ??
                      item['name']?.toString() ??
                      'Product',
                  _asInt(item['units']).toString(),
                  _formatCurrency(item['selling_price']),
                  _formatCurrency(item['discount']),
                  _formatCurrency(item['total']),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Summary',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Items: ${_asInt(order['item_count'])}  |  Units: ${_asInt(order['total_units'])}',
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Amount to Pay: ${_formatCurrency(order['total'])}',
                    ),
                  ],
                ),
              ),
            ),
            if (storeDetails['invoice_note']?.trim().isNotEmpty == true) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Note',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(storeDetails['invoice_note']!.trim()),
            ],
          ];
        },
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final filename =
        'invoice_${_safeFilePart(billNumber)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(await document.save());
    return file;
  }

  static Future<void> sharePdfBill({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
  }) async {
    final file = await generatePdfBill(order: order, items: items);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Invoice ${order['bill_number'] ?? order['id']}',
      ),
    );
  }
}
