import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'package:intl/intl.dart';

enum DiscountMode { manual, soldPrice, percentage }

class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key, this.existingSale});

  final Map<String, dynamic>? existingSale;

  @override
  State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  List<Map<String, dynamic>> products = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;
  DiscountMode discountMode = DiscountMode.manual;
  bool _didLoadExistingSale = false;

  final unitsController = TextEditingController();
  final discountController = TextEditingController();
  final soldPriceController = TextEditingController();
  final discountPercentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    setState(() {
      products = data;
    });
    _populateExistingSale();
  }

  @override
  void dispose() {
    unitsController.dispose();
    discountController.dispose();
    soldPriceController.dispose();
    discountPercentController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double? _selectedSellingPrice() {
    final price = selectedProduct?['selling_price'];
    if (price is num) {
      return price.toDouble();
    }
    return null;
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  bool get _isEditing => widget.existingSale != null;

  void _populateExistingSale() {
    final sale = widget.existingSale;
    if (sale == null || _didLoadExistingSale) return;

    final existingProductId = sale['product_id'] as int?;
    Map<String, dynamic>? matchedProduct;
    for (final product in products) {
      if (product['id'] == existingProductId) {
        matchedProduct = product;
        break;
      }
    }

    final sellingPrice = _asDouble(sale['selling_price']);
    final discount = _asDouble(sale['discount']);
    final soldPrice = sellingPrice - discount;
    final discountPercent =
        sellingPrice > 0 ? (discount / sellingPrice) * 100 : 0.0;

    setState(() {
      _didLoadExistingSale = true;
      selectedProductId = matchedProduct?['id'] as int?;
      selectedProduct = matchedProduct;
      unitsController.text = sale['units']?.toString() ?? '';
      discountMode = DiscountMode.manual;
      discountController.text = _formatAmount(discount);
      soldPriceController.text =
          _formatAmount(soldPrice < 0 ? 0.0 : soldPrice);
      discountPercentController.text = _formatAmount(discountPercent);
    });
  }

  void _syncCalculatedDiscount() {
    if (discountMode == DiscountMode.manual) return;

    final sellingPrice = _selectedSellingPrice();
    if (sellingPrice == null) {
      setState(() {
        discountController.clear();
      });
      return;
    }

    double? discount;
    if (discountMode == DiscountMode.soldPrice) {
      final soldPrice = double.tryParse(soldPriceController.text);
      if (soldPrice != null) {
        discount = sellingPrice - soldPrice;
      }
    } else {
      final percentage = double.tryParse(discountPercentController.text);
      if (percentage != null) {
        discount = sellingPrice * (percentage / 100);
      }
    }

    setState(() {
      if (discount == null) {
        discountController.clear();
        return;
      }
      discountController.text = _formatAmount(discount);
    });
  }

  void _changeDiscountMode(DiscountMode? value) {
    if (value == null) return;

    setState(() {
      discountMode = value;
      if (value != DiscountMode.soldPrice) {
        soldPriceController.clear();
      }
      if (value != DiscountMode.percentage) {
        discountPercentController.clear();
      }
      if (value != DiscountMode.manual) {
        discountController.clear();
      }
    });

    _syncCalculatedDiscount();
  }

  double? _resolveDiscount() {
    final sellingPrice = _selectedSellingPrice();
    if (sellingPrice == null) return null;

    switch (discountMode) {
      case DiscountMode.manual:
        final manualDiscount = double.tryParse(discountController.text);
        if (manualDiscount == null) {
          _showMessage("Enter a valid discount amount");
          return null;
        }
        if (manualDiscount < 0 || manualDiscount > sellingPrice) {
          _showMessage("Discount must be between 0 and selling price");
          return null;
        }
        return manualDiscount;
      case DiscountMode.soldPrice:
        final soldPrice = double.tryParse(soldPriceController.text);
        if (soldPrice == null) {
          _showMessage("Enter a valid sold price");
          return null;
        }
        if (soldPrice < 0 || soldPrice > sellingPrice) {
          _showMessage("Sold price must be between 0 and selling price");
          return null;
        }
        return sellingPrice - soldPrice;
      case DiscountMode.percentage:
        final percentage = double.tryParse(discountPercentController.text);
        if (percentage == null) {
          _showMessage("Enter a valid discount percentage");
          return null;
        }
        if (percentage < 0 || percentage > 100) {
          _showMessage("Discount percentage must be between 0 and 100");
          return null;
        }
        return sellingPrice * (percentage / 100);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "Edit Sale" : "Record Sale"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: selectedProductId,
              items: products.map((product) {
                return DropdownMenuItem<int>(
                  value: product['id'],
                  child: Text(product['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedProductId = value;
                  selectedProduct =
                      products.firstWhere((p) => p['id'] == value);
                });
                _syncCalculatedDiscount();
              },
              decoration:
                  const InputDecoration(labelText: "Select Product"),
            ),
            if (selectedProduct != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Selling Price: Rs ${_formatAmount(_selectedSellingPrice() ?? 0)}",
                  ),
                ),
              ),
            TextField(
              controller: unitsController,
              decoration:
                  const InputDecoration(labelText: "Units Sold"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DiscountMode>(
              initialValue: discountMode,
              onChanged: _changeDiscountMode,
              items: const [
                DropdownMenuItem(
                  value: DiscountMode.manual,
                  child: Text("Manual Discount"),
                ),
                DropdownMenuItem(
                  value: DiscountMode.soldPrice,
                  child: Text("Sold Price"),
                ),
                DropdownMenuItem(
                  value: DiscountMode.percentage,
                  child: Text("Discount Percentage"),
                ),
              ],
              decoration: const InputDecoration(
                labelText: "Discount Entry Method",
              ),
            ),
            if (discountMode == DiscountMode.soldPrice)
              TextField(
                controller: soldPriceController,
                decoration: const InputDecoration(
                  labelText: "Sold Price per unit",
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _syncCalculatedDiscount(),
              ),
            if (discountMode == DiscountMode.percentage)
              TextField(
                controller: discountPercentController,
                decoration: const InputDecoration(
                  labelText: "Discount Percentage",
                  helperText: "Enter 10 for a 10% discount",
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _syncCalculatedDiscount(),
              ),
            TextField(
              controller: discountController,
              readOnly: discountMode != DiscountMode.manual,
              decoration: InputDecoration(
                labelText: discountMode == DiscountMode.manual
                    ? "Discount per unit"
                    : "Calculated discount per unit",
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (selectedProduct == null ||
                    unitsController.text.isEmpty ||
                    (discountMode == DiscountMode.manual &&
                        discountController.text.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Fill all fields")),
                  );
                  return;
                }

                final units = int.tryParse(unitsController.text);
                if (units == null || units <= 0) {
                  _showMessage("Enter a valid number of units");
                  return;
                }

                final discount = _resolveDiscount();
                if (discount == null) return;

                double sellingPrice =
                    (selectedProduct!['selling_price'] as num).toDouble();
                double costPrice =
                    (selectedProduct!['cost_price'] as num).toDouble();
                int currentStock =
                    selectedProduct!['stock'];
                int availableStock = currentStock;

                if (_isEditing &&
                    widget.existingSale?['product_id'] == selectedProduct!['id']) {
                  availableStock +=
                      (widget.existingSale!['units'] as num).toInt();
                }

                if (units > availableStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Not enough stock")),
                  );
                  return;
                }

                double finalPrice =
                    sellingPrice - discount;
                if (finalPrice < 0) {
                  _showMessage("Final price cannot be negative");
                  return;
                }
                double total = finalPrice * units;
                double profit =
                    (finalPrice - costPrice) * units;

                if (_isEditing) {
                  try {
                    await DatabaseHelper.instance.updateSale(
                      saleId: widget.existingSale!['id'] as int,
                      productId: selectedProduct!['id'] as int,
                      units: units,
                      discount: discount,
                      total: total,
                      profit: profit,
                      costPrice: costPrice,
                      sellingPrice: sellingPrice,
                    );
                  } on Exception catch (error) {
                    _showMessage(
                      error.toString().replaceFirst('Exception: ', ''),
                    );
                    return;
                  }
                } else {
                  int newStock = currentStock - units;

                  await DatabaseHelper.instance.updateStock(
                    selectedProduct!['id'],
                    newStock,
                  );

                  await DatabaseHelper.instance.insertSale({
                    'product_id': selectedProduct!['id'],
                    'units': units,
                    'discount': discount,
                    'total': total,
                    'profit': profit,
                    'cost_price': costPrice,
                    'selling_price': sellingPrice,
                    'date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                  });
                }

                if (!context.mounted) return;
                Navigator.of(context).pop(true);
              },
              child: Text(_isEditing ? "Update Sale" : "Save Sale"),
            )
          ],
        ),
      ),
    );
  }
}
