import 'package:flutter/material.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  Widget _introCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Quick Start",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              "Add your products first, then record sales, manage stock, review customer history, export reports, and keep backups of your data. This guide covers the main features available in the app.",
            ),
          ],
        ),
      ),
    );
  }

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
          _introCard(),
          _stepCard(
            icon: Icons.calendar_month_outlined,
            title: "Dashboard and Date Range",
            description:
                "Use the dashboard to track revenue, profit, sales count, product count, recent sales, and top selling products. Change the date range to see business activity for the last 7 days or a custom period.",
          ),
          _stepCard(
            icon: Icons.add_box_outlined,
            title: "Add or Update Products",
            description:
                "Use Add Product to create a new product with name, cost price, selling price, opening stock, and an optional product photo. While typing the name, matching products appear below the field, and selecting one lets you correct the name, update prices, and add more stock to the existing product.",
          ),
          _stepCard(
            icon: Icons.photo_camera_outlined,
            title: "Product Photos and Inventory",
            description:
                "You can attach a product photo from camera or gallery. Inventory items on the home screen can be long pressed for product edit and stock actions, so you can quickly fix names, prices, or stock without opening multiple screens.",
          ),
          _stepCard(
            icon: Icons.shopping_cart_checkout_rounded,
            title: "Record Sales",
            description:
                "Use Record Sale or New Order to add one or more products in a single order. Search for products inside the product box, add items one by one, and apply discounts by manual amount, sold price, or percentage. Customer name and phone number are optional, and cost price / profit are hidden unless you confirm to view them.",
          ),
          _stepCard(
            icon: Icons.payments_outlined,
            title: "Payments and Sale Summary",
            description:
                "Each order can be marked as Paid in Full, Partially Paid, or Unpaid, with payment methods like Cash, UPI, Card, Bank Transfer, Credit, Cheque, or Other. The sale summary shows item-wise details, total amount, amount received, due amount, and the final order total before saving.",
          ),
          _stepCard(
            icon: Icons.people_alt_outlined,
            title: "Customers",
            description:
                "Customers are created automatically from sale records when you save a customer name or phone number. Open Customers to search by name or phone number, review purchase history, edit wrong customer details, and open any past order for more information.",
          ),
          _stepCard(
            icon: Icons.inventory_2_outlined,
            title: "Manage Stock",
            description:
                "Use Stock Adjustment to add stock, remove stock, or set the exact stock quantity. The screen shows current stock, selling price, and updated stock preview. You can also long press products on the dashboard inventory list for quick stock actions.",
          ),
          _stepCard(
            icon: Icons.history_rounded,
            title: "Sales History",
            description:
                "Sales History lets you filter by date, review full orders, check payment status, see customer details, view item-wise sale details, edit eligible sales, delete eligible sales, record product returns, export CSV or PDF reports, and share bill PDFs for past purchases.",
          ),
          _stepCard(
            icon: Icons.assignment_return_outlined,
            title: "Returns",
            description:
                "From Sales History or Customer History, you can record full or partial product returns against an old sale. Choose the return quantity for each item, add a reason, and decide whether the returned units should go back into stock or stay out of inventory for damaged items.",
          ),
          _stepCard(
            icon: Icons.receipt_long_outlined,
            title: "Bills, Exports, and Reports",
            description:
                "You can generate and share bill PDFs for past orders, export sales to CSV or PDF for custom dates, the past month, or all data, and choose whether to share the file or save it locally in the sale folder on the device.",
          ),
          _stepCard(
            icon: Icons.settings_outlined,
            title: "Settings, Backup, and Restore",
            description:
                "Settings lets you change the application theme, choose the default discount mode for Record Sale, update invoice and store details, take a backup, save backups locally, restore a selected `.db` backup file from device storage, and review this guide anytime.",
          ),
        ],
      ),
    );
  }
}
