import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ads/ad_banner_panel.dart';
import '../database/database_helper.dart';
import 'customer_history_screen.dart';
import 'edit_customer_screen.dart';

enum _CustomerAction { history, edit }

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final rows = await DatabaseHelper.instance.getCustomers(
      search: _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _customers = rows;
      _isLoading = false;
    });
  }

  String _formatCurrency(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    if (amount == amount.roundToDouble()) {
      return "Rs ${amount.toStringAsFixed(0)}";
    }
    return "Rs ${amount.toStringAsFixed(2)}";
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return "No purchases yet";
    try {
      final date = DateFormat('yyyy-MM-dd HH:mm').parseStrict(raw);
      return DateFormat('d MMM yyyy, h:mm a').format(date);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _openCustomerHistory(Map<String, dynamic> customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerHistoryScreen(customer: customer),
      ),
    );
    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditCustomerScreen(customer: customer)),
    );
    if (!mounted || updated != true) return;
    await _loadCustomers();
  }

  Future<void> _handleCustomerAction(
    _CustomerAction action,
    Map<String, dynamic> customer,
  ) async {
    switch (action) {
      case _CustomerAction.history:
        await _openCustomerHistory(customer);
        break;
      case _CustomerAction.edit:
        await _editCustomer(customer);
        break;
    }
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final phone = customer['phone']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: ListTile(
        onTap: () => _openCustomerHistory(customer),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        title: Text(
          customer['name']?.toString().trim().isNotEmpty == true
              ? customer['name'].toString().trim()
              : 'Unnamed Customer',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(phone.isEmpty ? "Phone not saved" : phone),
              const SizedBox(height: 6),
              Text(
                "Orders: ${customer['orders_count']} • Spent: ${_formatCurrency(customer['total_spent'])}",
              ),
              const SizedBox(height: 4),
              Text(
                "Last purchase: ${_formatDate(customer['last_purchase_date']?.toString())}",
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<_CustomerAction>(
          onSelected: (action) => _handleCustomerAction(action, customer),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _CustomerAction.history,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_rounded),
                title: Text("View History"),
              ),
            ),
            PopupMenuItem(
              value: _CustomerAction.edit,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined),
                title: Text("Edit Customer"),
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
      appBar: AppBar(title: const Text("Customers")),
      body: RefreshIndicator(
        onRefresh: _loadCustomers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Customer Directory",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Search saved customers by name or phone number and open their purchase history.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => _loadCustomers(),
                      decoration: InputDecoration(
                        labelText: "Search Customers",
                        hintText: "Type a name or phone number",
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _loadCustomers();
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const AdBannerPanel(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_customers.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    "No customers found yet. Customer records will appear here after you save sales with a name or phone number.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ..._customers.map(_buildCustomerCard),
          ],
        ),
      ),
    );
  }
}
