import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class RecordReturnScreen extends StatefulWidget {
  const RecordReturnScreen({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<RecordReturnScreen> createState() => _RecordReturnScreenState();
}

class _RecordReturnScreenState extends State<RecordReturnScreen> {
  final _reasonController = TextEditingController();

  List<_ReturnableSaleItem> _items = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _restockReturnedItems = true;

  String get _groupKey {
    final key = widget.order['group_key']?.toString();
    if (key != null && key.isNotEmpty) {
      return key;
    }
    return 'legacy-${widget.order['id']}';
  }

  @override
  void initState() {
    super.initState();
    _loadReturnableItems();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
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

  String _formatCurrency(double value) => "Rs ${_formatAmount(value)}";

  int get _selectedUnits =>
      _items.fold<int>(0, (sum, item) => sum + item.selectedUnits);

  double get _refundTotal =>
      _items.fold<double>(0, (sum, item) => sum + item.refundAmount);

  double get _profitAdjustment => _items.fold<double>(
    0,
    (sum, item) => sum + item.profitAdjustment(restock: _restockReturnedItems),
  );

  Future<void> _loadReturnableItems() async {
    final saleItems = await DatabaseHelper.instance.getSaleItemsForGroupKey(
      _groupKey,
    );
    final returnRows = await DatabaseHelper.instance.getSaleReturnsForGroupKey(
      _groupKey,
    );

    if (!mounted) return;

    final returnedUnitsBySaleId = <int, int>{};
    for (final row in returnRows) {
      final saleId = _asInt(row['sale_id']);
      returnedUnitsBySaleId[saleId] =
          (returnedUnitsBySaleId[saleId] ?? 0) + _asInt(row['units']);
    }

    final items = saleItems
        .map((item) {
          final saleId = _asInt(item['id']);
          return _ReturnableSaleItem(
            saleId: saleId,
            productId: _asInt(item['product_id']),
            productName:
                item['product_name']?.toString() ??
                item['name']?.toString() ??
                '',
            soldUnits: _asInt(item['units']),
            returnedUnits: returnedUnitsBySaleId[saleId] ?? 0,
            costPrice: _asDouble(item['cost_price']),
            sellingPrice: _asDouble(item['selling_price']),
            discount: _asDouble(item['discount']),
          );
        })
        .where((item) => item.availableUnits > 0)
        .toList();

    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeUnits(_ReturnableSaleItem item, int nextValue) {
    setState(() {
      if (nextValue < 0) {
        item.selectedUnits = 0;
      } else if (nextValue > item.availableUnits) {
        item.selectedUnits = item.availableUnits;
      } else {
        item.selectedUnits = nextValue;
      }
    });
  }

  Future<void> _saveReturn() async {
    if (_selectedUnits <= 0) {
      _showMessage("Select at least one unit to return");
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      final selectedItems = _items
          .where((item) => item.selectedUnits > 0)
          .map((item) => {'sale_id': item.saleId, 'units': item.selectedUnits})
          .toList();

      await DatabaseHelper.instance.recordSaleReturn(
        groupKey: _groupKey,
        items: selectedItems,
        restock: _restockReturnedItems,
        reason: _reasonController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
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

  Widget _buildItemCard(_ReturnableSaleItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName.isEmpty ? 'Product' : item.productName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReturnChip(label: "Sold", value: "${item.soldUnits}"),
                _ReturnChip(label: "Returned", value: "${item.returnedUnits}"),
                _ReturnChip(
                  label: "Available",
                  value: "${item.availableUnits}",
                  valueColor: colorScheme.secondary,
                ),
                _ReturnChip(
                  label: "Sold Price",
                  value: _formatCurrency(item.soldPrice),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: item.selectedUnits > 0
                      ? () => _changeUnits(item, item.selectedUnits - 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Return Quantity",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${item.selectedUnits}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: item.selectedUnits < item.availableUnits
                      ? () => _changeUnits(item, item.selectedUnits + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (item.selectedUnits > 0) ...[
              const SizedBox(height: 12),
              Text(
                "Refund ${_formatCurrency(item.refundAmount)} • ${_restockReturnedItems ? 'Profit reversal' : 'Loss impact'} ${_formatCurrency(item.profitAdjustment(restock: _restockReturnedItems).abs())}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Record Return")),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.order['bill_number']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                ? widget.order['bill_number'].toString().trim()
                                : 'Sale #${widget.order['id']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Select the returned quantity for each product. The original sale stays in history, and this return is recorded separately.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          "Everything from this sale has already been returned.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  else ...[
                    ..._items.map(_buildItemCard),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _restockReturnedItems,
                              title: const Text(
                                "Add returned units back to stock",
                              ),
                              subtitle: Text(
                                _restockReturnedItems
                                    ? "Use this for resellable returns."
                                    : "Turn this off for damaged items or refunds without stock recovery.",
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _restockReturnedItems = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _reasonController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: "Reason",
                                hintText: "Optional. Why was this returned?",
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ReturnChip(
                                  label: "Units",
                                  value: "$_selectedUnits",
                                ),
                                _ReturnChip(
                                  label: "Refund",
                                  value: _formatCurrency(_refundTotal),
                                ),
                                _ReturnChip(
                                  label: _restockReturnedItems
                                      ? "Profit Reversal"
                                      : "Loss Impact",
                                  value: _formatCurrency(
                                    _profitAdjustment.abs(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveReturn,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.assignment_return_outlined),
                      label: Text(
                        _isSaving ? "Saving Return..." : "Save Return",
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ReturnableSaleItem {
  _ReturnableSaleItem({
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.soldUnits,
    required this.returnedUnits,
    required this.costPrice,
    required this.sellingPrice,
    required this.discount,
  });

  final int saleId;
  final int productId;
  final String productName;
  final int soldUnits;
  final int returnedUnits;
  final double costPrice;
  final double sellingPrice;
  final double discount;
  int selectedUnits = 0;

  int get availableUnits => soldUnits - returnedUnits;

  double get soldPrice => sellingPrice - discount;

  double get refundAmount => soldPrice * selectedUnits;

  double profitAdjustment({required bool restock}) {
    if (restock) {
      return (soldPrice - costPrice) * selectedUnits;
    }
    return refundAmount;
  }
}

class _ReturnChip extends StatelessWidget {
  const _ReturnChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $value",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: valueColor,
        ),
      ),
    );
  }
}
