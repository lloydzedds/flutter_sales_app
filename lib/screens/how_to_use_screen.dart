import 'package:flutter/material.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  Widget _stepCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 22, child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("How to Use")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stepCard(
            icon: Icons.dashboard_outlined,
            title: "Dashboard",
            description:
                "Use the dashboard to track revenue, profit, product count, recent sales, and top selling products for the selected date range.",
          ),
          _stepCard(
            icon: Icons.add_box_outlined,
            title: "Add Products",
            description:
                "Open the inventory section and use Add Product to save a product with cost price, selling price, and opening stock.",
          ),
          _stepCard(
            icon: Icons.shopping_cart_checkout_rounded,
            title: "Record Sales",
            description:
                "Use Record Sale or New Order to add one or more products, apply discount by amount, sold price, or percentage, and optionally save the customer name and phone number with the sale.",
          ),
          _stepCard(
            icon: Icons.people_alt_outlined,
            title: "Customers",
            description:
                "Open Customers to search saved customers by name or phone number and review their purchase history.",
          ),
          _stepCard(
            icon: Icons.inventory_2_outlined,
            title: "Manage Stock",
            description:
                "Use Stock Adjustment to add stock, remove stock, or set the exact stock value. You can also long press products to edit product details or open quick stock actions.",
          ),
          _stepCard(
            icon: Icons.history_rounded,
            title: "Sales History",
            description:
                "Sales History lets you filter by date, review full orders, open sale details, edit old sales, delete a sale, export CSV, and share bill PDFs for past purchases.",
          ),
          _stepCard(
            icon: Icons.settings_outlined,
            title: "Settings and Backup",
            description:
                "Settings lets you change theme, choose the default discount mode for Record Sale, update store details, take local backups, restore old backups, and review this guide anytime.",
          ),
        ],
      ),
    );
  }
}
