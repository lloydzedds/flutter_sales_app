import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';

enum ProductLabelCodeType { barcode, qr }

enum ProductLabelPaperSize {
  mm58x40,
  mm50x30,
  mm70x50;

  String get label {
    switch (this) {
      case ProductLabelPaperSize.mm50x30:
        return '50 x 30 mm';
      case ProductLabelPaperSize.mm70x50:
        return '70 x 50 mm';
      case ProductLabelPaperSize.mm58x40:
        return '58 x 40 mm';
    }
  }

  PdfPageFormat get pageFormat {
    switch (this) {
      case ProductLabelPaperSize.mm50x30:
        return PdfPageFormat(
          50 * PdfPageFormat.mm,
          30 * PdfPageFormat.mm,
          marginAll: 3 * PdfPageFormat.mm,
        );
      case ProductLabelPaperSize.mm70x50:
        return PdfPageFormat(
          70 * PdfPageFormat.mm,
          50 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        );
      case ProductLabelPaperSize.mm58x40:
        return PdfPageFormat(
          58 * PdfPageFormat.mm,
          40 * PdfPageFormat.mm,
          marginAll: 3 * PdfPageFormat.mm,
        );
    }
  }
}

class ProductLabelService {
  static String barcodeFromProduct(Map<String, dynamic> product) {
    return product['barcode']?.toString().trim() ?? '';
  }

  static Future<String> ensureProductBarcode(
    Map<String, dynamic> product,
  ) async {
    final existing = barcodeFromProduct(product);
    if (existing.isNotEmpty) return existing;

    final productId = _asInt(product['id']);
    if (productId <= 0) {
      throw Exception('This product cannot receive an internal barcode yet.');
    }

    final generated = generatedInternalBarcode(productId);
    await DatabaseHelper.instance.updateProductBarcode(productId, generated);
    product['barcode'] = generated;
    return generated;
  }

  static String generatedInternalBarcode(int productId) {
    return 'SB-${productId.toString().padLeft(6, '0')}';
  }

  static Future<File> saveProductLabels({
    required Map<String, dynamic> product,
    required String barcodeValue,
    required ProductLabelCodeType codeType,
    required ProductLabelPaperSize paperSize,
    required int copies,
    required bool includePrice,
    required Directory targetDirectory,
  }) async {
    final storeDetails = await DatabaseHelper.instance.getStoreDetails();
    final document = pw.Document();
    final name = product['name']?.toString().trim().isNotEmpty == true
        ? product['name'].toString().trim()
        : 'Product';
    final price = _formatCurrency(product['selling_price']);
    final storeName = storeDetails['store_name']?.trim().isNotEmpty == true
        ? storeDetails['store_name']!.trim()
        : 'Sale Buddy';

    for (var index = 0; index < copies; index++) {
      document.addPage(
        pw.Page(
          pageFormat: paperSize.pageFormat,
          build: (context) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    storeName,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    name,
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.BarcodeWidget(
                        barcode: codeType == ProductLabelCodeType.barcode
                            ? pw.Barcode.code128()
                            : pw.Barcode.qrCode(),
                        data: barcodeValue,
                        drawText: codeType == ProductLabelCodeType.barcode,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  if (includePrice) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      price,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                  if (codeType == ProductLabelCodeType.qr) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      barcodeValue,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    final fileName =
        'label_${_safeFilePart(name)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File(path.join(targetDirectory.path, fileName));
    await file.writeAsBytes(await document.save());
    return file;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _safeFilePart(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  static String _formatCurrency(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    if (amount == amount.roundToDouble()) {
      return 'Rs ${amount.toStringAsFixed(0)}';
    }
    return 'Rs ${amount.toStringAsFixed(2)}';
  }
}
