import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'package:intl/intl.dart';

class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key});

  @override
  State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  List<Map<String, dynamic>> products = [];
  int? selectedProductId;
  Map<String, dynamic>? selectedProduct;

  final unitsController = TextEditingController();
  final discountController = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Record Sale")),
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
                      products.firstWhere((p) => p['id'] == value);
                });
              },
              decoration:
                  const InputDecoration(labelText: "Select Product"),
            ),
            TextField(
              controller: unitsController,
              decoration:
                  const InputDecoration(labelText: "Units Sold"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: discountController,
              decoration: const InputDecoration(
                  labelText: "Discount per unit"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (selectedProduct == null ||
                    unitsController.text.isEmpty ||
                    discountController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Fill all fields")),
                  );
                  return;
                }

                int units = int.parse(unitsController.text);
                double discount =
                    double.parse(discountController.text);

                double sellingPrice =
                    selectedProduct!['selling_price'];
                double costPrice =
                    selectedProduct!['cost_price'];
                int currentStock =
                    selectedProduct!['stock'];

                if (units > currentStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Not enough stock")),
                  );
                  return;
                }

                double finalPrice =
                    sellingPrice - discount;
                double total = finalPrice * units;
                double profit =
                    (finalPrice - costPrice) * units;

                int newStock = currentStock - units;

                await DatabaseHelper.instance
                    .updateStock(
                        selectedProduct!['id'],
                        newStock);

                await DatabaseHelper.instance.insertSale({
                  'product_id': selectedProduct!['id'],
                  'units': units,
                  'discount': discount,
                  'total': total,
                  'profit': profit,
                  'date': DateFormat('yyyy-MM-dd HH:mm')
                      .format(DateTime.now()),
                });

                Navigator.pop(context);
              },
              child: const Text("Save Sale"),
            )
          ],
        ),
      ),
    );
  }
}