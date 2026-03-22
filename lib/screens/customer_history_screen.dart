import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../services/sale_bill_service.dart';
import 'add_sale_screen.dart';
import 'edit_customer_screen.dart';
import 'record_return_screen.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key, required this.customer});

  final Map<String, dynamic> customer;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  List<Map<String, dynamic>> _orders = [];
  late Map<String, dynamic> _customer;
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _customer = Map<String, dynamic>.from(widget.customer);
    _loadOrders();
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

  String _formatAmount(dynamic value) {
    final amount = _asDouble(value);
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2);
  }

  String _formatCurrency(dynamic value) {
    return "Rs ${_formatAmount(value)}";
  }

  String _formatResultValue(double value) {
    return _formatCurrency(value.abs());
  }

  String _resultLabel(double value) {
    return value < 0 ? "Loss" : "Profit";
  }

  String _paymentStatusLabel(dynamic value) {
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

  Color _paymentStatusColor(BuildContext context, dynamic value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'partial':
      case 'partially_paid':
        return const Color(0xFFFFB43A);
      case 'unpaid':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  DateTime? _parseOrderDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parseStrict(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  String _formatTime(DateTime? date) {
    if (date == null) return "--";
    return DateFormat('d MMM yyyy, h:mm a').format(date);
  }

  bool _hasReturns(Map<String, dynamic> order) =>
      _asDouble(order['returned_total']) > 0 ||
      _asInt(order['return_count']) > 0;

  Future<void> _loadOrders() async {
    final rows = await DatabaseHelper.instance.getCustomerSaleOrders(
      _asInt(_customer['id']),
    );
    if (!mounted) return;
    setState(() {
      _orders = rows;
      _isLoading = false;
    });
  }

  Future<void> _editCustomer() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditCustomerScreen(customer: _customer),
      ),
    );
    if (!mounted || updated != true) return;

    final refreshed = await DatabaseHelper.instance.getCustomerById(
      _asInt(_customer['id']),
    );
    if (!mounted) return;

    setState(() {
      if (refreshed != null) {
        _customer = refreshed;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _loadOrderItems(
    Map<String, dynamic> order,
  ) {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    return DatabaseHelper.instance.getSaleItemsForGroupKey(groupKey);
  }

  Future<List<Map<String, dynamic>>> _loadReturnRows(
    Map<String, dynamic> order,
  ) {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    return DatabaseHelper.instance.getSaleReturnsForGroupKey(groupKey);
  }

  Future<void> _shareBill(Map<String, dynamic> order) async {
    setState(() {
      _isBusy = true;
    });
    try {
      final items = await _loadOrderItems(order);
      if (items.isEmpty) return;
      await SaleBillService.sharePdfBill(order: order, items: items);
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _recordReturn(Map<String, dynamic> order) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordReturnScreen(order: order)),
    );
    if (!mounted || recorded != true) return;
    await _loadOrders();
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final items = await _loadOrderItems(order);
    final returns = await _loadReturnRows(order);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['bill_number']?.toString().trim().isNotEmpty == true
                      ? order['bill_number'].toString().trim()
                      : 'Sale #${order['id']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTime(_parseOrderDate(order['date']?.toString())),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                _CustomerOrderChip(
                  label: "Payment",
                  value: _paymentStatusLabel(order['payment_status']),
                  valueColor: _paymentStatusColor(
                    context,
                    order['payment_status'],
                  ),
                ),
                const SizedBox(height: 8),
                _CustomerOrderChip(
                  label: "Method",
                  value:
                      order['payment_method']?.toString().trim().isNotEmpty ==
                          true
                      ? order['payment_method'].toString().trim()
                      : 'Cash',
                ),
                const SizedBox(height: 8),
                _CustomerOrderChip(
                  label: "Received",
                  value: _formatCurrency(order['amount_paid']),
                ),
                const SizedBox(height: 8),
                _CustomerOrderChip(
                  label: "Due",
                  value: _formatCurrency(order['due_amount']),
                  valueColor: _asDouble(order['due_amount']) > 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 14),
                ...items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['product_name']?.toString() ??
                              item['name']?.toString() ??
                              'Product',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Qty ${_asInt(item['net_units'])} • SP ${_formatCurrency(item['selling_price'])} • Discount ${_formatCurrency(item['discount'])} • Total ${_formatCurrency(item['total'])}",
                        ),
                        if (_asDouble(item['returned_total']) > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Returned ${_formatCurrency(item['returned_total'])}",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                if (returns.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    "Returns",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...returns.map((entry) {
                    final restocked = _asInt(entry['restocked']) == 1;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withAlpha(10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['product_name']?.toString() ?? 'Product',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Qty ${_asInt(entry['units'])} • Refund ${_formatCurrency(entry['refund_amount'])}",
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${restocked ? 'Restocked' : 'Not restocked'} • ${entry['date']?.toString() ?? '--'}",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _recordReturn(order);
                    },
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text("Record Return"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _shareBill(order);
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text("Share Bill PDF"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editOrder(Map<String, dynamic> order) async {
    if (_hasReturns(order)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This sale already has returns recorded, so editing is disabled.",
          ),
        ),
      );
      return;
    }

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddSaleScreen(existingSale: order)),
    );
    if (!mounted || updated != true) return;
    await _loadOrders();
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final profit = _asDouble(order['profit']);
    final resultColor = profit < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.secondary;
    final paymentColor = _paymentStatusColor(context, order['payment_status']);
    final dueAmount = _asDouble(order['due_amount']);
    final returnedTotal = _asDouble(order['returned_total']);
    final productPreview =
        order['product_names']?.toString().trim().isNotEmpty == true
        ? order['product_names'].toString().trim()
        : 'Products not available';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order['bill_number']?.toString().trim().isNotEmpty == true
                          ? order['bill_number'].toString().trim()
                          : 'Sale #${order['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    _formatCurrency(order['total']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(_parseOrderDate(order['date']?.toString())),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(productPreview),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CustomerOrderChip(
                    label: "Items",
                    value: "${_asInt(order['item_count'])}",
                  ),
                  _CustomerOrderChip(
                    label: "Units",
                    value: "${_asInt(order['total_units'])}",
                  ),
                  _CustomerOrderChip(
                    label: _resultLabel(profit),
                    value: _formatResultValue(profit),
                    valueColor: resultColor,
                  ),
                  _CustomerOrderChip(
                    label: "Payment",
                    value: _paymentStatusLabel(order['payment_status']),
                    valueColor: paymentColor,
                  ),
                  if (returnedTotal > 0)
                    _CustomerOrderChip(
                      label: "Returned",
                      value: _formatCurrency(returnedTotal),
                      valueColor: Theme.of(context).colorScheme.tertiary,
                    ),
                  if (dueAmount > 0)
                    _CustomerOrderChip(
                      label: "Due",
                      value: _formatCurrency(dueAmount),
                      valueColor: Theme.of(context).colorScheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showOrderDetails(order),
                      icon: const Icon(Icons.info_outline),
                      label: const Text("Details"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editOrder(order),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text("Edit"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recordReturn(order),
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text("Return"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _shareBill(order),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text("Bill"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = _orders.fold<double>(
      0,
      (sum, order) => sum + _asDouble(order['total']),
    );
    final outstandingDue = _orders.fold<double>(
      0,
      (sum, order) => sum + _asDouble(order['due_amount']),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer History"),
        actions: [
          IconButton(
            onPressed: _editCustomer,
            icon: const Icon(Icons.edit_outlined),
            tooltip: "Edit Customer",
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _customer['name']?.toString().trim().isNotEmpty == true
                          ? _customer['name'].toString().trim()
                          : 'Unnamed Customer',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _customer['phone']?.toString().trim().isNotEmpty == true
                          ? _customer['phone'].toString().trim()
                          : 'Phone not saved',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _CustomerOrderChip(
                          label: "Orders",
                          value: "${_orders.length}",
                        ),
                        _CustomerOrderChip(
                          label: "Total Spent",
                          value: _formatCurrency(totalSpent),
                        ),
                        _CustomerOrderChip(
                          label: "Outstanding",
                          value: _formatCurrency(outstandingDue),
                          valueColor: outstandingDue > 0
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _editCustomer,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text("Edit Customer Details"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_orders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    "No purchases found for this customer yet.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ..._orders.map(_buildOrderCard),
            if (_isBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerOrderChip extends StatelessWidget {
  const _CustomerOrderChip({
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
