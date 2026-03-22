import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import 'add_sale_screen.dart';

enum _CsvExportScope { customDates, pastMonth, everything }

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> revenueData = [];
  DateTime? selectedDate;
  double todayRevenue = 0;
  double todayProfit = 0;
  int todaySales = 0;
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    loadSales();
  }

  Map<String, String> _dateRange(DateTime date) {
    final day = DateFormat('yyyy-MM-dd').format(date);
    return {'start': "$day 00:00", 'end': "$day 23:59"};
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
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

  DateTime? _parseSaleDate(String? raw) {
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
    if (selectedDate == null) {
      return "All dates";
    }
    return _formatShortDate(selectedDate!);
  }

  String _overviewSubtitle() {
    if (selectedDate == null) {
      return "Showing the complete sales history";
    }
    return "Showing only sales from ${_formatSectionDate(selectedDate!)}";
  }

  Map<String, dynamic> _visibleSummary() {
    double revenue = 0;
    double profit = 0;

    for (final sale in sales) {
      revenue += _asDouble(sale['total']);
      profit += _asDouble(sale['profit']);
    }

    return {'sales': sales.length, 'revenue': revenue, 'profit': profit};
  }

  List<Map<String, dynamic>> _chartSeries() {
    const maxPoints = 10;
    if (revenueData.length <= maxPoints) {
      return revenueData;
    }
    return revenueData.sublist(revenueData.length - maxPoints);
  }

  List<_SalesSection> _groupedSales() {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final sale in sales) {
      final date =
          _parseSaleDate(sale['date']?.toString()) ?? DateTime(1970, 1, 1);
      final key = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(key, () => []).add(sale);
    }

    return grouped.values.map((sectionSales) {
      final firstDate =
          _parseSaleDate(sectionSales.first['date']?.toString()) ??
          DateTime(1970, 1, 1);
      double revenue = 0;
      double profit = 0;

      for (final sale in sectionSales) {
        revenue += _asDouble(sale['total']);
        profit += _asDouble(sale['profit']);
      }

      return _SalesSection(
        date: firstDate,
        sales: sectionSales,
        revenue: revenue,
        profit: profit,
      );
    }).toList();
  }

  String _csvCell(dynamic value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> loadSales({DateTime? filterDate}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final salesFuture = filterDate == null
        ? DatabaseHelper.instance.getSalesWithProduct()
        : DatabaseHelper.instance.getSalesByDateRange(
            _dateRange(filterDate)['start']!,
            _dateRange(filterDate)['end']!,
          );
    final graphFuture = DatabaseHelper.instance.getDailyRevenue();
    final summaryFuture = DatabaseHelper.instance.getTodaySummary();

    final data = await salesFuture;
    final graph = await graphFuture;
    final summary = await summaryFuture;

    if (!mounted) return;

    setState(() {
      selectedDate = filterDate;
      sales = data;
      revenueData = graph;
      todayRevenue = _asDouble(summary['total_revenue']);
      todayProfit = _asDouble(summary['total_profit']);
      todaySales = (summary['total_sales'] as num? ?? 0).toInt();
      _isLoading = false;
    });
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    await loadSales(filterDate: picked);
  }

  Future<void> clearDateFilter() async {
    await loadSales();
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
                subtitle: const Text("Export the last 30 days of sales"),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CsvExportScope.pastMonth),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text("Everything"),
                subtitle: const Text("Export all past sales data"),
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> exportToCSV() async {
    final scope = await _pickExportScope();
    if (scope == null) return;

    List<Map<String, dynamic>> exportSales;
    String exportLabel;

    switch (scope) {
      case _CsvExportScope.customDates:
        final range = await _pickExportDateRange();
        if (range == null) return;

        exportSales = await DatabaseHelper.instance.getSalesByDateRange(
          "${DateFormat('yyyy-MM-dd').format(range.start)} 00:00",
          "${DateFormat('yyyy-MM-dd').format(range.end)} 23:59",
        );
        exportLabel =
            "${DateFormat('yyyyMMdd').format(range.start)}_${DateFormat('yyyyMMdd').format(range.end)}";
        break;
      case _CsvExportScope.pastMonth:
        final end = DateTime.now();
        final start = end.subtract(const Duration(days: 29));
        exportSales = await DatabaseHelper.instance.getSalesByDateRange(
          "${DateFormat('yyyy-MM-dd').format(start)} 00:00",
          "${DateFormat('yyyy-MM-dd').format(end)} 23:59",
        );
        exportLabel = "past_month";
        break;
      case _CsvExportScope.everything:
        exportSales = await DatabaseHelper.instance.getSalesWithProduct();
        exportLabel = "all_data";
        break;
    }

    if (exportSales.isEmpty) {
      _showMessage("No sales found for the selected export range");
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final csv = StringBuffer(
        "Product,Units,Cost Price,Selling Price,Sold Price,Discount,Total,Profit Or Loss,Date\n",
      );

      for (final sale in exportSales) {
        final profit = _asDouble(sale['profit']);
        final soldPrice = sale['sold_price'] == null
            ? _asDouble(sale['selling_price']) - _asDouble(sale['discount'])
            : _asDouble(sale['sold_price']);

        csv.writeln(
          [
            _csvCell(sale['name']),
            _csvCell(sale['units']),
            _csvCell(_formatAmount(sale['cost_price'])),
            _csvCell(_formatAmount(sale['selling_price'])),
            _csvCell(_formatAmount(soldPrice)),
            _csvCell(_formatAmount(sale['discount'])),
            _csvCell(_formatAmount(sale['total'])),
            _csvCell(_formatAmount(profit)),
            _csvCell(sale['date']),
          ].join(','),
        );
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          "sales_export_${exportLabel}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv";
      final path = "${directory.path}/$fileName";

      final file = File(path);
      await file.writeAsString(csv.toString());

      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: "Sales Export File"),
      );

      if (!mounted) return;
      _showMessage("Export ready to share");
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
      await loadSales(filterDate: selectedDate);

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

  Future<void> deleteSale(int saleId) async {
    await DatabaseHelper.instance.deleteSale(saleId);
    if (!mounted) return;

    await loadSales(filterDate: selectedDate);
    if (!mounted) return;

    _showMessage("Sale deleted");
  }

  Future<void> _editSale(Map<String, dynamic> sale) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddSaleScreen(existingSale: sale)),
    );

    if (!mounted || updated != true) return;

    await loadSales(filterDate: selectedDate);
    if (!mounted) return;

    _showMessage("Sale updated");
  }

  Future<void> _showSaleDetails(Map<String, dynamic> sale) async {
    final profit = _asDouble(sale['profit']);
    final sellingPrice = _asDouble(sale['selling_price']);
    final costPrice = _asDouble(sale['cost_price']);
    final discount = _asDouble(sale['discount']);
    final soldPrice = sale['sold_price'] == null
        ? sellingPrice - discount
        : _asDouble(sale['sold_price']);
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
                  sale['name']?.toString() ?? 'Sale Details',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  sale['date']?.toString() ?? '--',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                _buildDetailRow(
                  "Units Sold",
                  sale['units']?.toString() ?? '--',
                ),
                _buildDetailRow("Selling Price", _formatCurrency(sellingPrice)),
                _buildDetailRow("Sold Price", _formatCurrency(soldPrice)),
                _buildDetailRow("Cost Price", _formatCurrency(costPrice)),
                _buildDetailRow("Discount", _formatCurrency(discount)),
                _buildDetailRow("Total", _formatCurrency(sale['total'])),
                _buildDetailRow(
                  _resultLabel(profit),
                  _formatResultValue(profit),
                  valueColor: profit < 0
                      ? colorScheme.error
                      : colorScheme.secondary,
                ),
                const SizedBox(height: 16),
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

  Future<bool> _confirmDeleteSale(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Delete Sale"),
          content: Text(
            "Delete the sale for ${sale['name']?.toString() ?? 'this product'}?",
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

  Future<void> _handleSaleLongPress(Map<String, dynamic> sale) async {
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
        await _showSaleDetails(sale);
        return;
      case 'edit':
        await _editSale(sale);
        return;
      case 'delete':
        final confirmed = await _confirmDeleteSale(sale);
        if (!confirmed) return;
        await deleteSale(sale['id'] as int);
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
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
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
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    final child = Text(label);
    if (filled) {
      return ElevatedButton.icon(
        onPressed: _isBusy ? null : onPressed,
        icon: Icon(icon),
        label: child,
      );
    }

    return OutlinedButton.icon(
      onPressed: _isBusy ? null : onPressed,
      icon: Icon(icon),
      label: child,
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            "$label $value",
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
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
                    "Review sales, export records, and manage previous transactions.",
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
      subtitle: "Filter the view, export sales, or create and restore backups",
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
    final todayResultLabel = _resultLabel(todayProfit);

    return _buildPanel(
      title: "Overview",
      subtitle: _overviewSubtitle(),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.18,
              children: [
                _buildMetricCard(
                  label: "Visible Sales",
                  value: "${summary['sales']}",
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF5F95FF),
                  caption: selectedDate == null
                      ? "All history"
                      : "Filtered day",
                ),
                _buildMetricCard(
                  label: "Visible Revenue",
                  value: _formatCurrency(summary['revenue']),
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF57D77F),
                  caption: "Current screen total",
                ),
                _buildMetricCard(
                  label: "Visible ${_resultLabel(visibleProfit)}",
                  value: _formatResultValue(visibleProfit),
                  icon: Icons.account_balance_wallet_outlined,
                  color: visibleProfit < 0
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFFB785FF),
                  caption: "Calculated from sale records",
                ),
                _buildMetricCard(
                  label: "Today's Sales",
                  value: "$todaySales",
                  icon: Icons.today_outlined,
                  color: const Color(0xFFFFB43A),
                  caption: "Revenue ${_formatCurrency(todayRevenue)}",
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              "Today: ${_formatCurrency(todayRevenue)} revenue • $todayResultLabel ${_formatResultValue(todayProfit)}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
      subtitle: "Latest sales days in your local history",
      child: _buildRevenueChart(),
    );
  }

  Widget _buildSectionHeader(_SalesSection section) {
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
              _buildInfoPill(
                icon: Icons.receipt_long_rounded,
                label: "Sales",
                value: "${section.sales.length}",
              ),
              _buildInfoPill(
                icon: Icons.currency_rupee_rounded,
                label: "Revenue",
                value: _formatCurrency(section.revenue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final profit = _asDouble(sale['profit']);
    final sellingPrice = _asDouble(sale['selling_price']);
    final costPrice = _asDouble(sale['cost_price']);
    final discount = _asDouble(sale['discount']);
    final soldPrice = sale['sold_price'] == null
        ? sellingPrice - discount
        : _asDouble(sale['sold_price']);
    final profitLabel = _resultLabel(profit);
    final saleDate = _parseSaleDate(sale['date']?.toString());
    final colorScheme = Theme.of(context).colorScheme;
    final resultColor = profit < 0 ? colorScheme.error : colorScheme.secondary;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withAlpha(40)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showSaleDetails(sale),
        onLongPress: () => _handleSaleLongPress(sale),
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
                          sale['name']?.toString() ?? 'Unknown Product',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${_formatTime(saleDate)} • ${sale['date']}",
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
                        _formatCurrency(sale['total']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$profitLabel ${_formatResultValue(profit)}",
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoPill(
                    icon: Icons.shopping_bag_outlined,
                    label: "Units",
                    value: sale['units']?.toString() ?? '--',
                  ),
                  _buildInfoPill(
                    icon: Icons.sell_outlined,
                    label: "SP",
                    value: _formatCurrency(sellingPrice),
                  ),
                  _buildInfoPill(
                    icon: Icons.payments_outlined,
                    label: "Sold",
                    value: _formatCurrency(soldPrice),
                  ),
                  _buildInfoPill(
                    icon: Icons.local_offer_outlined,
                    label: "Discount",
                    value: _formatCurrency(discount),
                  ),
                  _buildInfoPill(
                    icon: Icons.inventory_2_outlined,
                    label: "Cost",
                    value: _formatCurrency(costPrice),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Tap for details. Long press for more actions.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesTimeline() {
    final sections = _groupedSales();

    if (sections.isEmpty) {
      return _buildPanel(
        title: "Sales Timeline",
        subtitle: selectedDate == null
            ? "No sales have been recorded yet"
            : "No sales found for ${_formatSectionDate(selectedDate!)}",
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              selectedDate == null
                  ? "No sales yet"
                  : "No sales on the selected date",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return _buildPanel(
      title: "Sales Timeline",
      subtitle: "Tap a sale for details. Long press to edit or delete it",
      child: Column(
        children: sections.map((section) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                _buildSectionHeader(section),
                ...section.sales.map(_buildSaleCard),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && sales.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Sales History")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Sales History")),
      body: RefreshIndicator(
        onRefresh: () => loadSales(filterDate: selectedDate),
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
            _buildSalesTimeline(),
          ],
        ),
      ),
    );
  }
}

class _SalesSection {
  const _SalesSection({
    required this.date,
    required this.sales,
    required this.revenue,
    required this.profit,
  });

  final DateTime date;
  final List<Map<String, dynamic>> sales;
  final double revenue;
  final double profit;
}
