import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final costController = TextEditingController();
  final priceController = TextEditingController();
  final stockController = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _matchingProducts = [];
  Map<String, dynamic>? _selectedExistingProduct;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    nameController.dispose();
    costController.dispose();
    priceController.dispose();
    stockController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;

    setState(() {
      _products = data;
    });

    _updateMatchingProducts(nameController.text);
  }

  double? _parseAmount(String value) {
    return double.tryParse(value.trim());
  }

  int? _parseStock(String value) {
    return int.tryParse(value.trim());
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizedName() {
    return nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool get _isUpdatingExisting => _selectedExistingProduct != null;

  int get _existingStock => _selectedExistingProduct == null
      ? 0
      : _asInt(_selectedExistingProduct!['stock']);

  double get _costValue => _parseAmount(costController.text) ?? 0;

  double get _sellingValue => _parseAmount(priceController.text) ?? 0;

  int get _stockValue => _parseStock(stockController.text) ?? 0;

  int get _finalStockPreview =>
      _isUpdatingExisting ? _existingStock + _stockValue : _stockValue;

  double get _unitResult => _sellingValue - _costValue;

  double get _inventoryCost => _costValue * _finalStockPreview;

  double get _inventoryRevenue => _sellingValue * _finalStockPreview;

  double get _inventoryResult => _unitResult * _finalStockPreview;

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _formatCurrency(double value) {
    return "Rs ${_formatAmount(value)}";
  }

  Color _resultColor(ColorScheme colorScheme) {
    if (_unitResult < 0) {
      return colorScheme.error;
    }
    if (_unitResult > 0) {
      return colorScheme.secondary;
    }
    return colorScheme.onSurface.withAlpha(180);
  }

  String _resultLabel() {
    if (_unitResult < 0) {
      return "Loss per unit";
    }
    if (_unitResult > 0) {
      return "Profit per unit";
    }
    return "Break-even per unit";
  }

  void _refreshPreview([String _ = '']) {
    setState(() {});
  }

  void _handleNameChanged(String value) {
    final typedName = value.trim().toLowerCase();
    final selectedName =
        _selectedExistingProduct?['name']?.toString().trim().toLowerCase() ??
        '';

    if (_selectedExistingProduct != null && typedName != selectedName) {
      setState(() {
        _selectedExistingProduct = null;
        if (stockController.text == '0') {
          stockController.clear();
        }
      });
    }

    _updateMatchingProducts(value);
    _refreshPreview();
  }

  void _updateMatchingProducts(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _matchingProducts = [];
      });
      return;
    }

    final matches = _products
        .where((product) {
          final name = product['name']?.toString().toLowerCase() ?? '';
          return name.contains(query);
        })
        .take(6)
        .toList();

    setState(() {
      _matchingProducts = matches;
    });
  }

  void _selectExistingProduct(Map<String, dynamic> product) {
    nameController.text = product['name']?.toString() ?? '';
    costController.text = _formatAmount(
      _parseAmount(product['cost_price']?.toString() ?? '') ?? 0,
    );
    priceController.text = _formatAmount(
      _parseAmount(product['selling_price']?.toString() ?? '') ?? 0,
    );
    stockController.text = '0';

    setState(() {
      _selectedExistingProduct = product;
      _matchingProducts = [];
    });
  }

  void _clearSelectedExistingProduct() {
    setState(() {
      _selectedExistingProduct = null;
      _matchingProducts = [];
    });
    stockController.clear();
    _updateMatchingProducts(nameController.text);
  }

  void _resetForm() {
    nameController.clear();
    costController.clear();
    priceController.clear();
    stockController.clear();
    _formKey.currentState?.reset();
    setState(() {
      _selectedExistingProduct = null;
      _matchingProducts = [];
    });
    _refreshPreview();
  }

  Future<void> _saveProduct() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();

    final baseName = _normalizedName();
    final cost = _parseAmount(costController.text)!;
    final price = _parseAmount(priceController.text)!;
    final stock = _isUpdatingExisting && stockController.text.trim().isEmpty
        ? 0
        : _parseStock(stockController.text)!;

    setState(() {
      _isSaving = true;
    });

    try {
      late final String message;
      if (_selectedExistingProduct != null) {
        final existingProduct = _selectedExistingProduct!;
        final updatedStock = _existingStock + stock;

        await DatabaseHelper.instance.updateProduct(
          productId: existingProduct['id'] as int,
          name: baseName,
          costPrice: cost,
          sellingPrice: price,
          stock: updatedStock,
        );

        message = stock > 0
            ? "Product updated. Stock is now $updatedStock."
            : "Product details updated.";
      } else {
        final existingSamePrice = await DatabaseHelper.instance.findProduct(
          baseName,
          price,
        );

        if (existingSamePrice != null) {
          final currentStock = existingSamePrice['stock'];
          final newStock =
              (currentStock is num ? currentStock.toInt() : 0) + stock;

          await DatabaseHelper.instance.updateStock(
            existingSamePrice['id'] as int,
            newStock,
          );
          message = "Existing product found. Stock updated to $newStock.";
        } else {
          final sameNameList = await DatabaseHelper.instance.findByName(
            baseName,
          );
          final finalName = sameNameList.isNotEmpty
              ? "$baseName (${_formatAmount(price)})"
              : baseName;

          await DatabaseHelper.instance.insertProduct({
            'name': finalName,
            'cost_price': cost,
            'selling_price': price,
            'stock': stock,
          });

          message = sameNameList.isNotEmpty
              ? "New price variation added as $finalName."
              : "New product added successfully.";
        }
      }

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(message)));
      navigator.pop(true);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Could not save the product right now.")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildIntroCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create a Product",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Type a name to see existing matches. You can pick one to update its pricing and add more stock.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Product Details",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: _handleNameChanged,
                decoration: const InputDecoration(
                  labelText: "Product Name",
                  helperText: "Matching products appear below while you type.",
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return "Enter a product name";
                  }
                  return null;
                },
              ),
              if (_matchingProducts.isNotEmpty && !_isUpdatingExisting) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withAlpha(40),
                    ),
                  ),
                  child: Column(
                    children: _matchingProducts.map((product) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_toggle_off_rounded),
                        title: Text(product['name']?.toString() ?? ''),
                        subtitle: Text(
                          "Cost ${_formatCurrency(product['cost_price'])} • Selling ${_formatCurrency(product['selling_price'])} • Stock ${product['stock']}",
                        ),
                        onTap: () => _selectExistingProduct(product),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (_isUpdatingExisting) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withAlpha(12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Existing Product Selected",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Current stock: $_existingStock units. Update the price fields if needed, then enter how many more units to add.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _clearSelectedExistingProduct,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text("Use as New Product Instead"),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: _refreshPreview,
                      decoration: const InputDecoration(
                        labelText: "Cost Price",
                        prefixText: "Rs ",
                      ),
                      validator: (value) {
                        final amount = _parseAmount(value ?? '');
                        if (amount == null) {
                          return "Enter a valid amount";
                        }
                        if (amount < 0) {
                          return "Cost cannot be negative";
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: _refreshPreview,
                      decoration: const InputDecoration(
                        labelText: "Selling Price",
                        prefixText: "Rs ",
                      ),
                      validator: (value) {
                        final amount = _parseAmount(value ?? '');
                        if (amount == null) {
                          return "Enter a valid amount";
                        }
                        if (amount < 0) {
                          return "Selling price cannot be negative";
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: stockController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onChanged: _refreshPreview,
                decoration: InputDecoration(
                  labelText: _isUpdatingExisting
                      ? "Additional Stock"
                      : "Initial Stock",
                  helperText: _isUpdatingExisting
                      ? "Enter 0 if you only want to update the product details."
                      : "You can still change stock later from Stock Adjustment.",
                ),
                validator: (value) {
                  if (_isUpdatingExisting && (value?.trim().isEmpty ?? true)) {
                    return null;
                  }
                  final stock = _parseStock(value ?? '');
                  if (stock == null) {
                    return "Enter a whole number";
                  }
                  if (stock < 0) {
                    return "Stock cannot be negative";
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = _normalizedName();
    final resultColor = _resultColor(colorScheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? "Product Preview" : name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Review the pricing and stock impact before saving.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: resultColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _resultLabel(),
                    style: TextStyle(
                      color: resultColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPreviewRow("Cost Price", _formatCurrency(_costValue)),
            _buildPreviewRow("Selling Price", _formatCurrency(_sellingValue)),
            _buildPreviewRow(
              _resultLabel(),
              _formatCurrency(_unitResult),
              valueColor: resultColor,
            ),
            if (_isUpdatingExisting) ...[
              _buildPreviewRow("Current Stock", "$_existingStock units"),
              _buildPreviewRow("Additional Stock", "$_stockValue units"),
              _buildPreviewRow("Updated Stock", "$_finalStockPreview units"),
            ] else
              _buildPreviewRow("Opening Stock", "$_stockValue units"),
            const Divider(height: 22),
            _buildPreviewRow("Inventory Cost", _formatCurrency(_inventoryCost)),
            _buildPreviewRow(
              "Potential Revenue",
              _formatCurrency(_inventoryRevenue),
            ),
            _buildPreviewRow(
              "Potential Result",
              _formatCurrency(_inventoryResult),
              valueColor: resultColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveProduct,
            icon: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? "Saving..." : "Save Product"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _resetForm,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Clear Form"),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Product")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildIntroCard(context),
          const SizedBox(height: 16),
          _buildDetailsForm(context),
          const SizedBox(height: 16),
          _buildPreviewCard(context),
          const SizedBox(height: 16),
          _buildActionButtons(context),
        ],
      ),
    );
  }
}
