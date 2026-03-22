import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class StoreDetailsScreen extends StatefulWidget {
  const StoreDetailsScreen({super.key});

  @override
  State<StoreDetailsScreen> createState() => _StoreDetailsScreenState();
}

class _StoreDetailsScreenState extends State<StoreDetailsScreen> {
  final _storeNameController = TextEditingController();
  final _ownerController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _invoicePrefixController = TextEditingController();
  final _invoiceNoteController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taxIdController.dispose();
    _invoicePrefixController.dispose();
    _invoiceNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final details = await DatabaseHelper.instance.getStoreDetails();
    if (!mounted) return;

    _storeNameController.text = details['store_name'] ?? '';
    _ownerController.text = details['store_owner'] ?? '';
    _phoneController.text = details['store_phone'] ?? '';
    _emailController.text = details['store_email'] ?? '';
    _addressController.text = details['store_address'] ?? '';
    _taxIdController.text = details['store_tax_id'] ?? '';
    _invoicePrefixController.text = details['invoice_prefix'] ?? '';
    _invoiceNoteController.text = details['invoice_note'] ?? '';
    setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_storeNameController.text.trim().isEmpty) {
      _showMessage("Store name is required");
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await DatabaseHelper.instance.saveStoreDetails({
      'store_name': _storeNameController.text.trim(),
      'store_owner': _ownerController.text.trim(),
      'store_phone': _phoneController.text.trim(),
      'store_email': _emailController.text.trim(),
      'store_address': _addressController.text.trim(),
      'store_tax_id': _taxIdController.text.trim(),
      'invoice_prefix': _invoicePrefixController.text.trim(),
      'invoice_note': _invoiceNoteController.text.trim(),
    });

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    Navigator.of(context).pop(true);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Store Details")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Invoice and Store Information",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "These details are saved as your business identity for invoice-ready information.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  _field(controller: _storeNameController, label: "Store Name"),
                  _field(
                    controller: _ownerController,
                    label: "Owner / Contact Person",
                  ),
                  _field(
                    controller: _phoneController,
                    label: "Phone Number",
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    controller: _emailController,
                    label: "Email Address",
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _field(
                    controller: _addressController,
                    label: "Store Address",
                    maxLines: 3,
                  ),
                  _field(
                    controller: _taxIdController,
                    label: "Tax / GST Number",
                  ),
                  _field(
                    controller: _invoicePrefixController,
                    label: "Invoice Prefix",
                  ),
                  _field(
                    controller: _invoiceNoteController,
                    label: "Invoice Footer Note",
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? "Saving..." : "Save Details"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
