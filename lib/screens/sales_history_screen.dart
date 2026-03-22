import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../services/sale_bill_service.dart';
import '../services/sales_export_service.dart';
import 'add_sale_screen.dart';

enum _CsvExportScope { customDates, pastMonth, everything }

enum _ExportAction { share, saveToLocal }

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> revenueData = [];
  DateTime? selectedDate;
  double todayRevenue = 0;
  double todayProfit = 0;
  int todaySales = 0;
  bool _isLoading = true;
  bool _isBusy = false;

  String _folderLabel(File file) => file.parent.path;

  @override
  void initState() {
    super.initState();
    loadOrders();
  }

  Map<String, String> _dateRange(DateTime date) {
    final day = DateFormat('yyyy-MM-dd').format(date);
    return {'start': "$day 00:00", 'end': "$day 23:59"};
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

  DateTime? _parseDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  String _formatSectionDate(DateTime date) {
    return DateFormat('EEE, d MMM yyyy').format(date);
  }

  String _formatShortDate(DateTime date) {
    return DateFormat('d MMM yyyy').format(date);
  }

  String _formatTime(DateTime? date) {
    if (date == null) return "--";
    return DateFormat('h:mm a').format(date);
  }

  String _activeFilterLabel() {
    if (selectedDate == null) return "All dates";
    return _formatShortDate(selectedDate!);
  }

  String _overviewSubtitle() {
    if (selectedDate == null) {
      return "Showing the complete order history";
    }
    return "Showing only orders from ${_formatSectionDate(selectedDate!)}";
  }

  Map<String, dynamic> _visibleSummary() {
    double revenue = 0;
    double profit = 0;
    for (final order in orders) {
      revenue += _asDouble(order['total']);
      profit += _asDouble(order['profit']);
    }

    return {'sales': orders.length, 'revenue': revenue, 'profit': profit};
  }

  List<Map<String, dynamic>> _chartSeries() {
    const maxPoints = 10;
    if (revenueData.length <= maxPoints) {
      return revenueData;
    }
    return revenueData.sublist(revenueData.length - maxPoints);
  }

  List<_OrderSection> _groupedOrders() {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final order in orders) {
      final date =
          _parseOrderDate(order['date']?.toString()) ?? DateTime(1970, 1, 1);
      final key = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(key, () => []).add(order);
    }

    return grouped.values.map((sectionOrders) {
      final firstDate =
          _parseOrderDate(sectionOrders.first['date']?.toString()) ??
          DateTime(1970, 1, 1);
      double revenue = 0;
      double profit = 0;

      for (final order in sectionOrders) {
        revenue += _asDouble(order['total']);
        profit += _asDouble(order['profit']);
      }

      return _OrderSection(
        date: firstDate,
        orders: sectionOrders,
        revenue: revenue,
        profit: profit,
      );
    }).toList();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> loadOrders({DateTime? filterDate}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final ordersFuture = filterDate == null
        ? DatabaseHelper.instance.getSaleOrders()
        : DatabaseHelper.instance.getSaleOrdersByDateRange(
            _dateRange(filterDate)['start']!,
            _dateRange(filterDate)['end']!,
          );
    final graphFuture = DatabaseHelper.instance.getDailyRevenue();
    final summaryFuture = DatabaseHelper.instance.getTodaySummary();

    final orderRows = await ordersFuture;
    final graph = await graphFuture;
    final summary = await summaryFuture;

    if (!mounted) return;

    setState(() {
      selectedDate = filterDate;
      orders = orderRows;
      revenueData = graph;
      todayRevenue = _asDouble(summary['total_revenue']);
      todayProfit = _asDouble(summary['total_profit']);
      todaySales = _asInt(summary['total_sales']);
      _isLoading = false;
    });
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;
    await loadOrders(filterDate: picked);
  }

  Future<void> clearDateFilter() async {
    await loadOrders();
  }

  Future<_CsvExportScope?> _pickExportScope() async {
    return showModalBottomSheet<_CsvExportScope>(
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
                leading: const Icon(Icons.date_range_outlined),
                title: const Text("Select Dates"),
                subtitle: const Text("Choose a custom start and end date"),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CsvExportScope.customDates),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text("Past Month"),
                subtitle: const Text("Export the last 30 days of orders"),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CsvExportScope.pastMonth),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text("Everything"),
                subtitle: const Text("Export all past order data"),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CsvExportScope.everything),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<DateTimeRange?> _pickExportDateRange() async {
    return showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 29)),
        end: DateTime.now(),
      ),
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
  }

  Future<_ExportAction?> _pickExportAction(String formatLabel) async {
    return showModalBottomSheet<_ExportAction>(
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
                leading: const Icon(Icons.share_outlined),
                title: Text("Share $formatLabel"),
                subtitle: const Text(
                  "Open the Android share menu and send the file to another app",
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ExportAction.share),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text("Save to Local"),
                subtitle: const Text(
                  "Save the file in Android/media/<app>/sale",
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ExportAction.saveToLocal),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_ExportSelection?> _pickExportSelection() async {
    final scope = await _pickExportScope();
    if (scope == null) return null;

    switch (scope) {
      case _CsvExportScope.customDates:
        final range = await _pickExportDateRange();
        if (range == null) return null;
        return _ExportSelection(
          exportLabel:
              "${DateFormat('yyyyMMdd').format(range.start)}_${DateFormat('yyyyMMdd').format(range.end)}",
          title:
              "Custom range: ${DateFormat('d MMM yyyy').format(range.start)} to ${DateFormat('d MMM yyyy').format(range.end)}",
          startDate: "${DateFormat('yyyy-MM-dd').format(range.start)} 00:00",
          endDate: "${DateFormat('yyyy-MM-dd').format(range.end)} 23:59",
        );
      case _CsvExportScope.pastMonth:
        final end = DateTime.now();
        final start = end.subtract(const Duration(days: 29));
        return _ExportSelection(
          exportLabel: "past_month",
          title: "Past Month",
          startDate: "${DateFormat('yyyy-MM-dd').format(start)} 00:00",
          endDate: "${DateFormat('yyyy-MM-dd').format(end)} 23:59",
        );
      case _CsvExportScope.everything:
        return const _ExportSelection(
          exportLabel: "all_data",
          title: "All Sales Data",
        );
    }
  }

  Future<void> exportToCSV() async {
    final selection = await _pickExportSelection();
    if (selection == null) return;
    final action = await _pickExportAction("CSV");
    if (action == null) return;

    final exportRows = selection.hasDateRange
        ? await DatabaseHelper.instance.getSaleItemsForExport(
            startDate: selection.startDate,
            endDate: selection.endDate,
          )
        : await DatabaseHelper.instance.getSaleItemsForExport();

    if (exportRows.isEmpty) {
      _showMessage("No sales found for the selected export range");
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final targetDirectory = action == _ExportAction.saveToLocal
          ? null
          : await SalesExportService.ensureShareDirectory();
      final file = await SalesExportService.saveCsvExport(
        rows: exportRows,
        exportLabel: selection.exportLabel,
        targetDirectory: targetDirectory,
      );

      if (action == _ExportAction.share) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: "Sales CSV Export"),
        );
      }

      if (!mounted) return;
      _showMessage(
        action == _ExportAction.share
            ? "Share sheet opened for CSV export"
            : "CSV saved to ${_folderLabel(file)}",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> exportToPDF() async {
    final selection = await _pickExportSelection();
    if (selection == null) return;
    final action = await _pickExportAction("PDF");
    if (action == null) return;

    final exportOrders = selection.hasDateRange
        ? await DatabaseHelper.instance.getSaleOrdersByDateRange(
            selection.startDate!,
            selection.endDate!,
          )
        : await DatabaseHelper.instance.getSaleOrders();

    if (exportOrders.isEmpty) {
      _showMessage("No sales found for the selected export range");
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final targetDirectory = action == _ExportAction.saveToLocal
          ? null
          : await SalesExportService.ensureShareDirectory();
      final file = await SalesExportService.savePdfExport(
        orders: exportOrders,
        exportLabel: selection.exportLabel,
        reportTitle: selection.title,
        targetDirectory: targetDirectory,
      );

      if (action == _ExportAction.share) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: "Sales PDF Export"),
        );
      }

      if (!mounted) return;
      _showMessage(
        action == _ExportAction.share
            ? "Share sheet opened for PDF export"
            : "PDF saved to ${_folderLabel(file)}",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> backupDatabase() async {
    setState(() {
      _isBusy = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          "sales_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db";
      final backupPath = "${directory.path}/$fileName";

      final backupFile = await DatabaseHelper.instance.createBackup(backupPath);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupFile.path)],
          text: "Sales Database Backup",
        ),
      );

      if (!mounted) return;
      _showMessage("Backup created and ready to share");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> restoreDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null) return;

    final selectedPath = result.files.single.path;
    if (selectedPath == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await DatabaseHelper.instance.restoreDatabaseFromFile(selectedPath);
      await loadOrders(filterDate: selectedDate);
      if (!mounted) return;
      _showMessage("Backup restored and history refreshed");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrderItems(
    Map<String, dynamic> order,
  ) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    return DatabaseHelper.instance.getSaleItemsForGroupKey(groupKey);
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

  Future<void> deleteOrder(Map<String, dynamic> order) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    await DatabaseHelper.instance.deleteSaleOrder(groupKey);
    if (!mounted) return;

    await loadOrders(filterDate: selectedDate);
    if (!mounted) return;

    _showMessage("Sale deleted");
  }

  Future<void> _editSale(Map<String, dynamic> order) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddSaleScreen(existingSale: order)),
    );
    if (!mounted || updated != true) return;

    await loadOrders(filterDate: selectedDate);
    if (!mounted) return;
    _showMessage("Sale updated");
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final items = await _loadOrderItems(order);
    if (!mounted) return;

    final profit = _asDouble(order['profit']);
    final colorScheme = Theme.of(context).colorScheme;

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
                _buildDetailRow(
                  "Customer",
                  order['customer_name']?.toString().trim().isNotEmpty == true
                      ? order['customer_name'].toString().trim()
                      : 'Walk-in Customer',
                ),
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
                            _OrderChip(
                              label: "Qty",
                              value: "${_asInt(item['units'])}",
                            ),
                            _OrderChip(
                              label: "SP",
                              value: _formatCurrency(item['selling_price']),
                            ),
                            _OrderChip(
                              label: "Discount",
                              value: _formatCurrency(item['discount']),
                            ),
                            _OrderChip(
                              label: "Total",
                              value: _formatCurrency(item['total']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
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
      case 'edit':
        await _editSale(order);
        return;
      case 'delete':
        final confirmed = await _confirmDeleteSale(order);
        if (!confirmed) return;
        await deleteOrder(order);
        return;
    }
  }

  Widget _buildPanel({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
    );

    return filled
        ? ElevatedButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
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

  Widget _buildIntroCard() {
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
                color: colorScheme.primary.withAlpha(22),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.history_rounded, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Sales History",
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Review full orders, customers, export records, and share bills.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondary.withAlpha(18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _activeFilterLabel(),
                style: TextStyle(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsPanel() {
    return _buildPanel(
      title: "History Tools",
      subtitle:
          "Filter the view, share exports, save them locally in Android/media/<app>/sale, or create and restore backups",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildToolButton(
                onPressed: pickDate,
                icon: Icons.calendar_month_outlined,
                label: "Filter by Date",
                filled: true,
              ),
              if (selectedDate != null)
                _buildToolButton(
                  onPressed: clearDateFilter,
                  icon: Icons.filter_alt_off_outlined,
                  label: "Clear Filter",
                ),
              _buildToolButton(
                onPressed: exportToCSV,
                icon: Icons.ios_share_outlined,
                label: "Export CSV",
              ),
              _buildToolButton(
                onPressed: exportToPDF,
                icon: Icons.picture_as_pdf_outlined,
                label: "Export PDF",
              ),
              _buildToolButton(
                onPressed: backupDatabase,
                icon: Icons.backup_outlined,
                label: "Backup",
              ),
              _buildToolButton(
                onPressed: restoreDatabase,
                icon: Icons.restore_rounded,
                label: "Restore",
              ),
            ],
          ),
          if (_isLoading || _isBusy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewPanel() {
    final summary = _visibleSummary();
    final visibleProfit = _asDouble(summary['profit']);

    return _buildPanel(
      title: "Overview",
      subtitle: _overviewSubtitle(),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 154,
        ),
        children: [
          _buildMetricCard(
            label: "Visible Orders",
            value: "${summary['sales']}",
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF5F95FF),
          ),
          _buildMetricCard(
            label: "Visible Revenue",
            value: _formatCurrency(summary['revenue']),
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF57D77F),
          ),
          _buildMetricCard(
            label: "Visible ${_resultLabel(visibleProfit)}",
            value: _formatResultValue(visibleProfit),
            icon: Icons.account_balance_wallet_outlined,
            color: visibleProfit < 0
                ? Theme.of(context).colorScheme.error
                : const Color(0xFFB785FF),
          ),
          _buildMetricCard(
            label: "Today's Orders",
            value: "$todaySales",
            icon: Icons.today_outlined,
            color: const Color(0xFFFFB43A),
            caption: "Revenue ${_formatCurrency(todayRevenue)}",
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    final chartPoints = _chartSeries();
    if (chartPoints.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            "No revenue data yet",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final maxY = chartPoints
        .map((point) => _asDouble(point['revenue']))
        .fold<double>(
          0,
          (previous, element) => element > previous ? element : previous,
        );
    final effectiveMax = maxY <= 0 ? 10.0 : maxY * 1.2;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: effectiveMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: effectiveMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colorScheme.outline.withAlpha(40),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: effectiveMax / 4,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value == value.roundToDouble()
                        ? value.toStringAsFixed(0)
                        : value.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= chartPoints.length) {
                    return const SizedBox.shrink();
                  }

                  final date = _parseDay(chartPoints[index]['day']?.toString());
                  final label = date == null
                      ? chartPoints[index]['day']?.toString() ?? '--'
                      : DateFormat('M/d').format(date);

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: chartPoints.asMap().entries.map((entry) {
                return FlSpot(
                  entry.key.toDouble(),
                  _asDouble(entry.value['revenue']),
                );
              }).toList(),
              isCurved: true,
              barWidth: 4,
              color: colorScheme.primary,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.primary.withAlpha(84),
                    colorScheme.primary.withAlpha(0),
                  ],
                ),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: colorScheme.surface,
                    strokeWidth: 2,
                    strokeColor: colorScheme.primary,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartPanel() {
    return _buildPanel(
      title: "Revenue Trend",
      subtitle: "Latest order days in your local history",
      child: _buildRevenueChart(),
    );
  }

  Widget _buildSectionHeader(_OrderSection section) {
    final profitLabel = _resultLabel(section.profit);
    final colorScheme = Theme.of(context).colorScheme;
    final resultColor = section.profit < 0
        ? colorScheme.error
        : colorScheme.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatSectionDate(section.date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: resultColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "$profitLabel ${_formatResultValue(section.profit)}",
                  style: TextStyle(
                    color: resultColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OrderChip(label: "Orders", value: "${section.orders.length}"),
              _OrderChip(
                label: "Revenue",
                value: _formatCurrency(section.revenue),
              ),
            ],
          ),
        ],
      ),
    );
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
      return parts.join(' • ');
    }
    return "${parts.take(2).join(' • ')} +${parts.length - 2} more";
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final profit = _asDouble(order['profit']);
    final orderDate = _parseOrderDate(order['date']?.toString());
    final colorScheme = Theme.of(context).colorScheme;
    final resultColor = profit < 0 ? colorScheme.error : colorScheme.secondary;
    final paymentColor = _paymentStatusColor(context, order['payment_status']);
    final dueAmount = _asDouble(order['due_amount']);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withAlpha(40)),
      ),
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
                          "${_formatTime(orderDate)} • ${order['customer_name']?.toString().trim().isNotEmpty == true ? order['customer_name'].toString().trim() : 'Walk-in Customer'}",
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
                  _OrderChip(
                    label: "Items",
                    value: "${_asInt(order['item_count'])}",
                  ),
                  _OrderChip(
                    label: "Units",
                    value: "${_asInt(order['total_units'])}",
                  ),
                  _OrderChip(
                    label: "Payment",
                    value: _paymentStatusLabel(order['payment_status']),
                    valueColor: paymentColor,
                  ),
                  if (dueAmount > 0)
                    _OrderChip(
                      label: "Due",
                      value: _formatCurrency(dueAmount),
                      valueColor: colorScheme.error,
                    ),
                  if (order['customer_phone']?.toString().trim().isNotEmpty ==
                      true)
                    _OrderChip(
                      label: "Phone",
                      value: order['customer_phone'].toString().trim(),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Tap for details. Long press for bill, edit, or delete.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersTimeline() {
    final sections = _groupedOrders();

    if (sections.isEmpty) {
      return _buildPanel(
        title: "Orders Timeline",
        subtitle: selectedDate == null
            ? "No sales have been recorded yet"
            : "No sales found for ${_formatSectionDate(selectedDate!)}",
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              selectedDate == null
                  ? "No orders yet"
                  : "No sales on the selected date",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return _buildPanel(
      title: "Orders Timeline",
      subtitle:
          "Tap an order for details. Long press to share bill, edit, or delete",
      child: Column(
        children: sections.map((section) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                _buildSectionHeader(section),
                ...section.orders.map(_buildOrderCard),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && orders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Sales History")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Sales History")),
      body: RefreshIndicator(
        onRefresh: () => loadOrders(filterDate: selectedDate),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildIntroCard(),
            const SizedBox(height: 16),
            _buildToolsPanel(),
            const SizedBox(height: 16),
            _buildOverviewPanel(),
            const SizedBox(height: 16),
            _buildChartPanel(),
            const SizedBox(height: 16),
            _buildOrdersTimeline(),
          ],
        ),
      ),
    );
  }
}

class _OrderSection {
  const _OrderSection({
    required this.date,
    required this.orders,
    required this.revenue,
    required this.profit,
  });

  final DateTime date;
  final List<Map<String, dynamic>> orders;
  final double revenue;
  final double profit;
}

class _ExportSelection {
  const _ExportSelection({
    required this.exportLabel,
    required this.title,
    this.startDate,
    this.endDate,
  });

  final String exportLabel;
  final String title;
  final String? startDate;
  final String? endDate;

  bool get hasDateRange => startDate != null && endDate != null;
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({required this.label, required this.value, this.valueColor});

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
