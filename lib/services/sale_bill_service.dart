import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

class SaleBillService {
  static const PdfColor _invoiceAccent = PdfColor.fromInt(0xFF2F5D8A);
  static const PdfColor _invoiceAccentSoft = PdfColor.fromInt(0xFFEAF2FB);
  static const PdfColor _invoiceBorder = PdfColor.fromInt(0xFFD4DCE6);

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

  static String _customerName(Map<String, dynamic> order) {
    final name = order['customer_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Walk-in Customer' : name;
  }

  static String _paymentMethod(Map<String, dynamic> order) {
    final method = order['payment_method']?.toString().trim() ?? '';
    return method.isEmpty ? 'Cash' : method;
  }

  static String _formattedOrderDate(String rawDate) {
    if (rawDate.trim().isEmpty) return '--';

    try {
      return DateFormat(
        'd MMM yyyy, h:mm a',
      ).format(DateFormat('yyyy-MM-dd HH:mm').parseStrict(rawDate));
    } catch (_) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) return rawDate;
      return DateFormat('d MMM yyyy, h:mm a').format(parsed);
    }
  }

  static pw.Widget _labelValueRow(
    String label,
    String value, {
    bool emphasize = false,
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: emphasize ? 11.5 : 10.5,
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
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
    final customerName = _customerName(order);
    final customerPhone = order['customer_phone']?.toString().trim() ?? '';
    final grossTotal = _asDouble(order['gross_total'] ?? order['total']);
    final netTotal = _asDouble(order['total']);
    final returnedTotal = _asDouble(order['returned_total']);
    final amountPaid = _asDouble(order['amount_paid']);
    final dueAmount = _asDouble(order['due_amount']);
    final totalUnits = _asInt(order['total_units']);
    final itemCount = _asInt(order['item_count']);

    document.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(28),
          pageFormat: PdfPageFormat.a4,
        ),
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _invoiceBorder, width: 1),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              storeDetails['store_name']?.trim().isNotEmpty == true
                                  ? storeDetails['store_name']!.trim()
                                  : 'Sale Buddy',
                              style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                                color: _invoiceAccent,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            if (storeDetails['store_owner']?.trim().isNotEmpty ==
                                true)
                              pw.Text(
                                storeDetails['store_owner']!.trim(),
                                style: const pw.TextStyle(fontSize: 10.5),
                              ),
                            if (storeDetails['store_phone']?.trim().isNotEmpty ==
                                true)
                              pw.Text(
                                storeDetails['store_phone']!.trim(),
                                style: const pw.TextStyle(fontSize: 10.5),
                              ),
                            if (storeDetails['store_email']?.trim().isNotEmpty ==
                                true)
                              pw.Text(
                                storeDetails['store_email']!.trim(),
                                style: const pw.TextStyle(fontSize: 10.5),
                              ),
                            if (storeDetails['store_address']?.trim().isNotEmpty ==
                                true)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  storeDetails['store_address']!.trim(),
                                  style: const pw.TextStyle(fontSize: 10.5),
                                ),
                              ),
                            if (storeDetails['store_tax_id']?.trim().isNotEmpty ==
                                true)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  'Tax ID: ${storeDetails['store_tax_id']!.trim()}',
                                  style: const pw.TextStyle(fontSize: 10),
                                ),
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Container(
                        width: 180,
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: _invoiceAccentSoft,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: _invoiceBorder),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'INVOICE',
                              style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: _invoiceAccent,
                                letterSpacing: 1.1,
                              ),
                            ),
                            pw.SizedBox(height: 8),
                            _labelValueRow('Bill No', billNumber, emphasize: true),
                            _labelValueRow(
                              'Date',
                              _formattedOrderDate(rawDate),
                            ),
                            _labelValueRow(
                              'Payment',
                              _paymentStatusLabel(order['payment_status']),
                            ),
                            _labelValueRow(
                              'Method',
                              _paymentMethod(order),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(
                            color: _invoiceAccentSoft,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: _invoiceBorder),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'BILL TO',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _invoiceAccent,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              pw.SizedBox(height: 7),
                              pw.Text(
                                customerName,
                                style: pw.TextStyle(
                                  fontSize: 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _invoiceAccent,
                                ),
                              ),
                              if (customerPhone.isNotEmpty) ...[
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Phone: $customerPhone',
                                  style: const pw.TextStyle(fontSize: 10.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Container(
                        width: 170,
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: _invoiceBorder),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _labelValueRow('Products', '$itemCount'),
                            _labelValueRow('Units', '$totalUnits'),
                            if (returnedTotal > 0)
                              _labelValueRow(
                                'Returns',
                                _formatCurrency(returnedTotal),
                                valueColor: PdfColors.red700,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: _invoiceAccent,
                    ),
                    border: pw.TableBorder.all(color: _invoiceBorder, width: 0.7),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    cellPadding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    cellAlignment: pw.Alignment.centerLeft,
                    cellAlignments: {
                      1: pw.Alignment.center,
                      2: pw.Alignment.centerRight,
                      3: pw.Alignment.centerRight,
                      4: pw.Alignment.centerRight,
                    },
                    headers: const [
                      'Product',
                      'Qty',
                      'M.R.P',
                      'Discount',
                      'Total',
                    ],
                    data: items.map((item) {
                      return [
                        item['product_name']?.toString() ??
                            item['name']?.toString() ??
                            'Product',
                        _asInt(item['units']).toString(),
                        _formatCurrency(item['selling_price']),
                        _formatCurrency(item['discount']),
                        _formatCurrency(item['gross_total'] ?? item['total']),
                      ];
                    }).toList(),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      width: 240,
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _invoiceBorder),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'SUMMARY',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: _invoiceAccent,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          _labelValueRow(
                            'Sub Total',
                            _formatCurrency(grossTotal),
                          ),
                          if (returnedTotal > 0)
                            _labelValueRow(
                              'Returned',
                              _formatCurrency(returnedTotal),
                              valueColor: PdfColors.red700,
                            ),
                          _labelValueRow(
                            'Amount Received',
                            _formatCurrency(amountPaid),
                          ),
                          _labelValueRow(
                            'Due Amount',
                            _formatCurrency(dueAmount),
                            valueColor: dueAmount > 0
                                ? PdfColors.red700
                                : PdfColors.green700,
                          ),
                          pw.SizedBox(height: 4),
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: pw.BoxDecoration(
                              color: _invoiceAccentSoft,
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'TOTAL',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: _invoiceAccent,
                                  ),
                                ),
                                pw.Text(
                                  _formatCurrency(netTotal),
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    color: _invoiceAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Divider(color: _invoiceBorder),
                  pw.SizedBox(height: 8),
                  if (storeDetails['invoice_note']?.trim().isNotEmpty == true)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        storeDetails['invoice_note']!.trim(),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  if (storeDetails['invoice_note']?.trim().isNotEmpty == true)
                    pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Thank you for shopping with us.',
                        style: pw.TextStyle(
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(
                            width: 110,
                            height: 1,
                            color: PdfColors.grey500,
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Authorized Signatory',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
