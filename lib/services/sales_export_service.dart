import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';

class SalesExportService {
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

  static String _paymentStatusLabel(dynamic value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'partial':
      case 'partially_paid':
        return 'Partially Paid';
      case 'unpaid':
        return 'Unpaid';
      default:
        return 'Paid in Full';
    }
  }

  static String _safeFilePart(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  static Future<Directory> ensureLocalSaleDirectory() async {
    Directory? baseDirectory;

    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      final externalPath = externalDirectory?.path;
      if (externalPath != null) {
        const marker = '/Android/data/';
        final markerIndex = externalPath.indexOf(marker);
        if (markerIndex != -1) {
          final storageRoot = externalPath.substring(0, markerIndex);
          final packagePath = externalPath.substring(
            markerIndex + marker.length,
          );
          final packageName = packagePath.split('/').first;

          if (packageName.isNotEmpty) {
            baseDirectory = Directory(
              path.join(storageRoot, 'Android', 'media', packageName, 'sale'),
            );
          }
        }
      }
    }

    baseDirectory ??= await getDownloadsDirectory();
    baseDirectory ??= await getApplicationDocumentsDirectory();

    if (!await baseDirectory.exists()) {
      await baseDirectory.create(recursive: true);
    }

    if (path.basename(baseDirectory.path) != 'sale') {
      baseDirectory = Directory(path.join(baseDirectory.path, 'sale'));
    }

    if (!await baseDirectory.exists()) {
      await baseDirectory.create(recursive: true);
    }

    return baseDirectory;
  }

  static Future<Directory> ensureShareDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    final shareDirectory = Directory(
      path.join(temporaryDirectory.path, 'sale'),
    );
    if (!await shareDirectory.exists()) {
      await shareDirectory.create(recursive: true);
    }
    return shareDirectory;
  }

  static Future<File> saveCsvExport({
    required List<Map<String, dynamic>> rows,
    required String exportLabel,
    Directory? targetDirectory,
  }) async {
    final directory = targetDirectory ?? await ensureLocalSaleDirectory();
    final csv = StringBuffer(
      "Bill No,Customer,Phone,Product,Units,Returned Units,Selling Price,Discount,Net Total,Returned Amount,Net Profit,Payment Status,Payment Method,Amount Paid,Due Amount,Date\n",
    );

    for (final row in rows) {
      csv.writeln(
        [
          _csvCell(row['bill_number']),
          _csvCell(row['customer_name']),
          _csvCell(row['customer_phone']),
          _csvCell(row['product_name']),
          _csvCell(row['units']),
          _csvCell(row['returned_units']),
          _csvCell(_formatAmount(_asDouble(row['selling_price']))),
          _csvCell(_formatAmount(_asDouble(row['discount']))),
          _csvCell(_formatAmount(_asDouble(row['total']))),
          _csvCell(_formatAmount(_asDouble(row['returned_total']))),
          _csvCell(_formatAmount(_asDouble(row['profit']))),
          _csvCell(_paymentStatusLabel(row['payment_status'])),
          _csvCell(row['payment_method']),
          _csvCell(_formatAmount(_asDouble(row['amount_paid']))),
          _csvCell(_formatAmount(_asDouble(row['due_amount']))),
          _csvCell(row['date']),
        ].join(','),
      );
    }

    final fileName =
        'sales_export_${_safeFilePart(exportLabel)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File(path.join(directory.path, fileName));
    await file.writeAsString(csv.toString());
    return file;
  }

  static Future<File> savePdfExport({
    required List<Map<String, dynamic>> orders,
    required String exportLabel,
    required String reportTitle,
    Directory? targetDirectory,
  }) async {
    final directory = targetDirectory ?? await ensureLocalSaleDirectory();
    final storeDetails = await DatabaseHelper.instance.getStoreDetails();
    final document = pw.Document();
    final generatedAt = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(24),
          pageFormat: PdfPageFormat.a4.landscape,
        ),
        build: (context) {
          return [
            pw.Text(
              storeDetails['store_name']?.trim().isNotEmpty == true
                  ? storeDetails['store_name']!.trim()
                  : 'Sale Buddy',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Sales History Export',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(reportTitle),
            pw.Text('Generated: $generatedAt'),
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
              columnWidths: {
                0: const pw.FlexColumnWidth(1.1),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(2.1),
                3: const pw.FlexColumnWidth(0.6),
                4: const pw.FlexColumnWidth(0.7),
                5: const pw.FlexColumnWidth(0.9),
                6: const pw.FlexColumnWidth(0.9),
                7: const pw.FlexColumnWidth(0.9),
                8: const pw.FlexColumnWidth(1.5),
                9: const pw.FlexColumnWidth(0.9),
                10: const pw.FlexColumnWidth(1.2),
              },
              headers: const [
                'Bill No',
                'Customer',
                'Products',
                'Items',
                'Units',
                'Returned',
                'Amount',
                'Due',
                'Payment',
                'Profit',
                'Date',
              ],
              data: orders.map((order) {
                final customer =
                    order['customer_name']?.toString().trim().isNotEmpty == true
                    ? order['customer_name'].toString().trim()
                    : 'Walk-in Customer';
                return [
                  order['bill_number']?.toString().trim().isNotEmpty == true
                      ? order['bill_number'].toString().trim()
                      : 'Sale #${order['id']}',
                  customer,
                  order['product_names']?.toString() ?? '',
                  _asInt(order['item_count']).toString(),
                  _asInt(order['total_units']).toString(),
                  _formatCurrency(order['returned_total']),
                  _formatCurrency(order['total']),
                  _formatCurrency(order['due_amount']),
                  '${_paymentStatusLabel(order['payment_status'])} • ${order['payment_method']?.toString().trim().isNotEmpty == true ? order['payment_method'].toString().trim() : 'Cash'}',
                  _formatCurrency(order['profit']),
                  order['date']?.toString() ?? '',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    final fileName =
        'sales_export_${_safeFilePart(exportLabel)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File(path.join(directory.path, fileName));
    await file.writeAsBytes(await document.save());
    return file;
  }

  static String _csvCell(dynamic value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }
}
