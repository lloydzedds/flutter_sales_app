import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() =>
      _SalesHistoryScreenState();
}

class _SalesHistoryScreenState
    extends State<SalesHistoryScreen> {
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

  Future<void> loadSales() async {
    final data =
        await DatabaseHelper.instance.getSalesWithProduct();
    final graph =
        await DatabaseHelper.instance.getDailyRevenue();

    final summary =
        await DatabaseHelper.instance.getTodaySummary();

    if (!mounted) return;
    setState(() {
      sales = data;
      revenueData = graph;
      todayRevenue =
          (summary['total_revenue'] as num? ?? 0).toDouble();

      todayProfit =
          (summary['total_profit'] as num? ?? 0).toDouble();

      todaySales =
          (summary['total_sales'] as num? ?? 0).toInt();
    });
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      selectedDate = picked;

      String start =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} 00:00";

      String end =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} 23:59";

      final filtered = await DatabaseHelper.instance
          .getSalesByDateRange(start, end);

      setState(() {
        sales = filtered;
      });
    }
  }
  Future<void> exportToCSV() async {
    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No sales to export")),
      );
      return;
    }

    String csv = "Product,Units,Discount,Total,Profit,Date\n";

    for (var s in sales) {
      csv +=
          "${s['name']},${s['units']},${s['discount']},${s['total']},${s['profit']},${s['date']}\n";
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Export & Share Ready")),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Backup Created & Ready to Share")),
    );
  }
  Future<void> restoreDatabase() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Database Restored. Restart App.")),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text("Sales History")),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: pickDate,
            child: const Text("Filter By Date"),
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
                      fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text("Sales: $todaySales",
                    style:
                        const TextStyle(color: Colors.white)),
                Text("Revenue: ₹$todayRevenue",
                    style:
                        const TextStyle(color: Colors.white)),
                Text(
                  "Profit: ₹$todayProfit",
                  style: TextStyle(
                      color: todayProfit < 0
                          ? Colors.red
                          : Colors.green),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: revenueData
                        .asMap()
                        .entries
                        .map((entry) {
                      return FlSpot(
                        entry.key.toDouble(),
                        (entry.value['revenue'] as num? ?? 0).toDouble(),
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
                      final s = sales[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6),
                        child: ListTile(
                          title: Text(
                            s['name'],
                            style: const TextStyle(
                                fontWeight:
                                    FontWeight.bold),
                          ),
                          subtitle: Text(
                              "Units: ${s['units']} | Discount: ₹${s['discount']}\nDate: ${s['date']}"),
                          trailing: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text("₹${s['total']}"),
                              Text(
                                "Profit: ₹${s['profit']}",
                                style: TextStyle(
                                  color:
                                      s['profit'] < 0
                                          ? Colors.red
                                          : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          onLongPress: () async {
                            await DatabaseHelper.instance
                                .deleteSale(s['id']);
                            if (!mounted) return;
                            loadSales();
                            ScaffoldMessenger.of(this.context)
                                .showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Sale Deleted")),
                            );
                          },
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}
