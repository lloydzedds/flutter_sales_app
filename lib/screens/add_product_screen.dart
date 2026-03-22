import '../database/database_helper.dart';
import 'package:flutter/material.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final nameController = TextEditingController();
  final costController = TextEditingController();
  final priceController = TextEditingController();
  final stockController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Product")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Product Name"),
            ),
            TextField(
              controller: costController,
              decoration: const InputDecoration(labelText: "Cost Price"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: "Selling Price"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: "Initial Stock"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    costController.text.isEmpty ||
                    priceController.text.isEmpty ||
                    stockController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Fill all fields")),
                  );
                  return;
                }

                String baseName = nameController.text.trim();
                double cost = double.parse(costController.text);
                double price = double.parse(priceController.text);
                int stock = int.parse(stockController.text);

                final existingSamePrice =
                    await DatabaseHelper.instance.findProduct(baseName, price);

                if (existingSamePrice != null) {
                  int newStock = existingSamePrice['stock'] + stock;

                  await DatabaseHelper.instance.updateStock(
                    existingSamePrice['id'],
                    newStock,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Stock Updated")),
                  );
                } else {
                  // Check if same name but different price exists
                  final sameNameList =
                      await DatabaseHelper.instance.findByName(baseName);

                  String finalName = baseName;

                  if (sameNameList.isNotEmpty) {
                    finalName = "$baseName ($price)";
                  }

                  await DatabaseHelper.instance.insertProduct({
                    'name': finalName,
                    'cost_price': cost,
                    'selling_price': price,
                    'stock': stock,
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("New Product Added")),
                  );
                }

                nameController.clear();
                costController.clear();
                priceController.clear();
                stockController.clear();
              },
              child: const Text("Save Product"),
            )
          ],
        ),
      ),
    );
  }
}