import 'package:flutter/material.dart';

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
  final _lineItemFormKey = GlobalKey<FormState>();

  final customerNameController = TextEditingController();
  final customerPhoneController = TextEditingController();
  final unitsController = TextEditingController();
  final discountController = TextEditingController();
  final soldPriceController = TextEditingController();
  final discountPercentController = TextEditingController();
  final productSearchController = TextEditingController();
  final productSearchFocusNode = FocusNode();

  List<Map<String, dynamic>> products = [];
  List<_DraftSaleItem> _items = [];
  List<_DraftSaleItem> _originalItems = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;
  double? _composerCostPrice;
  double? _composerSellingPrice;
  DiscountMode discountMode = DiscountMode.manual;
  bool _didLoadExistingSale = false;
  bool _missingExistingProduct = false;
  bool _isSaving = false;
  bool _showCostPrice = false;
  bool _showProfitLoss = false;
  int? _editingItemIndex;

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

  String get _groupKey {
    final existing = widget.existingSale;
    if (existing == null) return '';
    final key = existing['group_key']?.toString();
    if (key != null && key.isNotEmpty) return key;
    return 'legacy-${existing['id']}';
  }

  @override
  void initState() {
    super.initState();
    discountMode = _defaultDiscountMode;
    productSearchController.addListener(_handleProductSearchChanged);
    _loadProducts();
  }

  @override
  void dispose() {
    productSearchController.removeListener(_handleProductSearchChanged);
    customerNameController.dispose();
    customerPhoneController.dispose();
    unitsController.dispose();
    discountController.dispose();
    soldPriceController.dispose();
    discountPercentController.dispose();
    productSearchController.dispose();
    productSearchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;

    setState(() {
      products = data;
    });

    await _populateExistingSale();
  }

  Future<void> _populateExistingSale() async {
    if (!_isEditing || _didLoadExistingSale) return;

    final items = await DatabaseHelper.instance.getSaleItemsForGroupKey(
      _groupKey,
    );
    if (!mounted) return;

    final draftItems = items.map(_DraftSaleItem.fromMap).toList();
    var missingProduct = false;
    for (final item in draftItems) {
      final exists = products.any((product) => product['id'] == item.productId);
      if (!exists) {
        missingProduct = true;
        break;
      }
    }

    setState(() {
      _didLoadExistingSale = true;
      _missingExistingProduct = missingProduct;
      _showCostPrice = false;
      _showProfitLoss = false;
      _items = draftItems;
      _originalItems = draftItems.map((item) => item.copy()).toList();
      customerNameController.text =
          widget.existingSale?['customer_name']?.toString() ?? '';
      customerPhoneController.text =
          widget.existingSale?['customer_phone']?.toString() ?? '';
      discountMode = _defaultDiscountMode;
    });
  }

  Future<void> _openAddProduct() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );

    if (!mounted) return;
    await _loadProducts();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
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

  double? _selectedSellingPrice() => _composerSellingPrice;

  double? _selectedCostPrice() => _composerCostPrice;

  int _baseAvailableStockForProduct(int productId) {
    Map<String, dynamic>? matchedProduct;
    for (final product in products) {
      if (product['id'] == productId) {
        matchedProduct = product;
        break;
      }
    }

    if (matchedProduct == null) return 0;

    var stock = _asInt(matchedProduct['stock']);
    for (final item in _originalItems) {
      if (item.productId == productId) {
        stock += item.units;
      }
    }
    return stock;
  }

  int _reservedUnitsInDraftForProduct(int productId) {
    var total = 0;
    for (var index = 0; index < _items.length; index++) {
      if (_editingItemIndex != null && _editingItemIndex == index) {
        continue;
      }
      final item = _items[index];
      if (item.productId == productId) {
        total += item.units;
      }
    }
    return total;
  }

  int _availableStockForComposer() {
    final productId = selectedProductId;
    if (productId == null) return 0;
    return _baseAvailableStockForProduct(productId) -
        _reservedUnitsInDraftForProduct(productId);
  }

  int? _parsedUnits() => int.tryParse(unitsController.text.trim());

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

  void _refreshPreview([String _ = '']) {
    if (discountMode == DiscountMode.manual) {
      setState(() {});
    } else {
      _syncCalculatedDiscount();
    }
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

  int? _remainingStockPreview() {
    final units = _parsedUnits();
    if (selectedProduct == null || units == null || units <= 0) return null;
    return _availableStockForComposer() - units;
  }

  void _setComposerProduct(Map<String, dynamic>? product) {
    selectedProduct = product;
    selectedProductId = product == null ? null : product['id'] as int;
    _composerCostPrice = product == null
        ? null
        : _asDouble(product['cost_price']);
    _composerSellingPrice = product == null
        ? null
        : _asDouble(product['selling_price']);
    productSearchController.text = product == null
        ? ''
        : product['name'].toString();
  }

  void _selectProduct(int? value) {
    Map<String, dynamic>? nextProduct;
    if (value != null) {
      for (final product in products) {
        if (product['id'] == value) {
          nextProduct = product;
          break;
        }
      }
    }

    setState(() {
      _showCostPrice = false;
      _showProfitLoss = false;
      _setComposerProduct(nextProduct);
      if (value != null) {
        _missingExistingProduct = false;
      }
    });

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
        _setComposerProduct(null);
      });
      _syncCalculatedDiscount();
      return;
    }

    setState(() {});
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

  void _clearComposer({bool keepCustomer = true}) {
    FocusScope.of(context).unfocus();
    _lineItemFormKey.currentState?.reset();
    setState(() {
      _editingItemIndex = null;
      _showCostPrice = false;
      _setComposerProduct(null);
      discountMode = _defaultDiscountMode;
      unitsController.clear();
      discountController.clear();
      soldPriceController.clear();
      discountPercentController.clear();
      if (!keepCustomer) {
        customerNameController.clear();
        customerPhoneController.clear();
      }
    });
  }

  void _restoreForm() {
    FocusScope.of(context).unfocus();

    if (_isEditing) {
      setState(() {
        _items = _originalItems.map((item) => item.copy()).toList();
        customerNameController.text =
            widget.existingSale?['customer_name']?.toString() ?? '';
        customerPhoneController.text =
            widget.existingSale?['customer_phone']?.toString() ?? '';
      });
      _clearComposer();
      return;
    }

    setState(() {
      _items = [];
      customerNameController.clear();
      customerPhoneController.clear();
    });
    _clearComposer(keepCustomer: false);
  }

  void _addOrUpdateCurrentItem() {
    if (selectedProduct == null || selectedProductId == null) {
      _showMessage("Select a product first");
      return;
    }

    final form = _lineItemFormKey.currentState;
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

    final availableStock = _availableStockForComposer();
    if (units > availableStock) {
      _showMessage("Not enough stock for this product");
      return;
    }

    final duplicateIndex = _items.indexWhere(
      (item) => item.productId == selectedProductId,
    );
    if (_editingItemIndex == null &&
        duplicateIndex != -1 &&
        duplicateIndex < _items.length) {
      _showMessage("This product is already in the sale. Edit it instead.");
      return;
    }

    final nextItem = _DraftSaleItem(
      productId: selectedProductId!,
      productName: selectedProduct!['name'].toString(),
      units: units,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      discount: discount,
    );

    setState(() {
      if (_editingItemIndex != null) {
        _items[_editingItemIndex!] = nextItem;
      } else {
        _items.add(nextItem);
      }
    });

    _clearComposer();
  }

  void _editLineItem(int index) {
    final item = _items[index];
    Map<String, dynamic>? matchedProduct;
    for (final product in products) {
      if (product['id'] == item.productId) {
        matchedProduct = product;
        break;
      }
    }

    if (matchedProduct == null) {
      _showMessage(
        "This product is no longer in inventory. Remove it or choose another product.",
      );
      return;
    }

    setState(() {
      _editingItemIndex = index;
      _showCostPrice = false;
      _setComposerProduct(matchedProduct);
      _composerCostPrice = item.costPrice;
      _composerSellingPrice = item.sellingPrice;
      unitsController.text = item.units.toString();
      discountMode = DiscountMode.manual;
      discountController.text = _formatAmount(item.discount);
      soldPriceController.text = _formatAmount(item.soldPrice);
      discountPercentController.text = item.sellingPrice > 0
          ? _formatAmount((item.discount / item.sellingPrice) * 100)
          : '';
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _items.removeAt(index);
      if (_editingItemIndex == index) {
        _editingItemIndex = null;
      } else if (_editingItemIndex != null && _editingItemIndex! > index) {
        _editingItemIndex = _editingItemIndex! - 1;
      }
    });
  }

  double _cartSubtotal() {
    var total = 0.0;
    for (final item in _items) {
      total += item.sellingPrice * item.units;
    }
    return total;
  }

  double _cartDiscountTotal() {
    var total = 0.0;
    for (final item in _items) {
      total += item.totalDiscount;
    }
    return total;
  }

  double _cartNetTotal() {
    var total = 0.0;
    for (final item in _items) {
      total += item.total;
    }
    return total;
  }

  double _cartProfit() {
    var total = 0.0;
    for (final item in _items) {
      total += item.profit;
    }
    return total;
  }

  int _cartUnits() {
    var total = 0;
    for (final item in _items) {
      total += item.units;
    }
    return total;
  }

  Future<void> _saveSale() async {
    if (_items.isEmpty) {
      _showMessage("Add at least one product to the sale");
      return;
    }

    final customerPhone = customerPhoneController.text.trim();
    if (customerPhone.isNotEmpty && customerPhone.length < 6) {
      _showMessage("Enter a valid customer phone number");
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      final itemMaps = _items.map((item) => item.toMap()).toList();
      if (_isEditing) {
        await DatabaseHelper.instance.updateSaleOrder(
          groupKey: _groupKey,
          items: itemMaps,
          customerName: customerNameController.text,
          customerPhone: customerPhoneController.text,
        );
      } else {
        await DatabaseHelper.instance.createSaleOrder(
          items: itemMaps,
          customerName: customerNameController.text,
          customerPhone: customerPhoneController.text,
        );
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
                        ? "Edit multiple sale items, customer details, and totals in one place."
                        : "Add one or more products to the sale, then save the full order together.",
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
                "One or more products from this old sale no longer exist in inventory. You can still review the order, but replace or remove missing items before saving changes.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Customer Details",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              "Optional. Add a name or phone number to save this customer with the sale.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: customerNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: "Customer Name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customerPhoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: "Phone Number"),
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

  Widget _buildCurrentItemCard(BuildContext context) {
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
        child: Form(
          key: _lineItemFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _editingItemIndex == null
                          ? "Add Product to Sale"
                          : "Edit Product in Sale",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_editingItemIndex != null)
                    TextButton.icon(
                      onPressed: _clearComposer,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text("Cancel Edit"),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Pick a product, apply discount, and add it to the running sale.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              DropdownMenu<int>(
                key: ValueKey(
                  '${selectedProductId ?? 'none'}|${products.length}|${_editingItemIndex ?? 'new'}',
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
                  value: "${_availableStockForComposer()} units",
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
                  label: "Stock After This Item",
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
                  helperText: "Enter how many units of this product were sold.",
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addOrUpdateCurrentItem,
                icon: Icon(
                  _editingItemIndex == null
                      ? Icons.add_shopping_cart_rounded
                      : Icons.check_rounded,
                ),
                label: Text(
                  _editingItemIndex == null
                      ? "Add Product to Sale"
                      : "Update Product in Sale",
                ),
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
    BuildContext context,
    double profit,
    Color? valueColor,
  ) {
    return InkWell(
      onTap: _toggleProfitLossVisibility,
      borderRadius: BorderRadius.circular(12),
      child: _buildSummaryRow(
        context,
        _showProfitLoss ? "Profit / Loss" : "Profit / Loss Hidden",
        _showProfitLoss ? _formatCurrency(profit) : "Tap to show",
        valueColor: _showProfitLoss ? valueColor : null,
      ),
    );
  }

  Widget _buildLineItemTile(
    BuildContext context,
    _DraftSaleItem item,
    int index,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _editLineItem(index),
                icon: const Icon(Icons.edit_outlined),
                tooltip: "Edit item",
              ),
              IconButton(
                onPressed: () => _removeLineItem(index),
                icon: const Icon(Icons.delete_outline),
                tooltip: "Remove item",
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DetailChip(label: "Qty", value: "${item.units}"),
              _DetailChip(
                label: "Selling Price",
                value: _formatCurrency(item.sellingPrice),
              ),
              _DetailChip(
                label: "Discount",
                value: _formatCurrency(item.discount),
              ),
              _DetailChip(
                label: "Line Total",
                value: _formatCurrency(item.total),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final totalProfit = _cartProfit();
    final profitColor = totalProfit < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.secondary;

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
              _items.isEmpty
                  ? "Add products to build the sale summary."
                  : "Review the products, discounts, and final amount before saving.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  "No products added yet.",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ...List.generate(_items.length, (index) {
                return _buildLineItemTile(context, _items[index], index);
              }),
            const Divider(height: 24),
            _buildSummaryRow(
              context,
              "Products in Sale",
              "${_items.length} item${_items.length == 1 ? '' : 's'}",
            ),
            _buildSummaryRow(context, "Total Units", "${_cartUnits()} units"),
            _buildSummaryRow(
              context,
              "Regular Total",
              _formatCurrency(_cartSubtotal()),
            ),
            _buildSummaryRow(
              context,
              "Total Discount",
              _formatCurrency(_cartDiscountTotal()),
            ),
            _buildProtectedProfitLossRow(context, totalProfit, profitColor),
            const SizedBox(height: 6),
            _buildSummaryRow(
              context,
              "Amount to Pay",
              _formatCurrency(_cartNetTotal()),
              valueColor: Theme.of(context).colorScheme.primary,
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
            label: Text(_isEditing ? "Restore Original Values" : "Clear Sale"),
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
      body: ListView(
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
            _buildCustomerCard(context),
            const SizedBox(height: 16),
            _buildCurrentItemCard(context),
            const SizedBox(height: 16),
            _buildDiscountCard(context),
            const SizedBox(height: 16),
            _buildSummaryCard(context),
            const SizedBox(height: 16),
            _buildActionButtons(context),
          ],
        ],
      ),
    );
  }
}

class _DraftSaleItem {
  const _DraftSaleItem({
    required this.productId,
    required this.productName,
    required this.units,
    required this.costPrice,
    required this.sellingPrice,
    required this.discount,
  });

  final int productId;
  final String productName;
  final int units;
  final double costPrice;
  final double sellingPrice;
  final double discount;

  double get soldPrice => sellingPrice - discount;

  double get totalDiscount => discount * units;

  double get total => soldPrice * units;

  double get profit => (soldPrice - costPrice) * units;

  _DraftSaleItem copy() {
    return _DraftSaleItem(
      productId: productId,
      productName: productName,
      units: units,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      discount: discount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'units': units,
      'discount': discount,
      'total': total,
      'profit': profit,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
    };
  }

  factory _DraftSaleItem.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _DraftSaleItem(
      productId: asInt(map['product_id']),
      productName:
          map['product_name']?.toString() ?? map['name']?.toString() ?? '',
      units: asInt(map['units']),
      costPrice: asDouble(map['cost_price']),
      sellingPrice: asDouble(map['selling_price']),
      discount: asDouble(map['discount']),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(120),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(40),
        ),
      ),
      child: Text(
        "$label: $value",
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
