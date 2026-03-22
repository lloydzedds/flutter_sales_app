import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_settings_controller.dart';
import '../database/database_helper.dart';
import 'add_product_screen.dart';

enum DiscountMode { manual, soldPrice, percentage }

class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key, this.existingSale});

  final Map<String, dynamic>? existingSale;

  @override
  State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> products = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;
  DiscountMode discountMode = DiscountMode.manual;
  bool _didLoadExistingSale = false;
  bool _missingExistingProduct = false;
  bool _isSaving = false;
  bool _showCostPrice = false;
  bool _showProfitLoss = false;

  final unitsController = TextEditingController();
  final discountController = TextEditingController();
  final soldPriceController = TextEditingController();
  final discountPercentController = TextEditingController();
  final productSearchController = TextEditingController();
  final productSearchFocusNode = FocusNode();

  bool get _isEditing => widget.existingSale != null;

  DiscountMode get _defaultDiscountMode {
    switch (AppSettingsController.instance.defaultDiscountMode) {
      case 'sold_price':
        return DiscountMode.soldPrice;
      case 'percentage':
        return DiscountMode.percentage;
      default:
        return DiscountMode.manual;
    }
  }

  @override
  void initState() {
    super.initState();
    productSearchController.addListener(_handleProductSearchChanged);
    discountMode = _defaultDiscountMode;
    loadProducts();
  }

  @override
  void dispose() {
    productSearchController.removeListener(_handleProductSearchChanged);
    unitsController.dispose();
    discountController.dispose();
    soldPriceController.dispose();
    discountPercentController.dispose();
    productSearchController.dispose();
    productSearchFocusNode.dispose();
    super.dispose();
  }

  Future<void> loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;

    setState(() {
      products = data;
    });

    _populateExistingSale();
  }

  Future<void> _openAddProduct() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );

    if (!mounted) return;
    await loadProducts();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
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

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _formatCurrency(double value) {
    return "Rs ${_formatAmount(value)}";
  }

  double? _selectedSellingPrice() {
    final price = selectedProduct?['selling_price'];
    if (price is num) {
      return price.toDouble();
    }
    return null;
  }

  double? _selectedCostPrice() {
    final price = selectedProduct?['cost_price'];
    if (price is num) {
      return price.toDouble();
    }
    return null;
  }

  int _availableStock() {
    final product = selectedProduct;
    if (product == null) return 0;

    var stock = _asInt(product['stock']);
    if (_isEditing && widget.existingSale?['product_id'] == product['id']) {
      stock += _asInt(widget.existingSale?['units']);
    }
    return stock;
  }

  List<DropdownMenuEntry<int>> get _productMenuEntries {
    return products.map((product) {
      return DropdownMenuEntry<int>(
        value: product['id'] as int,
        label: product['name'].toString(),
      );
    }).toList();
  }

  List<DropdownMenuEntry<int>> _filterProductEntries(
    List<DropdownMenuEntry<int>> entries,
    String filter,
  ) {
    final query = filter.trim().toLowerCase();
    if (query.isEmpty) {
      return entries;
    }

    return entries.where((entry) {
      return entry.label.toLowerCase().contains(query);
    }).toList();
  }

  int? _parsedUnits() {
    return int.tryParse(unitsController.text.trim());
  }

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
    final discountPercent = sellingPrice > 0
        ? (discount / sellingPrice) * 100
        : 0.0;

    setState(() {
      _didLoadExistingSale = true;
      _missingExistingProduct =
          existingProductId != null && matchedProduct == null;
      _showCostPrice = false;
      _showProfitLoss = false;
      selectedProductId = matchedProduct == null
          ? null
          : matchedProduct['id'] as int;
      selectedProduct = matchedProduct;
      unitsController.text = sale['units']?.toString() ?? '';
      discountMode = _defaultDiscountMode;
      discountController.text = _formatAmount(discount);
      soldPriceController.text = _formatAmount(soldPrice < 0 ? 0.0 : soldPrice);
      discountPercentController.text = _formatAmount(discountPercent);
      productSearchController.text = matchedProduct?['name']?.toString() ?? '';
    });
  }

  void _selectProduct(int? value) {
    final nextProduct = value == null
        ? null
        : products.firstWhere((product) => product['id'] == value);

    setState(() {
      _showCostPrice = false;
      _showProfitLoss = false;
      selectedProductId = value;
      selectedProduct = nextProduct;
      if (value != null) {
        _missingExistingProduct = false;
      }
    });

    if (nextProduct == null) {
      productSearchController.clear();
    } else {
      productSearchController.text = nextProduct['name'].toString();
    }
    productSearchFocusNode.unfocus();
    _syncCalculatedDiscount();
  }

  void _handleProductSearchChanged() {
    if (!mounted) return;

    final typedName = productSearchController.text.trim().toLowerCase();
    final selectedName =
        selectedProduct?['name']?.toString().trim().toLowerCase() ?? '';
    final shouldClearSelection =
        selectedProduct != null && typedName != selectedName;

    if (shouldClearSelection) {
      setState(() {
        _showCostPrice = false;
        _showProfitLoss = false;
        selectedProductId = null;
        selectedProduct = null;
      });
      _syncCalculatedDiscount();
      return;
    }

    setState(() {});
  }

  void _syncCalculatedDiscount() {
    if (discountMode == DiscountMode.manual) {
      setState(() {});
      return;
    }

    final discount = _resolveDiscount(showErrors: false);
    setState(() {
      if (discount == null) {
        discountController.clear();
      } else {
        discountController.text = _formatAmount(discount);
      }
    });
  }

  void _changeDiscountMode(DiscountMode mode) {
    final currentDiscount = _resolveDiscount(showErrors: false);

    setState(() {
      discountMode = mode;
      if (mode == DiscountMode.manual) {
        if (currentDiscount != null) {
          discountController.text = _formatAmount(currentDiscount);
        }
      } else {
        if (mode != DiscountMode.soldPrice) {
          soldPriceController.clear();
        }
        if (mode != DiscountMode.percentage) {
          discountPercentController.clear();
        }
      }
    });

    _syncCalculatedDiscount();
  }

  double? _resolveDiscount({required bool showErrors}) {
    final sellingPrice = _selectedSellingPrice();
    if (sellingPrice == null) return null;

    String? message;
    double? discount;

    switch (discountMode) {
      case DiscountMode.manual:
        final manualDiscount = double.tryParse(discountController.text.trim());
        if (manualDiscount == null) {
          message = "Enter a valid discount amount";
        } else if (manualDiscount < 0 || manualDiscount > sellingPrice) {
          message = "Discount must be between 0 and the selling price";
        } else {
          discount = manualDiscount;
        }
        break;
      case DiscountMode.soldPrice:
        final soldPrice = double.tryParse(soldPriceController.text.trim());
        if (soldPrice == null) {
          message = "Enter a valid sold price";
        } else if (soldPrice < 0 || soldPrice > sellingPrice) {
          message = "Sold price must be between 0 and the selling price";
        } else {
          discount = sellingPrice - soldPrice;
        }
        break;
      case DiscountMode.percentage:
        final percentage = double.tryParse(
          discountPercentController.text.trim(),
        );
        if (percentage == null) {
          message = "Enter a valid discount percentage";
        } else if (percentage < 0 || percentage > 100) {
          message = "Discount percentage must be between 0 and 100";
        } else {
          discount = sellingPrice * (percentage / 100);
        }
        break;
    }

    if (message != null) {
      if (showErrors) {
        _showMessage(message);
      }
      return null;
    }

    return discount;
  }

  double? _soldPricePreview() {
    final sellingPrice = _selectedSellingPrice();
    final discount = _resolveDiscount(showErrors: false);
    if (sellingPrice == null || discount == null) return null;

    final soldPrice = sellingPrice - discount;
    if (soldPrice < 0) return null;
    return soldPrice;
  }

  double? _grossTotalPreview() {
    final sellingPrice = _selectedSellingPrice();
    final units = _parsedUnits();
    if (sellingPrice == null || units == null || units <= 0) return null;
    return sellingPrice * units;
  }

  double? _totalDiscountPreview() {
    final discount = _resolveDiscount(showErrors: false);
    final units = _parsedUnits();
    if (discount == null || units == null || units <= 0) return null;
    return discount * units;
  }

  double? _netTotalPreview() {
    final soldPrice = _soldPricePreview();
    final units = _parsedUnits();
    if (soldPrice == null || units == null || units <= 0) return null;
    return soldPrice * units;
  }

  double? _profitPreview() {
    final soldPrice = _soldPricePreview();
    final costPrice = _selectedCostPrice();
    final units = _parsedUnits();
    if (soldPrice == null || costPrice == null || units == null || units <= 0) {
      return null;
    }
    return (soldPrice - costPrice) * units;
  }

  int? _remainingStockPreview() {
    final units = _parsedUnits();
    if (selectedProduct == null || units == null || units <= 0) return null;
    return _availableStock() - units;
  }

  String _discountModeLabel(DiscountMode mode) {
    switch (mode) {
      case DiscountMode.manual:
        return "Manual";
      case DiscountMode.soldPrice:
        return "Sold Price";
      case DiscountMode.percentage:
        return "Percentage";
    }
  }

  String _discountModeHint() {
    switch (discountMode) {
      case DiscountMode.manual:
        return "Type the discount amount for each unit.";
      case DiscountMode.soldPrice:
        return "Enter the final amount the product was sold for per unit.";
      case DiscountMode.percentage:
        return "Enter 10 for a 10% discount on each unit.";
    }
  }

  void _refreshPreview([String _ = '']) {
    if (discountMode == DiscountMode.manual) {
      setState(() {});
    } else {
      _syncCalculatedDiscount();
    }
  }

  void _restoreForm() {
    FocusScope.of(context).unfocus();

    if (_isEditing) {
      setState(() {
        _didLoadExistingSale = false;
        _missingExistingProduct = false;
        _showCostPrice = false;
        _showProfitLoss = false;
        selectedProductId = null;
        selectedProduct = null;
        discountMode = _defaultDiscountMode;
        unitsController.clear();
        discountController.clear();
        soldPriceController.clear();
        discountPercentController.clear();
      });
      _populateExistingSale();
      return;
    }

    setState(() {
      _showCostPrice = false;
      _showProfitLoss = false;
      selectedProductId = null;
      selectedProduct = null;
      discountMode = _defaultDiscountMode;
      unitsController.clear();
      discountController.clear();
      soldPriceController.clear();
      discountPercentController.clear();
      productSearchController.clear();
    });
  }

  Future<void> _toggleCostPriceVisibility() async {
    if (_showCostPrice) {
      setState(() {
        _showCostPrice = false;
      });
      return;
    }

    final shouldShow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Display Cost Price"),
          content: const Text(
            "Are you sure you want to display the cost price?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("No"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldShow != true) return;

    setState(() {
      _showCostPrice = true;
    });
  }

  Future<void> _toggleProfitLossVisibility() async {
    if (_showProfitLoss) {
      setState(() {
        _showProfitLoss = false;
      });
      return;
    }

    final shouldShow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Display Profit / Loss"),
          content: const Text(
            "Are you sure you want to display the profit / loss?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("No"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldShow != true) return;

    setState(() {
      _showProfitLoss = true;
    });
  }

  Future<void> _saveSale() async {
    if (selectedProduct == null) {
      _showMessage("Select a product first");
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final discount = _resolveDiscount(showErrors: true);
    if (discount == null) return;

    final units = _parsedUnits();
    if (units == null || units <= 0) {
      _showMessage("Enter a valid number of units");
      return;
    }

    final sellingPrice = _selectedSellingPrice();
    final costPrice = _selectedCostPrice();
    if (sellingPrice == null || costPrice == null) {
      _showMessage("Selected product pricing is incomplete");
      return;
    }

    final availableStock = _availableStock();
    if (units > availableStock) {
      _showMessage("Not enough stock for this sale");
      return;
    }

    final soldPrice = sellingPrice - discount;
    if (soldPrice < 0) {
      _showMessage("Final price cannot be negative");
      return;
    }

    final total = soldPrice * units;
    final profit = (soldPrice - costPrice) * units;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      if (_isEditing) {
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
      } else {
        final newStock = _asInt(selectedProduct!['stock']) - units;

        await DatabaseHelper.instance.updateStock(
          selectedProduct!['id'] as int,
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

      if (!mounted) return;
      navigator.pop(true);
    } on Exception catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
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
                _isEditing
                    ? Icons.edit_calendar_outlined
                    : Icons.shopping_cart_checkout_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEditing ? "Update Sale" : "Record a Sale",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isEditing
                        ? "Edit the selected sale and keep the stock movement accurate."
                        : "Choose a product, apply discount your way, and review the final numbers before saving.",
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

  Widget _buildEmptyStateCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "No products available",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              "Add at least one product before recording a sale.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text("Add Product First"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingProductCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "The original product for this sale no longer exists. Choose another product to continue editing.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    Color? accentColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayColor = accentColor ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: displayColor.withAlpha(18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: displayColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostPriceTile(BuildContext context, double? costPrice) {
    return InkWell(
      onTap: _toggleCostPriceVisibility,
      borderRadius: BorderRadius.circular(18),
      child: _buildMetricTile(
        context: context,
        label: _showCostPrice ? "Cost Price" : "Cost Price Hidden",
        value: _showCostPrice ? _formatCurrency(costPrice ?? 0) : "Tap to show",
        icon: _showCostPrice
            ? Icons.visibility_rounded
            : Icons.visibility_off_rounded,
        accentColor: const Color(0xFF57D77F),
      ),
    );
  }

  Widget _buildSaleDetailsCard(BuildContext context) {
    final sellingPrice = _selectedSellingPrice();
    final costPrice = _selectedCostPrice();
    final remainingStock = _remainingStockPreview();
    final remainingColor = remainingStock == null
        ? null
        : remainingStock < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.secondary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Sale Details",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            DropdownMenu<int>(
              key: ValueKey(
                '${selectedProductId ?? 'none'}|${products.length}',
              ),
              controller: productSearchController,
              focusNode: productSearchFocusNode,
              initialSelection: selectedProductId,
              requestFocusOnTap: true,
              enableFilter: true,
              enableSearch: true,
              menuHeight: 280,
              width: double.infinity,
              leadingIcon: const Icon(Icons.search_rounded),
              label: const Text("Select Product"),
              hintText: "Tap to search or browse products",
              helperText: "Type a product name to filter the list.",
              filterCallback: _filterProductEntries,
              dropdownMenuEntries: _productMenuEntries,
              onSelected: _selectProduct,
            ),
            if (selectedProduct != null) ...[
              const SizedBox(height: 16),
              _buildMetricTile(
                context: context,
                label: "Available Stock",
                value: "${_availableStock()} units",
                icon: Icons.inventory_2_outlined,
                accentColor: const Color(0xFFFFB43A),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      context: context,
                      label: "Selling Price",
                      value: _formatCurrency(sellingPrice ?? 0),
                      icon: Icons.sell_outlined,
                      accentColor: const Color(0xFF5F95FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCostPriceTile(context, costPrice)),
                ],
              ),
              const SizedBox(height: 12),
              _buildMetricTile(
                context: context,
                label: "Stock After Sale",
                value: remainingStock == null
                    ? "Enter units to preview"
                    : "$remainingStock units",
                icon: Icons.inventory_outlined,
                accentColor: remainingColor,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: unitsController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onChanged: _refreshPreview,
              decoration: const InputDecoration(
                labelText: "Units Sold",
                helperText: "Enter how many units were sold in this sale.",
              ),
              validator: (value) {
                final units = int.tryParse(value?.trim() ?? '');
                if (units == null) {
                  return "Enter a whole number";
                }
                if (units <= 0) {
                  return "Units must be greater than 0";
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountInputField() {
    switch (discountMode) {
      case DiscountMode.manual:
        return TextFormField(
          key: const ValueKey('manual_discount'),
          controller: discountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onChanged: _refreshPreview,
          decoration: const InputDecoration(
            labelText: "Discount per Unit",
            prefixText: "Rs ",
          ),
          validator: (value) {
            final discount = double.tryParse(value?.trim() ?? '');
            final sellingPrice = _selectedSellingPrice();
            if (discount == null) {
              return "Enter a valid discount";
            }
            if (discount < 0) {
              return "Discount cannot be negative";
            }
            if (sellingPrice != null && discount > sellingPrice) {
              return "Discount cannot be higher than the selling price";
            }
            return null;
          },
        );
      case DiscountMode.soldPrice:
        return TextFormField(
          key: const ValueKey('sold_price'),
          controller: soldPriceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onChanged: _refreshPreview,
          decoration: const InputDecoration(
            labelText: "Sold Price per Unit",
            prefixText: "Rs ",
          ),
          validator: (value) {
            final soldPrice = double.tryParse(value?.trim() ?? '');
            final sellingPrice = _selectedSellingPrice();
            if (soldPrice == null) {
              return "Enter a valid sold price";
            }
            if (soldPrice < 0) {
              return "Sold price cannot be negative";
            }
            if (sellingPrice != null && soldPrice > sellingPrice) {
              return "Sold price cannot be higher than the selling price";
            }
            return null;
          },
        );
      case DiscountMode.percentage:
        return TextFormField(
          key: const ValueKey('percentage_discount'),
          controller: discountPercentController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onChanged: _refreshPreview,
          decoration: const InputDecoration(
            labelText: "Discount Percentage",
            suffixText: "%",
          ),
          validator: (value) {
            final percentage = double.tryParse(value?.trim() ?? '');
            if (percentage == null) {
              return "Enter a valid percentage";
            }
            if (percentage < 0 || percentage > 100) {
              return "Percentage must be between 0 and 100";
            }
            return null;
          },
        );
    }
  }

  Widget _buildDiscountCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Discount Setup",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _discountModeHint(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DiscountMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(_discountModeLabel(mode)),
                  selected: discountMode == mode,
                  onSelected: (_) => _changeDiscountMode(mode),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _buildDiscountInputField(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: discountController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Calculated Discount per Unit",
                prefixText: "Rs ",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
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

  Widget _buildProtectedProfitLossRow(
    BuildContext context, {
    required double? profit,
    Color? valueColor,
  }) {
    return InkWell(
      onTap: _toggleProfitLossVisibility,
      borderRadius: BorderRadius.circular(12),
      child: _buildSummaryRow(
        context,
        _showProfitLoss ? "Profit / Loss" : "Profit / Loss Hidden",
        _showProfitLoss ? _moneyOrPlaceholder(profit) : "Tap to show",
        valueColor: _showProfitLoss ? valueColor : null,
      ),
    );
  }

  String _moneyOrPlaceholder(double? value) {
    if (value == null) return "--";
    return _formatCurrency(value);
  }

  String _stockOrPlaceholder(int? value) {
    if (value == null) return "--";
    return "$value units";
  }

  Widget _buildSummaryCard(BuildContext context) {
    final profit = _profitPreview();
    final profitColor = profit == null
        ? null
        : profit < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.secondary;
    final soldPrice = _soldPricePreview();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Sale Summary",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              "These values update live as you edit the sale.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _buildSummaryRow(
              context,
              "Regular Total",
              _moneyOrPlaceholder(_grossTotalPreview()),
            ),
            _buildSummaryRow(
              context,
              "Total Discount",
              _moneyOrPlaceholder(_totalDiscountPreview()),
            ),
            _buildSummaryRow(
              context,
              "Sold Price per Unit",
              _moneyOrPlaceholder(soldPrice),
            ),
            _buildSummaryRow(
              context,
              "Net Sale Amount",
              _moneyOrPlaceholder(_netTotalPreview()),
            ),
            _buildProtectedProfitLossRow(
              context,
              profit: profit,
              valueColor: profitColor,
            ),
            _buildSummaryRow(
              context,
              "Remaining Stock",
              _stockOrPlaceholder(_remainingStockPreview()),
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
            onPressed: _isSaving ? null : _saveSale,
            icon: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isEditing ? Icons.save_as_outlined : Icons.check_circle,
                  ),
            label: Text(_isEditing ? "Update Sale" : "Save Sale"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _restoreForm,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_isEditing ? "Restore Original Values" : "Clear Form"),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasProducts = products.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? "Edit Sale" : "Record Sale")),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildIntroCard(context),
            if (!hasProducts && !_isEditing) ...[
              const SizedBox(height: 16),
              _buildEmptyStateCard(context),
            ] else ...[
              if (_missingExistingProduct) ...[
                const SizedBox(height: 16),
                _buildMissingProductCard(context),
              ],
              const SizedBox(height: 16),
              _buildSaleDetailsCard(context),
              const SizedBox(height: 16),
              _buildDiscountCard(context),
              const SizedBox(height: 16),
              _buildSummaryCard(context),
              const SizedBox(height: 16),
              _buildActionButtons(context),
            ],
          ],
        ),
      ),
    );
  }
}
