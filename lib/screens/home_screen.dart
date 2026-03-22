import 'package:flutter/material.dart';
import 'sales_history_screen.dart';
import '../database/database_helper.dart';
import 'add_product_screen.dart';
import 'add_sale_screen.dart';
import 'stock_adjust_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    final data = await DatabaseHelper.instance.getProducts();
    setState(() {
      products = data;
    });
  }

  // 🔥 Merge duplicate logic
  Future<void> mergeDuplicate(
      Map<String, dynamic> p1,
      Map<String, dynamic> p2) async {
    int totalStock = p1['stock'] + p2['stock'];

    await DatabaseHelper.instance.updateStock(
      p1['id'],
      totalStock,
    );

    await DatabaseHelper.instance.deleteProduct(
      p2['id'],
    );

    loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sales Manager")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddProductScreen(),
                  ),
                );
                loadProducts();
              },
              child: const Text("Add Product"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const SalesHistoryScreen(),
                  ),
                );
              },
              child: const Text("Sales History"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddSaleScreen(),
                  ),
                );
                loadProducts();
              },
              child: const Text("Record Sale"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const StockAdjustScreen(),
                  ),
                );
                loadProducts();
              },
              child: const Text("Stock Adjustment"),
            ),
            const SizedBox(height: 20),
            const Text(
              "Product List",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: products.isEmpty
                  ? const Center(child: Text("No Products Added"))
                  : ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];

                        return Card(
                          child: ListTile(
                            title: Text(
                              p['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: p['stock'] == 0
                                    ? Colors.red
                                    : p['stock'] <= 5
                                        ? Colors.orange
                                        : Colors.black,
                              ),
                            ),
                            subtitle: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Stock: ${p['stock']} | ₹${p['selling_price']}",
                                  style: TextStyle(
                                    color: p['stock'] == 0
                                        ? Colors.red
                                        : p['stock'] <= 1
                                            ? Colors.orange
                                            : Colors.black,
                                  ),
                                ),
                                if (p['stock'] == 0)
                                  const Chip(
                                    label: Text("OUT OF STOCK"),
                                    backgroundColor: Colors.red,
                                    labelStyle: TextStyle(color: Colors.white),
                                  )
                                else if (p['stock'] <= 5)
                                  const Chip(
                                    label: Text("LOW STOCK"),
                                    backgroundColor: Colors.orange,
                                    labelStyle: TextStyle(color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}