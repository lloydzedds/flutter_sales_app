import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../services/sale_bill_service.dart';
import 'add_sale_screen.dart';
import 'record_return_screen.dart';

enum _BillSearchScope { all, product, customer }

class BillSearchScreen extends StatefulWidget {
  const BillSearchScreen({super.key});

  @override
  State<BillSearchScreen> createState() => _BillSearchScreenState();
}

class _BillSearchScreenState extends State<BillSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allOrders = [];
  bool _isLoading = true;
  bool _isBusy = false;
  bool _walkInOnly = false;
  _BillSearchScope _searchScope = _BillSearchScope.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    final rows = await DatabaseHelper.instance.getSaleOrders();
    if (!mounted) return;

    setState(() {
      _allOrders = rows;
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

  String _formatSectionDate(DateTime date) {
    return DateFormat('EEE, d MMM yyyy').format(date);
  }

  String _formatTime(DateTime? date) {
    if (date == null) return "--";
    return DateFormat('h:mm a').format(date);
  }

  String _normalized(String value) => value.trim().toLowerCase();

  String _customerLabel(Map<String, dynamic> order) {
    final name = order['customer_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Walk-in Customer' : name;
  }

  bool _hasReturns(Map<String, dynamic> order) =>
      _asDouble(order['returned_total']) > 0 ||
      _asInt(order['return_count']) > 0;

  bool _isWalkInOrder(Map<String, dynamic> order) {
    final customerId = _asInt(order['customer_id']);
    final customerName = order['customer_name']?.toString().trim() ?? '';
    final phone = order['customer_phone']?.toString().trim() ?? '';
    return customerId <= 0 &&
        phone.isEmpty &&
        (customerName.isEmpty ||
            _normalized(customerName) == 'walk-in customer');
  }

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  bool get _hasFilters =>
      _hasSearchQuery ||
      _walkInOnly ||
      _searchScope != _BillSearchScope.all;

  List<Map<String, dynamic>> get _orders {
    final query = _normalized(_searchController.text);
    return _allOrders.where((order) {
      if (_walkInOnly && !_isWalkInOrder(order)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final billNumber = order['bill_number']?.toString() ?? '';
      final productNames = order['product_names']?.toString() ?? '';
      final customerName = _customerLabel(order);
      final customerPhone = order['customer_phone']?.toString() ?? '';

      switch (_searchScope) {
        case _BillSearchScope.product:
          return _normalized(productNames).contains(query);
        case _BillSearchScope.customer:
          return _normalized(customerName).contains(query) ||
              _normalized(customerPhone).contains(query);
        case _BillSearchScope.all:
          return [
            billNumber,
            productNames,
            customerName,
            customerPhone,
          ].any((value) => _normalized(value).contains(query));
      }
    }).toList();
  }

  String _searchHint() {
    switch (_searchScope) {
      case _BillSearchScope.product:
        return "Search by sold product name";
      case _BillSearchScope.customer:
        return "Search by customer name or phone";
      case _BillSearchScope.all:
        return "Search bill no, product, customer, or phone";
    }
  }

  String _scopeLabel(_BillSearchScope scope) {
    switch (scope) {
      case _BillSearchScope.product:
        return "Product";
      case _BillSearchScope.customer:
        return "Customer";
      case _BillSearchScope.all:
        return "All";
    }
  }

  void _clearFilters() {
    _searchController.clear();
    if (!mounted) return;

    setState(() {
      _walkInOnly = false;
      _searchScope = _BillSearchScope.all;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _productPreview(Map<String, dynamic> order) {
    final raw = order['product_names']?.toString() ?? '';
    if (raw.trim().isEmpty) return 'Products not available';

    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length <= 2) {
      return parts.join(' | ');
    }
    return "${parts.take(2).join(' | ')} +${parts.length - 2} more";
  }

  Future<List<Map<String, dynamic>>> _loadOrderItems(
    Map<String, dynamic> order,
  ) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    return DatabaseHelper.instance.getSaleItemsForGroupKey(groupKey);
  }

  Future<List<Map<String, dynamic>>> _loadReturnRows(
    Map<String, dynamic> order,
  ) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    return DatabaseHelper.instance.getSaleReturnsForGroupKey(groupKey);
  }

  Future<void> _shareBill(Map<String, dynamic> order) async {
    setState(() {
      _isBusy = true;
    });

    try {
      final items = await _loadOrderItems(order);
      if (items.isEmpty) {
        _showMessage("Could not find sale items for this bill");
        return;
      }

      await SaleBillService.sharePdfBill(order: order, items: items);
      if (!mounted) return;
      _showMessage("Bill ready to share");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    try {
      await DatabaseHelper.instance.deleteSaleOrder(groupKey);
      if (!mounted) return;

      await _loadOrders();
      if (!mounted) return;

      _showMessage("Sale deleted");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editSale(Map<String, dynamic> order) async {
    if (_hasReturns(order)) {
      _showMessage(
        "This sale already has returns recorded, so editing is disabled.",
      );
      return;
    }

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddSaleScreen(existingSale: order)),
    );
    if (!mounted || updated != true) return;

    await _loadOrders();
    if (!mounted) return;
    _showMessage("Sale updated");
  }

  Future<void> _recordReturn(Map<String, dynamic> order) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordReturnScreen(order: order)),
    );
    if (!mounted || recorded != true) return;

    await _loadOrders();
    if (!mounted) return;
    _showMessage("Return recorded");
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final items = await _loadOrderItems(order);
    final returns = await _loadReturnRows(order);
    if (!mounted) return;

    final profit = _asDouble(order['profit']);
    final colorScheme = Theme.of(context).colorScheme;
    final returnedTotal = _asDouble(order['returned_total']);
    final returnedUnits = returns.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['units']),
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
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
                  order['date']?.toString() ?? '--',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                _buildDetailRow("Customer", _customerLabel(order)),
                if (order['customer_phone']?.toString().trim().isNotEmpty ==
                    true)
                  _buildDetailRow("Phone", order['customer_phone'].toString()),
                _buildDetailRow(
                  "Products",
                  "${_asInt(order['item_count'])} item(s)",
                ),
                _buildDetailRow(
                  "Units",
                  "${_asInt(order['total_units'])} units",
                ),
                if (_hasReturns(order)) ...[
                  _buildDetailRow(
                    "Gross Total",
                    _formatCurrency(order['gross_total']),
                  ),
                  _buildDetailRow(
                    "Returned",
                    "${_formatCurrency(returnedTotal)} | $returnedUnits unit(s)",
                    valueColor: colorScheme.tertiary,
                  ),
                  _buildDetailRow("Net Total", _formatCurrency(order['total'])),
                ] else
                  _buildDetailRow("Total", _formatCurrency(order['total'])),
                _buildDetailRow(
                  "Payment Status",
                  _paymentStatusLabel(order['payment_status']),
                  valueColor: _paymentStatusColor(
                    context,
                    order['payment_status'],
                  ),
                ),
                _buildDetailRow(
                  "Payment Method",
                  order['payment_method']?.toString().trim().isNotEmpty == true
                      ? order['payment_method'].toString().trim()
                      : 'Cash',
                ),
                _buildDetailRow(
                  "Amount Received",
                  _formatCurrency(order['amount_paid']),
                ),
                _buildDetailRow(
                  "Due Amount",
                  _formatCurrency(order['due_amount']),
                  valueColor: _asDouble(order['due_amount']) > 0
                      ? colorScheme.error
                      : colorScheme.secondary,
                ),
                _buildDetailRow(
                  _resultLabel(profit),
                  _formatResultValue(profit),
                  valueColor: profit < 0
                      ? colorScheme.error
                      : colorScheme.secondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Products",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ...items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(10),
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _BillSearchChip(
                              label: "Qty",
                              value: "${_asInt(item['net_units'])}",
                            ),
                            _BillSearchChip(
                              label: "SP",
                              value: _formatCurrency(item['selling_price']),
                            ),
                            _BillSearchChip(
                              label: "Discount",
                              value: _formatCurrency(item['discount']),
                            ),
                            _BillSearchChip(
                              label: "Total",
                              value: _formatCurrency(item['total']),
                            ),
                            if (_asDouble(item['returned_total']) > 0)
                              _BillSearchChip(
                                label: "Returned",
                                value: _formatCurrency(item['returned_total']),
                                valueColor: colorScheme.tertiary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                if (returns.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "Returns",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  ...returns.map((entry) {
                    final restocked = _asInt(entry['restocked']) == 1;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withAlpha(10),
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
                            "Qty ${_asInt(entry['units'])} | Refund ${_formatCurrency(entry['refund_amount'])}",
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${restocked ? 'Restocked' : 'Not restocked'} | ${entry['date']?.toString() ?? '--'}",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (entry['reason']?.toString().trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry['reason'].toString().trim(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDeleteSale(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Delete Sale"),
          content: Text(
            "Delete ${order['bill_number']?.toString().trim().isNotEmpty == true ? order['bill_number'].toString().trim() : 'this sale'}?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _handleSaleLongPress(Map<String, dynamic> order) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text("Show details"),
                onTap: () => Navigator.of(sheetContext).pop('details'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text("Share bill"),
                onTap: () => Navigator.of(sheetContext).pop('bill'),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: const Text("Record return"),
                onTap: () => Navigator.of(sheetContext).pop('return'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Edit sale"),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete sale"),
                textColor: Colors.red,
                iconColor: Colors.red,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'details':
        await _showOrderDetails(order);
        return;
      case 'bill':
        await _shareBill(order);
        return;
      case 'return':
        await _recordReturn(order);
        return;
      case 'edit':
        await _editSale(order);
        return;
      case 'delete':
        final confirmed = await _confirmDeleteSale(order);
        if (!confirmed) return;
        await _deleteOrder(order);
        return;
    }
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
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

  Widget _buildSearchPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Search Bills",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Find bills by product, customer, walk-in sales, bill number, or phone.",
                      ),
                    ],
                  ),
                ),
                if (_hasFilters)
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text("Clear"),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _searchHint(),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _hasSearchQuery
                    ? IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._BillSearchScope.values.map((scope) {
                  return ChoiceChip(
                    label: Text(_scopeLabel(scope)),
                    selected: _searchScope == scope,
                    onSelected: (_) {
                      setState(() {
                        _searchScope = scope;
                      });
                    },
                  );
                }),
                FilterChip(
                  label: const Text("Walk-in Only"),
                  selected: _walkInOnly,
                  onSelected: (selected) {
                    setState(() {
                      _walkInOnly = selected;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BillSearchChip(
                  label: "Visible",
                  value: "${_orders.length}",
                ),
                _BillSearchChip(
                  label: "All Bills",
                  value: "${_allOrders.length}",
                ),
              ],
            ),
            if (_isBusy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> order) {
    final profit = _asDouble(order['profit']);
    final orderDate = _parseOrderDate(order['date']?.toString());
    final colorScheme = Theme.of(context).colorScheme;
    final resultColor = profit < 0 ? colorScheme.error : colorScheme.secondary;
    final paymentColor = _paymentStatusColor(context, order['payment_status']);
    final dueAmount = _asDouble(order['due_amount']);
    final returnedTotal = _asDouble(order['returned_total']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showOrderDetails(order),
        onLongPress: () => _handleSaleLongPress(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['bill_number']?.toString().trim().isNotEmpty ==
                                  true
                              ? order['bill_number'].toString().trim()
                              : 'Sale #${order['id']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${_formatSectionDate(orderDate ?? DateTime.now())} | ${_formatTime(orderDate)}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _customerLabel(order),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(order['total']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${_resultLabel(profit)} ${_formatResultValue(profit)}",
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _productPreview(order),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BillSearchChip(
                    label: "Items",
                    value: "${_asInt(order['item_count'])}",
                  ),
                  _BillSearchChip(
                    label: "Units",
                    value: "${_asInt(order['total_units'])}",
                  ),
                  _BillSearchChip(
                    label: "Payment",
                    value: _paymentStatusLabel(order['payment_status']),
                    valueColor: paymentColor,
                  ),
                  if (returnedTotal > 0)
                    _BillSearchChip(
                      label: "Returned",
                      value: _formatCurrency(returnedTotal),
                      valueColor: colorScheme.tertiary,
                    ),
                  if (dueAmount > 0)
                    _BillSearchChip(
                      label: "Due",
                      value: _formatCurrency(dueAmount),
                      valueColor: colorScheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Tap for bill details. Long press for bill, return, edit, or delete.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_orders.isEmpty) {
      return Card(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _allOrders.isEmpty
                    ? "No bills have been recorded yet."
                    : "No bills matched the current search. Try a different product, customer name, or walk-in filter.",
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: _orders.map(_buildResultCard).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _allOrders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Bill Search")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Bill Search")),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildSearchPanel(),
            const SizedBox(height: 16),
            _buildResults(),
          ],
        ),
      ),
    );
  }
}

class _BillSearchChip extends StatelessWidget {
  const _BillSearchChip({
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
