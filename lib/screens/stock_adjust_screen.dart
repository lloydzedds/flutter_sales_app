import 'package:flutter/material.dart';

import '../database/database_helper.dart';

enum StockAdjustMode { add, remove, set }

class StockAdjustScreen extends StatefulWidget {
  const StockAdjustScreen({
    super.key,
    this.initialProductId,
    this.initialMode = StockAdjustMode.add,
  });

  final int? initialProductId;
  final StockAdjustMode initialMode;

  @override
  State<StockAdjustScreen> createState() => _StockAdjustScreenState();
}

class _StockAdjustScreenState extends State<StockAdjustScreen> {
  List<Map<String, dynamic>> products = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;
  late StockAdjustMode adjustmentMode;

  final qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    adjustmentMode = widget.initialMode;
    loadProducts();
  }

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  Future<void> loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;

    setState(() {
      products = data;
      if (widget.initialProductId != null) {
        for (final product in data) {
          if (product['id'] == widget.initialProductId) {
            selectedProductId = product['id'] as int;
            selectedProduct = product;
            break;
          }
        }
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int _currentStock() {
    final stock = selectedProduct?['stock'];
    if (stock is int) {
      return stock;
    }
    if (stock is num) {
      return stock.toInt();
    }
    return 0;
  }

  int? _parsedQuantity() {
    return int.tryParse(qtyController.text.trim());
  }

  int? _updatedStockPreview() {
    final product = selectedProduct;
    if (product == null) return null;

    final currentStock = _currentStock();
    final quantity = _parsedQuantity();
    if (quantity == null) return currentStock;

    switch (adjustmentMode) {
      case StockAdjustMode.add:
        return currentStock + quantity;
      case StockAdjustMode.remove:
        return currentStock - quantity;
      case StockAdjustMode.set:
        return quantity;
    }
  }

  String _modeLabel(StockAdjustMode mode) {
    switch (mode) {
      case StockAdjustMode.add:
        return "Add Stock";
      case StockAdjustMode.remove:
        return "Remove Stock";
      case StockAdjustMode.set:
        return "Set Exact Stock";
    }
  }

  String _quantityLabel() {
    switch (adjustmentMode) {
      case StockAdjustMode.add:
        return "Quantity to Add";
      case StockAdjustMode.remove:
        return "Quantity to Remove";
      case StockAdjustMode.set:
        return "New Stock Value";
    }
  }

  Future<void> adjustStock() async {
    if (selectedProduct == null || qtyController.text.trim().isEmpty) {
      _showMessage("Fill all fields");
      return;
    }

    final navigator = Navigator.of(context);

    final quantity = _parsedQuantity();
    if (quantity == null || quantity < 0) {
      _showMessage("Enter a valid stock value");
      return;
    }

    final currentStock = _currentStock();
    int newStock;

    switch (adjustmentMode) {
      case StockAdjustMode.add:
        if (quantity == 0) {
          _showMessage("Quantity must be greater than 0");
          return;
        }
        newStock = currentStock + quantity;
        break;
      case StockAdjustMode.remove:
        if (quantity == 0) {
          _showMessage("Quantity must be greater than 0");
          return;
        }
        newStock = currentStock - quantity;
        break;
      case StockAdjustMode.set:
        newStock = quantity;
        break;
    }

    if (newStock < 0) {
      _showMessage("Stock cannot be negative");
      return;
    }

    await DatabaseHelper.instance.updateStock(
      selectedProduct!['id'] as int,
      newStock,
    );

    if (!mounted) return;
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final previewStock = _updatedStockPreview();
    final colorScheme = Theme.of(context).colorScheme;
    final mutedTextColor = colorScheme.onSurface.withAlpha(180);
    final previewColor = previewStock == null
        ? colorScheme.onSurface
        : previewStock < 0
        ? colorScheme.error
        : colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(title: const Text("Stock Adjustment")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: selectedProductId,
              items: products.map((product) {
                return DropdownMenuItem<int>(
                  value: product['id'] as int,
                  child: Text(product['name'].toString()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedProductId = value;
                  selectedProduct = value == null
                      ? null
                      : products.firstWhere((p) => p['id'] == value);
                });
              },
              decoration: const InputDecoration(labelText: "Select Product"),
            ),
            if (selectedProduct != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withAlpha(180),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedProduct!['name'].toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Current Stock",
                      style: TextStyle(
                        color: mutedTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${_currentStock()} units",
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Selling Price",
                      style: TextStyle(
                        color: mutedTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Rs ${selectedProduct!['selling_price']}",
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (previewStock != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        "Updated Stock",
                        style: TextStyle(
                          color: mutedTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$previewStock units",
                        style: TextStyle(
                          color: previewColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              "Adjustment Type",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StockAdjustMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(_modeLabel(mode)),
                  selected: adjustmentMode == mode,
                  onSelected: (_) {
                    setState(() {
                      adjustmentMode = mode;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              decoration: InputDecoration(
                labelText: _quantityLabel(),
                helperText: adjustmentMode == StockAdjustMode.set
                    ? "Enter the final stock you want to keep"
                    : "Enter the quantity to change",
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: adjustStock,
                child: Text(_modeLabel(adjustmentMode)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
