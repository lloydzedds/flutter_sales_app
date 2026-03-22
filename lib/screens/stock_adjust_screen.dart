import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class StockAdjustScreen extends StatefulWidget {
  const StockAdjustScreen({super.key});

  @override
  State<StockAdjustScreen> createState() =>
      _StockAdjustScreenState();
}

class _StockAdjustScreenState
    extends State<StockAdjustScreen> {
  List<Map<String, dynamic>> products = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;

  final qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    final data =
        await DatabaseHelper.instance.getProducts();
    setState(() {
      products = data;
    });
  }

  Future<void> adjustStock(bool isAdd) async {
    if (selectedProduct == null ||
        qtyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields")),
      );
      return;
    }

    int qty = int.parse(qtyController.text);
    int currentStock = selectedProduct!['stock'] as int;

    int newStock =
        isAdd ? currentStock + qty : currentStock - qty;

    if (newStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Stock cannot be negative")),
      );
      return;
    }

    await DatabaseHelper.instance.updateStock(
      selectedProduct!['id'] as int,
      newStock,
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text("Stock Adjustment")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: selectedProductId,
              items: products.map((product) {
                return DropdownMenuItem<int>(
                  value: product['id'],
                  child: Text(product['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedProductId = value;
                  selectedProduct =
                      products.firstWhere(
                          (p) => p['id'] == value);
                });
              },
              decoration: const InputDecoration(
                  labelText: "Select Product"),
            ),
            TextField(
              controller: qtyController,
              decoration:
                  const InputDecoration(labelText: "Quantity"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () =>
                      adjustStock(true),
                  child: const Text("Add Stock"),
                ),
                ElevatedButton(
                  onPressed: () =>
                      adjustStock(false),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red),
                  child:
                      const Text("Remove Stock"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}