import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'add_sale_screen.dart';
import '../database/database_helper.dart';

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

  @override
  void initState() {
    super.initState();
    loadSales();
  }

  Map<String, String> _dateRange(DateTime date) {
    final day =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    return {
      'start': "$day 00:00",
      'end': "$day 23:59",
    };
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

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Map<String, dynamic> _visibleSummary() {
    double revenue = 0;
    double profit = 0;

    for (final sale in sales) {
      revenue += _asDouble(sale['total']);
      profit += _asDouble(sale['profit']);
    }

    return {
      'sales': sales.length,
      'revenue': revenue,
      'profit': profit,
    };
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> loadSales({DateTime? filterDate}) async {
    final data = filterDate == null
        ? await DatabaseHelper.instance.getSalesWithProduct()
        : await DatabaseHelper.instance.getSalesByDateRange(
            _dateRange(filterDate)['start']!,
            _dateRange(filterDate)['end']!,
          );
    final graph = await DatabaseHelper.instance.getDailyRevenue();
    final summary = await DatabaseHelper.instance.getTodaySummary();

    if (!mounted) return;
    setState(() {
      selectedDate = filterDate;
      sales = data;
      revenueData = graph;
      todayRevenue = (summary['total_revenue'] as num? ?? 0).toDouble();
      todayProfit = (summary['total_profit'] as num? ?? 0).toDouble();
      todaySales = (summary['total_sales'] as num? ?? 0).toInt();
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

    await loadSales(filterDate: picked);
  }

  Future<void> clearDateFilter() async {
    await loadSales();
  }

  Future<void> exportToCSV() async {
    if (sales.isEmpty) {
      _showMessage("No sales to export");
      return;
    }

    String csv =
        "Product,Units,Cost Price,Selling Price,Sold Price,Discount,Total,Profit Or Loss,Date\n";

    for (final sale in sales) {
      final profit = _asDouble(sale['profit']);
      final soldPrice = sale['sold_price'] == null
          ? _asDouble(sale['selling_price']) - _asDouble(sale['discount'])
          : _asDouble(sale['sold_price']);

      csv +=
          "${sale['name']},${sale['units']},${_formatAmount(sale['cost_price'])},${_formatAmount(sale['selling_price'])},${_formatAmount(soldPrice)},${_formatAmount(sale['discount'])},${_formatAmount(sale['total'])},${_formatAmount(profit)},${sale['date']}\n";
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/sales_export.csv";

    final file = File(path);
    await file.writeAsString(csv);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: "Sales Export File",
      ),
    );

    if (!mounted) return;
    _showMessage("Export & Share Ready");
  }

  Future<void> backupDatabase() async {
    final dbPath = await DatabaseHelper.instance.getDatabasePath();
    final dbFile = File(dbPath);

    final directory = await getApplicationDocumentsDirectory();
    final backupPath = "${directory.path}/sales_backup.db";

    final backupFile = await dbFile.copy(backupPath);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(backupFile.path)],
        text: "Sales Database Backup",
      ),
    );

    if (!mounted) return;
    _showMessage("Backup Created & Ready to Share");
  }

  Future<void> restoreDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );

    if (result == null) return;

    final selectedPath = result.files.single.path;
    if (selectedPath == null) return;

    final pickedFile = File(selectedPath);
    final dbPath = await DatabaseHelper.instance.getDatabasePath();
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await pickedFile.copy(dbPath);

    if (!mounted) return;
    _showMessage("Database Restored. Restart App.");
  }

  Future<void> deleteSale(int saleId) async {
    await DatabaseHelper.instance.deleteSale(saleId);
    if (!mounted) return;

    await loadSales(filterDate: selectedDate);
    if (!mounted) return;

    _showMessage("Sale Deleted");
  }

  Future<void> _editSale(Map<String, dynamic> sale) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddSaleScreen(existingSale: sale),
      ),
    );

    if (!mounted || updated != true) return;

    await loadSales(filterDate: selectedDate);
    if (!mounted) return;

    _showMessage("Sale Updated");
  }

  Future<void> _showSaleDetails(Map<String, dynamic> sale) async {
    final profit = _asDouble(sale['profit']);
    final sellingPrice = _asDouble(sale['selling_price']);
    final costPrice = _asDouble(sale['cost_price']);
    final discount = _asDouble(sale['discount']);
    final soldPrice = sale['sold_price'] == null
        ? sellingPrice - discount
        : _asDouble(sale['sold_price']);
    final profitLabel = profit < 0 ? "Loss" : "Profit";

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(sale['name']?.toString() ?? 'Sale Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Date: ${sale['date']}"),
                Text("Units Sold: ${sale['units']}"),
                Text("Selling Price: Rs ${_formatAmount(sellingPrice)}"),
                Text("Sold Price: Rs ${_formatAmount(soldPrice)}"),
                Text("Cost Price: Rs ${_formatAmount(costPrice)}"),
                Text("Discount: Rs ${_formatAmount(discount)}"),
                Text("Total: Rs ${_formatAmount(sale['total'])}"),
                Text(
                  "$profitLabel: Rs ${_formatAmount(profit.abs())}",
                  style: TextStyle(
                    color: profit < 0 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSaleLongPress(Map<String, dynamic> sale) async {
    final action = await showModalBottomSheet<String>(
      context: context,
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
                title: const Text("Edit Sale"),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete Sale"),
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
        await deleteSale(sale['id'] as int);
        return;
    }
  }

  Widget _buildFilteredSummaryCard() {
    if (selectedDate == null) {
      return const SizedBox.shrink();
    }

    final summary = _visibleSummary();
    final profit = _asDouble(summary['profit']);
    final profitLabel = profit < 0 ? "Loss" : "Profit";

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blueGrey.shade50,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Sales for ${_formatDate(selectedDate!)}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text("Sales: ${summary['sales']}"),
          Text("Revenue: Rs ${_formatAmount(summary['revenue'])}"),
          Text(
            "$profitLabel: Rs ${_formatAmount(profit.abs())}",
            style: TextStyle(
              color: profit < 0 ? Colors.red : Colors.green,
              fontWeight: FontWeight.w600,
            ),
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
    final profitLabel = profit < 0 ? "Loss" : "Profit";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _handleSaleLongPress(sale),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      sale['name']?.toString() ?? 'Unknown Product',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    "Total: Rs ${_formatAmount(sale['total'])}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Date: ${sale['date']}"),
              Text("Units Sold: ${sale['units']}"),
              Text(
                "Selling Price: Rs ${_formatAmount(sellingPrice)} | Sold Price: Rs ${_formatAmount(soldPrice)}",
              ),
              Text(
                "Cost Price: Rs ${_formatAmount(costPrice)} | Discount: Rs ${_formatAmount(discount)}",
              ),
              const SizedBox(height: 6),
              Text(
                "$profitLabel: Rs ${_formatAmount(profit.abs())}",
                style: TextStyle(
                  color: profit < 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sales History")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: pickDate,
                  child: const Text("Filter By Date"),
                ),
                if (selectedDate != null)
                  OutlinedButton(
                    onPressed: clearDateFilter,
                    child: const Text("Clear Filter"),
                  ),
                ElevatedButton(
                  onPressed: exportToCSV,
                  child: const Text("Export to CSV"),
                ),
                ElevatedButton(
                  onPressed: backupDatabase,
                  child: const Text("Backup Database"),
                ),
                ElevatedButton(
                  onPressed: restoreDatabase,
                  child: const Text("Restore Database"),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's Summary",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Sales: $todaySales",
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  "Revenue: Rs ${_formatAmount(todayRevenue)}",
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  todayProfit < 0
                      ? "Loss: Rs ${_formatAmount(todayProfit.abs())}"
                      : "Profit: Rs ${_formatAmount(todayProfit)}",
                  style: TextStyle(
                    color: todayProfit < 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          _buildFilteredSummaryCard(),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: revenueData.asMap().entries.map((entry) {
                      return FlSpot(
                        entry.key.toDouble(),
                        _asDouble(entry.value['revenue']),
                      );
                    }).toList(),
                    isCurved: true,
                    barWidth: 3,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: sales.isEmpty
                ? const Center(child: Text("No Sales Yet"))
                : ListView.builder(
                    itemCount: sales.length,
                    itemBuilder: (context, index) {
                      return _buildSaleCard(sales[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
