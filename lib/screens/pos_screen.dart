import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import 'add_product_screen.dart';
import 'barcode_scanner_screen.dart';

enum _PosPaymentStatus { paid, partial, unpaid }

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _discountController = TextEditingController();
  final _amountReceivedController = TextEditingController();

  static const _paymentMethods = [
    'Cash',
    'UPI',
    'Card',
    'Bank Transfer',
    'Credit',
    'Cheque',
    'Other',
  ];

  List<Map<String, dynamic>> _products = [];
  final List<_PosCartItem> _cart = [];
  String _query = '';
  String _paymentMethod = _paymentMethods.first;
  _PosPaymentStatus _paymentStatus = _PosPaymentStatus.paid;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text;
      });
    });
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountController.dispose();
    _amountReceivedController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _isLoading = false;
    });
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

  String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return "Rs ${value.toStringAsFixed(0)}";
    }
    return "Rs ${value.toStringAsFixed(2)}";
  }

  Uint8List? _productPhotoBytes(Map<String, dynamic> product) {
    final value = product['photo_bytes'];
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  String _barcodeFromProduct(Map<String, dynamic> product) {
    return product['barcode']?.toString().trim() ?? '';
  }

  Map<String, dynamic>? _loadedProductByBarcode(String barcode) {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    for (final product in _products) {
      if (_barcodeFromProduct(product) == cleanBarcode) {
        return product;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleProducts {
    final cleanQuery = _query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return _products;
    return _products.where((product) {
      final name = product['name']?.toString().toLowerCase() ?? '';
      final barcode = _barcodeFromProduct(product).toLowerCase();
      return name.contains(cleanQuery) || barcode.contains(cleanQuery);
    }).toList();
  }

  int _cartUnitsForProduct(int productId) {
    var units = 0;
    for (final item in _cart) {
      if (item.productId == productId) units += item.units;
    }
    return units;
  }

  double get _subtotal {
    var total = 0.0;
    for (final item in _cart) {
      total += item.lineSubtotal;
    }
    return total;
  }

  double get _discountTotal {
    final discount = double.tryParse(_discountController.text.trim()) ?? 0;
    if (discount < 0) return 0;
    if (discount > _subtotal) return _subtotal;
    return discount;
  }

  double get _netTotal => _subtotal - _discountTotal;

  double get _amountReceived {
    switch (_paymentStatus) {
      case _PosPaymentStatus.paid:
        return _netTotal;
      case _PosPaymentStatus.unpaid:
        return 0;
      case _PosPaymentStatus.partial:
        return double.tryParse(_amountReceivedController.text.trim()) ?? 0;
    }
  }

  double get _dueAmount {
    final due = _netTotal - _amountReceived;
    return due > 0 ? due : 0;
  }

  String _paymentStatusKey(_PosPaymentStatus status) {
    switch (status) {
      case _PosPaymentStatus.paid:
        return 'paid';
      case _PosPaymentStatus.partial:
        return 'partial';
      case _PosPaymentStatus.unpaid:
        return 'unpaid';
    }
  }

  String _paymentStatusLabel(_PosPaymentStatus status) {
    switch (status) {
      case _PosPaymentStatus.paid:
        return 'Paid';
      case _PosPaymentStatus.partial:
        return 'Partial';
      case _PosPaymentStatus.unpaid:
        return 'Unpaid';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addProduct(Map<String, dynamic> product) {
    final productId = _asInt(product['id']);
    final stock = _asInt(product['stock']);
    final cartUnits = _cartUnitsForProduct(productId);
    if (stock <= cartUnits) {
      _showMessage("No more stock available for ${product['name']}");
      return;
    }

    setState(() {
      final existingIndex = _cart.indexWhere(
        (item) => item.productId == productId,
      );
      if (existingIndex == -1) {
        _cart.add(
          _PosCartItem(
            productId: productId,
            productName: product['name']?.toString() ?? 'Product',
            costPrice: _asDouble(product['cost_price']),
            sellingPrice: _asDouble(product['selling_price']),
            stock: stock,
            units: 1,
          ),
        );
      } else {
        _cart[existingIndex] = _cart[existingIndex].copyWith(
          units: _cart[existingIndex].units + 1,
        );
      }
    });
  }

  void _changeUnits(_PosCartItem item, int delta) {
    final index = _cart.indexWhere(
      (entry) => entry.productId == item.productId,
    );
    if (index == -1) return;
    final nextUnits = item.units + delta;
    setState(() {
      if (nextUnits <= 0) {
        _cart.removeAt(index);
      } else if (nextUnits <= item.stock) {
        _cart[index] = item.copyWith(units: nextUnits);
      } else {
        _showMessage("Only ${item.stock} in stock");
      }
    });
  }

  Future<void> _openAddProduct({String? initialBarcode}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(initialBarcode: initialBarcode),
      ),
    );
    if (!mounted) return;
    await _loadProducts();
  }

  Future<bool> _confirmAddScannedProduct(String barcode) async {
    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Product Not Found"),
          content: Text(
            "No saved product uses barcode $barcode. Add it to inventory first?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text("Add Product"),
            ),
          ],
        );
      },
    );

    return shouldAdd == true;
  }

  Future<void> _scanBarcodeToCart() async {
    FocusScope.of(context).unfocus();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: "Scan for POS"),
      ),
    );
    final cleanBarcode = code?.trim() ?? '';
    if (cleanBarcode.isEmpty) return;

    await _loadProducts();
    var product =
        _loadedProductByBarcode(cleanBarcode) ??
        await DatabaseHelper.instance.findProductByBarcode(cleanBarcode);

    if (product == null) {
      final shouldAdd = await _confirmAddScannedProduct(cleanBarcode);
      if (!mounted || !shouldAdd) return;
      await _openAddProduct(initialBarcode: cleanBarcode);
      product =
          _loadedProductByBarcode(cleanBarcode) ??
          await DatabaseHelper.instance.findProductByBarcode(cleanBarcode);
      if (!mounted || product == null) return;
    }

    _searchController.text = product['name']?.toString() ?? '';
    _addProduct(product);
  }

  String? _checkoutValidationMessage() {
    if (_cart.isEmpty) return 'Add at least one product to the cart';
    if (_customerPhoneController.text.trim().isNotEmpty &&
        _customerPhoneController.text.trim().length < 6) {
      return 'Enter a valid customer phone number';
    }
    final typedDiscount = double.tryParse(_discountController.text.trim()) ?? 0;
    if (typedDiscount < 0) return 'Discount cannot be negative';
    if (typedDiscount > _subtotal) return 'Discount cannot exceed subtotal';
    if (_paymentStatus == _PosPaymentStatus.partial) {
      final received = double.tryParse(_amountReceivedController.text.trim());
      if (received == null || received <= 0 || received >= _netTotal) {
        return 'Enter an amount received that is more than 0 and less than the total';
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _cartToSaleItems() {
    final subtotal = _subtotal;
    return _cart.map((item) {
      final discountShare = subtotal <= 0
          ? 0.0
          : _discountTotal * (item.lineSubtotal / subtotal);
      final unitDiscount = item.units <= 0 ? 0.0 : discountShare / item.units;
      final soldPrice = item.sellingPrice - unitDiscount;
      return {
        'product_id': item.productId,
        'product_name': item.productName,
        'units': item.units,
        'discount': unitDiscount,
        'total': soldPrice * item.units,
        'profit': (soldPrice - item.costPrice) * item.units,
        'cost_price': item.costPrice,
        'selling_price': item.sellingPrice,
      };
    }).toList();
  }

  Future<void> _checkout() async {
    final message = _checkoutValidationMessage();
    if (message != null) {
      _showMessage(message);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseHelper.instance.createSaleOrder(
        items: _cartToSaleItems(),
        customerName: _customerNameController.text,
        customerPhone: _customerPhoneController.text,
        paymentStatus: _paymentStatusKey(_paymentStatus),
        paymentMethod: _paymentMethod,
        amountPaid: _amountReceived,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: "Search products for POS",
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.trim().isEmpty
            ? null
            : IconButton(
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product) {
    final colorScheme = Theme.of(context).colorScheme;
    final productId = _asInt(product['id']);
    final stock = _asInt(product['stock']);
    final available = stock - _cartUnitsForProduct(productId);
    final photoBytes = _productPhotoBytes(product);
    final barcode = _barcodeFromProduct(product);
    final canAdd = available > 0;

    return Card(
      child: InkWell(
        onTap: canAdd ? () => _addProduct(product) : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: photoBytes == null
                    ? Icon(
                        Icons.inventory_2_outlined,
                        color: colorScheme.primary,
                      )
                    : Image.memory(photoBytes, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name']?.toString() ?? 'Product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${_formatMoney(_asDouble(product['selling_price']))} - Stock $available${barcode.isEmpty ? '' : ' - $barcode'}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                canAdd ? Icons.add_circle_rounded : Icons.block_rounded,
                color: canAdd ? colorScheme.primary : colorScheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsPanel() {
    final visibleProducts = _visibleProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                "Products",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: "Scan barcode",
              onPressed: _scanBarcodeToCart,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
            TextButton.icon(
              onPressed: () => _openAddProduct(),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text("Add"),
            ),
          ],
        ),
        if (visibleProducts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _products.isEmpty
                    ? "No products available. Add products before using POS."
                    : "No products match your search.",
              ),
            ),
          )
        else
          ...visibleProducts.map(_buildProductTile),
      ],
    );
  }

  Widget _buildCartItem(_PosCartItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  "${_formatMoney(item.sellingPrice)} each",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _changeUnits(item, -1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            item.units.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          IconButton(
            onPressed: item.units >= item.stock
                ? null
                : () => _changeUnits(item, 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          SizedBox(
            width: 86,
            child: Text(
              _formatMoney(item.lineSubtotal),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentControls() {
    return Column(
      children: [
        SegmentedButton<_PosPaymentStatus>(
          segments: _PosPaymentStatus.values.map((status) {
            return ButtonSegment<_PosPaymentStatus>(
              value: status,
              label: Text(_paymentStatusLabel(status)),
            );
          }).toList(),
          selected: {_paymentStatus},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            setState(() {
              _paymentStatus = selection.first;
              if (_paymentStatus != _PosPaymentStatus.partial) {
                _amountReceivedController.clear();
              }
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _paymentMethod,
          decoration: const InputDecoration(labelText: "Payment method"),
          items: _paymentMethods.map((method) {
            return DropdownMenuItem(value: method, child: Text(method));
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _paymentMethod = value;
            });
          },
        ),
        if (_paymentStatus == _PosPaymentStatus.partial) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _amountReceivedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Amount received"),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: strong ? 18 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "POS Cart",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_cart.clear),
                    child: const Text("Clear"),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_cart.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text("Tap products to add them to the cart."),
              )
            else
              ..._cart.map(_buildCartItem),
            const SizedBox(height: 12),
            TextField(
              controller: _customerNameController,
              decoration: const InputDecoration(labelText: "Customer name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Customer phone"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: "Bill discount",
                hintText: "Optional total discount",
              ),
            ),
            const SizedBox(height: 16),
            _buildPaymentControls(),
            const Divider(height: 28),
            _buildSummaryRow("Subtotal", _formatMoney(_subtotal)),
            _buildSummaryRow("Discount", "- ${_formatMoney(_discountTotal)}"),
            _buildSummaryRow("Received", _formatMoney(_amountReceived)),
            _buildSummaryRow("Due", _formatMoney(_dueAmount)),
            _buildSummaryRow("Total", _formatMoney(_netTotal), strong: true),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _checkout,
              icon: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.point_of_sale_rounded),
              label: Text(_isSaving ? "Saving" : "Complete POS Sale"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("POS Terminal")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [_buildProductsPanel()],
                        ),
                      ),
                      SizedBox(
                        width: 420,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                          children: [_buildCartPanel()],
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildProductsPanel(),
                    const SizedBox(height: 16),
                    _buildCartPanel(),
                  ],
                );
              },
            ),
    );
  }
}

class _PosCartItem {
  const _PosCartItem({
    required this.productId,
    required this.productName,
    required this.costPrice,
    required this.sellingPrice,
    required this.stock,
    required this.units,
  });

  final int productId;
  final String productName;
  final double costPrice;
  final double sellingPrice;
  final int stock;
  final int units;

  double get lineSubtotal => sellingPrice * units;

  _PosCartItem copyWith({int? units}) {
    return _PosCartItem(
      productId: productId,
      productName: productName,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      stock: stock,
      units: units ?? this.units,
    );
  }
}
