import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/product_label_service.dart';
import '../services/sales_export_service.dart';

class ProductLabelScreen extends StatefulWidget {
  const ProductLabelScreen({super.key, required this.product});

  final Map<String, dynamic> product;

  @override
  State<ProductLabelScreen> createState() => _ProductLabelScreenState();
}

class _ProductLabelScreenState extends State<ProductLabelScreen> {
  ProductLabelCodeType _codeType = ProductLabelCodeType.barcode;
  ProductLabelPaperSize _paperSize = ProductLabelPaperSize.mm58x40;
  bool _includePrice = true;
  bool _isBusy = false;
  int _copies = 1;
  late final Map<String, dynamic> _product;
  late String _barcodeValue;

  @override
  void initState() {
    super.initState();
    _product = Map<String, dynamic>.from(widget.product);
    _barcodeValue = ProductLabelService.barcodeFromProduct(_product);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _productName {
    final name = _product['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Product' : name;
  }

  Future<void> _ensureInternalBarcode() async {
    setState(() {
      _isBusy = true;
    });

    try {
      final value = await ProductLabelService.ensureProductBarcode(_product);
      if (!mounted) return;
      setState(() {
        _barcodeValue = value;
      });
      _showMessage("Internal barcode ready: $value");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _exportLabels({required bool saveLocally}) async {
    setState(() {
      _isBusy = true;
    });

    try {
      final value = _barcodeValue.isNotEmpty
          ? _barcodeValue
          : await ProductLabelService.ensureProductBarcode(_product);
      final directory = saveLocally
          ? await SalesExportService.ensureLocalSaleDirectory()
          : await SalesExportService.ensureShareDirectory();
      final file = await ProductLabelService.saveProductLabels(
        product: _product,
        barcodeValue: value,
        codeType: _codeType,
        paperSize: _paperSize,
        copies: _copies,
        includePrice: _includePrice,
        targetDirectory: directory,
      );

      if (!mounted) return;
      setState(() {
        _barcodeValue = value;
      });

      if (saveLocally) {
        _showMessage("Label PDF saved to ${file.parent.path}");
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: "Product label for $_productName",
          ),
        );
        if (!mounted) return;
        _showMessage("Share sheet opened for label PDF");
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _buildCountPicker() {
    return Row(
      children: [
        IconButton(
          onPressed: _isBusy || _copies <= 1
              ? null
              : () => setState(() {
                  _copies -= 1;
                }),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              "$_copies label${_copies == 1 ? '' : 's'}",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          onPressed: _isBusy || _copies >= 50
              ? null
              : () => setState(() {
                  _copies += 1;
                }),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Print Product Label")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _productName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _barcodeValue.isEmpty
                        ? "This product does not have a barcode yet. You can assign an internal one and print it."
                        : "Barcode value: $_barcodeValue",
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _ensureInternalBarcode,
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: Text(
                        _barcodeValue.isEmpty
                            ? "Generate Internal Barcode"
                            : "Refresh Internal Barcode",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Label Setup",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<ProductLabelCodeType>(
                    segments: const [
                      ButtonSegment<ProductLabelCodeType>(
                        value: ProductLabelCodeType.barcode,
                        icon: Icon(Icons.view_week_outlined),
                        label: Text("Barcode"),
                      ),
                      ButtonSegment<ProductLabelCodeType>(
                        value: ProductLabelCodeType.qr,
                        icon: Icon(Icons.qr_code_2_rounded),
                        label: Text("QR"),
                      ),
                    ],
                    selected: {_codeType},
                    showSelectedIcon: false,
                    onSelectionChanged: _isBusy
                        ? null
                        : (selection) {
                            if (selection.isEmpty) return;
                            setState(() {
                              _codeType = selection.first;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProductLabelPaperSize>(
                    initialValue: _paperSize,
                    decoration: const InputDecoration(labelText: "Label size"),
                    items: ProductLabelPaperSize.values.map((size) {
                      return DropdownMenuItem(
                        value: size,
                        child: Text(size.label),
                      );
                    }).toList(),
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _paperSize = value;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Quantity",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _buildCountPicker(),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _includePrice,
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            setState(() {
                              _includePrice = value;
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Show selling price"),
                    subtitle: const Text(
                      "Useful for shelf labels and hanging tags.",
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Print Method",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "This first version creates a label PDF that you can save, share, or open with your printer app. That works well with most tag printers and Bluetooth print apps.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _exportLabels(saveLocally: false),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(_isBusy ? "Preparing..." : "Share Label PDF"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _exportLabels(saveLocally: true),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text("Save Label PDF"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
