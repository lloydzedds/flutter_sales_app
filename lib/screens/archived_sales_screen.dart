import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../services/sale_bill_service.dart';
import 'record_return_screen.dart';

class ArchivedSalesScreen extends StatefulWidget {
  const ArchivedSalesScreen({super.key});

  @override
  State<ArchivedSalesScreen> createState() => _ArchivedSalesScreenState();
}

class _ArchivedSalesScreenState extends State<ArchivedSalesScreen> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _months = [];
  List<Map<String, dynamic>> _orders = [];
  String? _selectedMonth;
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadArchive();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadArchive({String? month}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final months = await DatabaseHelper.instance.getArchivedMonthSummaries();
    final selectedMonth = month ?? _selectedMonth ?? _firstArchiveMonth(months);
    final orders = selectedMonth == null
        ? const <Map<String, dynamic>>[]
        : await DatabaseHelper.instance.getArchivedSaleOrders(
            archiveMonth: selectedMonth,
          );

    if (!mounted) return;
    setState(() {
      _months = months;
      _selectedMonth = selectedMonth;
      _orders = orders;
      _isLoading = false;
    });
  }

  String? _firstArchiveMonth(List<Map<String, dynamic>> months) {
    if (months.isEmpty) return null;
    return months.first['archive_month']?.toString();
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

  String _formatCurrency(dynamic value) => "Rs ${_formatAmount(value)}";

  String _formatResultValue(double value) => _formatCurrency(value.abs());

  String _resultLabel(double value) => value < 0 ? "Loss" : "Profit";

  String _normalized(String value) => value.trim().toLowerCase();

  DateTime? _parseOrderDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parseStrict(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  String _monthLabel(String month) {
    try {
      return DateFormat('MMMM yyyy').format(DateFormat('yyyy-MM').parse(month));
    } catch (_) {
      return month;
    }
  }

  String _formatDateTime(String? raw) {
    final date = _parseOrderDate(raw);
    if (date == null) return raw ?? '--';
    return DateFormat('d MMM yyyy, h:mm a').format(date);
  }

  String _customerLabel(Map<String, dynamic> order) {
    final name = order['customer_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Walk-in Customer' : name;
  }

  String _billLabel(Map<String, dynamic> order) {
    final bill = order['bill_number']?.toString().trim() ?? '';
    return bill.isEmpty ? 'Sale #${order['id']}' : bill;
  }

  String _productPreview(Map<String, dynamic> order) {
    final raw = order['product_names']?.toString() ?? '';
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Products not available';
    if (parts.length <= 2) return parts.join(' | ');
    return "${parts.take(2).join(' | ')} +${parts.length - 2} more";
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final query = _normalized(_searchController.text);
    if (query.isEmpty) return _orders;

    return _orders.where((order) {
      final billNumber = order['bill_number']?.toString() ?? '';
      final productNames = order['product_names']?.toString() ?? '';
      final customerName = _customerLabel(order);
      final customerPhone = order['customer_phone']?.toString() ?? '';
      return [
        billNumber,
        productNames,
        customerName,
        customerPhone,
      ].any((value) => _normalized(value).contains(query));
    }).toList();
  }

  Map<String, dynamic>? get _selectedSummary {
    final selected = _selectedMonth;
    if (selected == null) return null;
    for (final month in _months) {
      if (month['archive_month']?.toString() == selected) {
        return month;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _recordReturn(Map<String, dynamic> order) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordReturnScreen(order: order)),
    );
    if (!mounted || recorded != true) return;

    await _loadArchive(month: _selectedMonth);
    if (!mounted) return;
    _showMessage("Return recorded for archived bill");
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final items = await _loadOrderItems(order);
    final returns = await _loadReturnRows(order);
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final profit = _asDouble(order['profit']);

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
                  _billLabel(order),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDateTime(order['date']?.toString()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                _DetailRow(label: "Customer", value: _customerLabel(order)),
                if (order['customer_phone']?.toString().trim().isNotEmpty ==
                    true)
                  _DetailRow(
                    label: "Phone",
                    value: order['customer_phone'].toString(),
                  ),
                _DetailRow(
                  label: "Products",
                  value: "${_asInt(order['item_count'])} item(s)",
                ),
                _DetailRow(
                  label: "Units",
                  value: "${_asInt(order['total_units'])} units",
                ),
                _DetailRow(
                  label: "Total",
                  value: _formatCurrency(order['total']),
                ),
                _DetailRow(
                  label: _resultLabel(profit),
                  value: _formatResultValue(profit),
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
                  return _ArchivedLineCard(
                    title:
                        item['product_name']?.toString() ??
                        item['name']?.toString() ??
                        'Product',
                    chips: [
                      _ArchiveChipData("Qty", "${_asInt(item['net_units'])}"),
                      _ArchiveChipData(
                        "SP",
                        _formatCurrency(item['selling_price']),
                      ),
                      _ArchiveChipData(
                        "Discount",
                        _formatCurrency(item['discount']),
                      ),
                      _ArchiveChipData("Total", _formatCurrency(item['total'])),
                    ],
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
                    return _ArchivedLineCard(
                      tone: colorScheme.error,
                      title: entry['product_name']?.toString() ?? 'Product',
                      subtitle:
                          "${entry['date']?.toString() ?? '--'} | ${entry['reason']?.toString() ?? 'No reason added'}",
                      chips: [
                        _ArchiveChipData("Qty", "${_asInt(entry['units'])}"),
                        _ArchiveChipData(
                          "Refund",
                          _formatCurrency(entry['refund_amount']),
                        ),
                      ],
                    );
                  }),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _recordReturn(order);
                    },
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text("Record Return"),
                  ),
                ),
                const SizedBox(height: 10),
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

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.inventory_2_outlined,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Archived Bills",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Month-end records stay available for search and bill sharing.",
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

  Widget _buildMonthPicker() {
    final summary = _selectedSummary;
    final profit = _asDouble(summary?['profit']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedMonth,
              decoration: const InputDecoration(labelText: "Archive month"),
              items: _months.map((month) {
                final value = month['archive_month']?.toString() ?? '';
                return DropdownMenuItem(
                  value: value,
                  child: Text(_monthLabel(value)),
                );
              }).toList(),
              onChanged: _isLoading || _isBusy
                  ? null
                  : (value) {
                      if (value == null) return;
                      _searchController.clear();
                      _loadArchive(month: value);
                    },
            ),
            if (summary != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryPill(
                    icon: Icons.receipt_long_outlined,
                    label: "Bills",
                    value: "${_asInt(summary['orders_count'])}",
                  ),
                  _SummaryPill(
                    icon: Icons.trending_up_outlined,
                    label: "Revenue",
                    value: _formatCurrency(summary['total']),
                  ),
                  _SummaryPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _resultLabel(profit),
                    value: _formatResultValue(profit),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: "Search bill, product, customer, or phone",
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final profit = _asDouble(order['profit']);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
                      _billLabel(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isBusy ? null : () => _shareBill(order),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: "Share bill",
                  ),
                  IconButton(
                    onPressed: _isBusy ? null : () => _recordReturn(order),
                    icon: const Icon(Icons.assignment_return_outlined),
                    tooltip: "Record return",
                  ),
                ],
              ),
              Text(
                _formatDateTime(order['date']?.toString()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(
                _customerLabel(order),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _productPreview(order),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryPill(
                    icon: Icons.payments_outlined,
                    label: "Total",
                    value: _formatCurrency(order['total']),
                  ),
                  _SummaryPill(
                    icon: Icons.inventory_2_outlined,
                    label: "Items",
                    value: "${_asInt(order['item_count'])}",
                  ),
                  _SummaryPill(
                    icon: Icons.insights_outlined,
                    label: _resultLabel(profit),
                    value: _formatResultValue(profit),
                    color: profit < 0 ? colorScheme.error : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 42),
            const SizedBox(height: 12),
            Text(
              _months.isEmpty
                  ? "No archived bills yet"
                  : "No bills matched your search",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _months.isEmpty
                  ? "Previous-month sales will appear here after the app opens in a new month."
                  : "Try another bill number, product, customer, or phone.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _filteredOrders;

    return Scaffold(
      appBar: AppBar(title: const Text("Archived Bills")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          if (_months.isNotEmpty) ...[_buildMonthPicker(), _buildSearchCard()],
          if (_isLoading || _isBusy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          if (!_isLoading && filteredOrders.isEmpty)
            _buildEmptyState()
          else
            ...filteredOrders.map(_buildOrderCard),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withAlpha(16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(
            "$label: $value",
            style: TextStyle(color: tone, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveChipData {
  const _ArchiveChipData(this.label, this.value);

  final String label;
  final String value;
}

class _ArchivedLineCard extends StatelessWidget {
  const _ArchivedLineCard({
    required this.title,
    required this.chips,
    this.subtitle,
    this.tone,
  });

  final String title;
  final String? subtitle;
  final List<_ArchiveChipData> chips;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((chip) {
              return Chip(
                label: Text("${chip.label}: ${chip.value}"),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
