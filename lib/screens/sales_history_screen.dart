import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../services/sale_bill_service.dart';
import '../services/sales_export_service.dart';
import 'add_sale_screen.dart';
import 'bill_search_screen.dart';
import 'record_return_screen.dart';

enum _CsvExportScope { customDates, pastMonth, everything }

enum _ExportAction { share, saveToLocal }

enum _HistorySearchScope { all, product, customer }

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allOrders = [];
  DateTime? selectedDate;
  double todayRevenue = 0;
  double todayProfit = 0;
  int todaySales = 0;
  bool _isLoading = true;
  bool _isBusy = false;
  bool _walkInOnly = false;
  _HistorySearchScope _searchScope = _HistorySearchScope.all;

  String _folderLabel(File file) => file.parent.path;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    loadOrders();
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
    final finderLabel = _finderStatusLabel();
    if (selectedDate == null) {
      return finderLabel == null
          ? "Showing the complete order history"
          : "Showing the complete order history • $finderLabel";
    }
    return finderLabel == null
        ? "Showing only orders from ${_formatSectionDate(selectedDate!)}"
        : "Showing only orders from ${_formatSectionDate(selectedDate!)} • $finderLabel";
  }

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  bool get _hasFinderFilters =>
      _hasSearchQuery ||
      _walkInOnly ||
      _searchScope != _HistorySearchScope.all;

  List<Map<String, dynamic>> get orders => _filteredOrders();

  bool _hasReturns(Map<String, dynamic> order) =>
      _asDouble(order['returned_total']) > 0 ||
      _asInt(order['return_count']) > 0;

  String _normalized(String value) => value.trim().toLowerCase();

  String _customerLabel(Map<String, dynamic> order) {
    final name = order['customer_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Walk-in Customer' : name;
  }

  bool _isWalkInOrder(Map<String, dynamic> order) {
    final customerId = _asInt(order['customer_id']);
    final customerName = order['customer_name']?.toString().trim() ?? '';
    final phone = order['customer_phone']?.toString().trim() ?? '';
    return customerId <= 0 &&
        phone.isEmpty &&
        (customerName.isEmpty ||
            _normalized(customerName) == 'walk-in customer');
  }

  List<Map<String, dynamic>> _filteredOrders() {
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
        case _HistorySearchScope.product:
          return _normalized(productNames).contains(query);
        case _HistorySearchScope.customer:
          return _normalized(customerName).contains(query) ||
              _normalized(customerPhone).contains(query);
        case _HistorySearchScope.all:
          return [
            billNumber,
            productNames,
            customerName,
            customerPhone,
          ].any((value) => _normalized(value).contains(query));
      }
    }).toList();
  }

  String? _finderStatusLabel() {
    if (!_hasFinderFilters) return null;

    final parts = <String>[];
    if (_hasSearchQuery) {
      parts.add("${orders.length} matches");
    }
    if (_walkInOnly) {
      parts.add("walk-in only");
    }
    if (_searchScope != _HistorySearchScope.all) {
      parts.add("${_searchScopeLabel(_searchScope)} search");
    }

    return parts.isEmpty ? null : parts.join(" • ");
  }

  String _finderSubtitle() {
    if (_allOrders.isEmpty) {
      return "Search past bills by sold product, customer name, or walk-in sales.";
    }

    final baseLabel = selectedDate == null
        ? "${_allOrders.length} bills across all dates"
        : "${_allOrders.length} bills on ${_formatShortDate(selectedDate!)}";

    if (!_hasFinderFilters) {
      return "Search past bills by sold product, customer name, or walk-in sales. $baseLabel.";
    }

    return "Showing ${orders.length} matching bills from $baseLabel.";
  }

  String _searchHint() {
    switch (_searchScope) {
      case _HistorySearchScope.product:
        return "Search by sold product name";
      case _HistorySearchScope.customer:
        return "Search by customer name or phone";
      case _HistorySearchScope.all:
        return "Search bill no, product, customer, or phone";
    }
  }

  String _searchScopeLabel(_HistorySearchScope scope) {
    switch (scope) {
      case _HistorySearchScope.product:
        return "Product";
      case _HistorySearchScope.customer:
        return "Customer";
      case _HistorySearchScope.all:
        return "All";
    }
  }

  void _clearFinderFilters() {
    _searchController.clear();
    if (!mounted) return;

    setState(() {
      _walkInOnly = false;
      _searchScope = _HistorySearchScope.all;
    });
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
    final revenueByDay = <String, double>{};

    for (final order in orders) {
      final date = _parseOrderDate(order['date']?.toString());
      if (date == null) continue;

      final dayKey = DateFormat('yyyy-MM-dd').format(date);
      revenueByDay[dayKey] =
          (revenueByDay[dayKey] ?? 0) + _asDouble(order['total']);
    }

    final series = revenueByDay.entries
        .map<Map<String, dynamic>>((entry) => <String, dynamic>{
              'day': entry.key,
              'revenue': entry.value,
            })
        .toList()
      ..sort(
        (a, b) => (a['day'] as String).compareTo(b['day'] as String),
      );

    const maxPoints = 14;
    if (series.length <= maxPoints) {
      return series;
    }
    return series.sublist(series.length - maxPoints);
  }

  double _averageChartRevenue(List<Map<String, dynamic>> chartPoints) {
    if (chartPoints.isEmpty) return 0;

    final total = chartPoints.fold<double>(
      0,
      (sum, point) => sum + _asDouble(point['revenue']),
    );
    return total / chartPoints.length;
  }

  Map<String, dynamic>? _bestRevenueDay(List<Map<String, dynamic>> chartPoints) {
    if (chartPoints.isEmpty) return null;

    var best = chartPoints.first;
    for (final current in chartPoints.skip(1)) {
      if (_asDouble(current['revenue']) > _asDouble(best['revenue'])) {
        best = current;
      }
    }
    return best;
  }

  String _formatCompactAmount(double value) {
    if (value >= 1000) {
      return NumberFormat.compact(locale: 'en_IN').format(value);
    }

    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  String _chartTrendLabel(List<Map<String, dynamic>> chartPoints) {
    if (chartPoints.length < 2) {
      return "Single day in view";
    }

    final first = _asDouble(chartPoints.first['revenue']);
    final last = _asDouble(chartPoints.last['revenue']);
    final difference = last - first;

    if (difference.abs() < 0.01) {
      return "Flat vs first day";
    }

    final direction = difference > 0 ? "Up" : "Down";
    return "$direction ${_formatCurrency(difference.abs())}";
  }

  Color _chartTrendColor(
    BuildContext context,
    List<Map<String, dynamic>> chartPoints,
  ) {
    if (chartPoints.length < 2) {
      return Theme.of(context).colorScheme.primary;
    }

    final first = _asDouble(chartPoints.first['revenue']);
    final last = _asDouble(chartPoints.last['revenue']);
    if ((last - first).abs() < 0.01) {
      return Theme.of(context).colorScheme.primary;
    }

    return last >= first
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.error;
  }

  String _chartSubtitle(List<Map<String, dynamic>> chartPoints) {
    if (chartPoints.isEmpty) {
      return _hasFinderFilters
          ? "No matching revenue days for the current bill search"
          : "Revenue appears here after sales are recorded";
    }

    final start = _parseDay(chartPoints.first['day']?.toString());
    final end = _parseDay(chartPoints.last['day']?.toString());
    final rangeLabel = start == null || end == null
        ? "${chartPoints.length} recent revenue days"
        : start == end
        ? _formatSectionDate(start)
        : "${_formatShortDate(start)} to ${_formatShortDate(end)}";

    return _hasFinderFilters
        ? "$rangeLabel • ${orders.length} matching bills"
        : rangeLabel;
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
    final summaryFuture = DatabaseHelper.instance.getTodaySummary();

    final orderRows = await ordersFuture;
    final summary = await summaryFuture;

    if (!mounted) return;

    setState(() {
      selectedDate = filterDate;
      _allOrders = orderRows;
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

  Future<void> _openBillSearch() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BillSearchScreen()));
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
    final action = await _pickExportAction("Backup");
    if (action == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final directory = action == _ExportAction.saveToLocal
          ? await SalesExportService.ensureLocalSaleDirectory()
          : await SalesExportService.ensureShareDirectory();
      final fileName =
          "sales_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db";
      final backupPath = "${directory.path}/$fileName";

      final backupFile = await DatabaseHelper.instance.createBackup(backupPath);

      if (action == _ExportAction.share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(backupFile.path)],
            text: "Sales Database Backup",
          ),
        );
      }

      if (!mounted) return;
      _showMessage(
        action == _ExportAction.share
            ? "Share sheet opened for backup"
            : "Backup saved to ${_folderLabel(backupFile)}",
      );
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
      dialogTitle: "Select backup database",
      type: FileType.custom,
      allowedExtensions: ['db'],
      allowMultiple: false,
    );
    if (result == null) return;

    final selectedPath = result.files.single.path;
    if (selectedPath == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await DatabaseHelper.instance.restoreDatabaseFromFile(selectedPath);
      await loadOrders();
      if (!mounted) return;
      _showMessage("Backup restored and history refreshed");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
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

  Future<void> deleteOrder(Map<String, dynamic> order) async {
    final groupKey = order['group_key']?.toString() ?? 'legacy-${order['id']}';
    try {
      await DatabaseHelper.instance.deleteSaleOrder(groupKey);
      if (!mounted) return;

      await loadOrders(filterDate: selectedDate);
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

    await loadOrders(filterDate: selectedDate);
    if (!mounted) return;
    _showMessage("Sale updated");
  }

  Future<void> _recordReturn(Map<String, dynamic> order) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordReturnScreen(order: order)),
    );
    if (!mounted || recorded != true) return;

    await loadOrders(filterDate: selectedDate);
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
                if (_hasReturns(order)) ...[
                  _buildDetailRow(
                    "Gross Total",
                    _formatCurrency(order['gross_total']),
                  ),
                  _buildDetailRow(
                    "Returned",
                    "${_formatCurrency(returnedTotal)} • $returnedUnits unit(s)",
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
                            _OrderChip(
                              label: "Qty",
                              value: "${_asInt(item['net_units'])}",
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
                            if (_asDouble(item['returned_total']) > 0)
                              _OrderChip(
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
                            "Qty ${_asInt(entry['units'])} • Refund ${_formatCurrency(entry['refund_amount'])}",
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${restocked ? 'Restocked' : 'Not restocked'} • ${entry['date']?.toString() ?? '--'}",
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
                onPressed: _openBillSearch,
                icon: Icons.manage_search_rounded,
                label: "Search Bills",
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

  Widget _buildSearchPanel() {
    return _buildPanel(
      title: "Find Bills",
      subtitle: _finderSubtitle(),
      trailing: _hasFinderFilters
          ? TextButton(
              onPressed: _clearFinderFilters,
              child: const Text("Clear"),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              ..._HistorySearchScope.values.map((scope) {
                return ChoiceChip(
                  label: Text(_searchScopeLabel(scope)),
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
          const SizedBox(height: 10),
          Text(
            _walkInOnly
                ? "Showing only bills that were saved without a customer name."
                : "Search can match bill numbers, sold products, customer names, and phone numbers.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
            caption:
                "Revenue ${_formatCurrency(todayRevenue)} • ${_resultLabel(todayProfit)} ${_formatResultValue(todayProfit)}",
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
    final averageRevenue = _averageChartRevenue(chartPoints);
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
          minX: 0,
          maxX: chartPoints.length == 1 ? 1 : (chartPoints.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: effectiveMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colorScheme.outline.withAlpha(40),
              strokeWidth: 1,
            ),
          ),
          extraLinesData: averageRevenue <= 0
              ? const ExtraLinesData()
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: averageRevenue,
                      color: colorScheme.secondary.withAlpha(150),
                      strokeWidth: 1.6,
                      dashArray: const [6, 6],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 6, bottom: 2),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                        labelResolver: (_) =>
                            "Avg ${_formatCompactAmount(averageRevenue)}",
                      ),
                    ),
                  ],
                ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipBorderRadius: BorderRadius.circular(16),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              tooltipBorder: BorderSide(
                color: colorScheme.outline.withAlpha(60),
              ),
              getTooltipColor: (_) => colorScheme.surface,
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final index = spot.x.toInt();
                  if (index < 0 || index >= chartPoints.length) {
                    return null;
                  }

                  final point = chartPoints[index];
                  final date = _parseDay(point['day']?.toString());
                  final label = date == null
                      ? point['day']?.toString() ?? '--'
                      : _formatSectionDate(date);

                  return LineTooltipItem(
                    "$label\n",
                    TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(
                        text: _formatCurrency(point['revenue']),
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
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
                    _formatCompactAmount(value),
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
                  if (chartPoints.length > 8 &&
                      index.isOdd &&
                      index != chartPoints.length - 1) {
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
              isStrokeCapRound: true,
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
    final chartPoints = _chartSeries();
    final averageRevenue = _averageChartRevenue(chartPoints);
    final bestDay = _bestRevenueDay(chartPoints);
    final bestDayDate = _parseDay(bestDay?['day']?.toString());
    final trendColor = _chartTrendColor(context, chartPoints);

    return _buildPanel(
      title: "Revenue Trend",
      subtitle: _chartSubtitle(chartPoints),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chartPoints.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OrderChip(
                  label: "Days",
                  value: "${chartPoints.length}",
                ),
                _OrderChip(
                  label: "Avg / Day",
                  value: _formatCurrency(averageRevenue),
                ),
                if (bestDay != null)
                  _OrderChip(
                    label: "Best Day",
                    value:
                        "${_formatCurrency(bestDay['revenue'])}${bestDayDate == null ? '' : ' on ${_formatShortDate(bestDayDate)}'}",
                    valueColor: Theme.of(context).colorScheme.secondary,
                  ),
                _OrderChip(
                  label: "Trend",
                  value: _chartTrendLabel(chartPoints),
                  valueColor: trendColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _buildRevenueChart(),
        ],
      ),
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
    final returnedTotal = _asDouble(order['returned_total']);

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
                          "${_formatTime(orderDate)} • ${_customerLabel(order)}",
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
                  if (returnedTotal > 0)
                    _OrderChip(
                      label: "Returned",
                      value: _formatCurrency(returnedTotal),
                      valueColor: colorScheme.tertiary,
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
                "Tap for details. Long press for bill, return, edit, or delete.",
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
      final hasBaseOrders = _allOrders.isNotEmpty;
      return _buildPanel(
        title: "Orders Timeline",
        subtitle: hasBaseOrders && _hasFinderFilters
            ? "No bills matched the current search or walk-in filter"
            : selectedDate == null
            ? "No sales have been recorded yet"
            : "No sales found for ${_formatSectionDate(selectedDate!)}",
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              hasBaseOrders && _hasFinderFilters
                  ? "Try a different product, customer name, or walk-in filter"
                  : selectedDate == null
                  ? "No orders yet"
                  : "No sales on the selected date",
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return _buildPanel(
      title: "Orders Timeline",
      subtitle:
          "Tap an order for details. Long press to share bill, return, edit, or delete",
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
    if (_isLoading && _allOrders.isEmpty) {
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
            _buildSearchPanel(),
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
