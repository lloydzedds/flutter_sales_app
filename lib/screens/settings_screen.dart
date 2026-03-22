import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_settings_controller.dart';
import '../database/database_helper.dart';
import 'how_to_use_screen.dart';
import 'store_details_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = AppSettingsController.instance;

  Map<String, String> _storeDetails = {};
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadStoreDetails();
  }

  Future<void> _loadStoreDetails() async {
    final details = await DatabaseHelper.instance.getStoreDetails();
    if (!mounted) return;
    setState(() {
      _storeDetails = details;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openStoreDetails() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const StoreDetailsScreen()));

    if (!mounted || updated != true) return;
    await _loadStoreDetails();
    if (!mounted) return;
    _showMessage("Store details updated");
  }

  Future<void> _backupData() async {
    setState(() {
      _isBusy = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          "sales_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db";
      final backupPath = "${directory.path}/$fileName";

      final backupFile = await DatabaseHelper.instance.createBackup(backupPath);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupFile.path)],
          text: "Sales Manager backup",
        ),
      );

      if (!mounted) return;
      _showMessage("Backup created and ready to share");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _restoreData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );

    if (result == null) return;
    final selectedPath = result.files.single.path;
    if (selectedPath == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await DatabaseHelper.instance.restoreDatabaseFromFile(selectedPath);
      await _controller.reload();
      await _loadStoreDetails();

      if (!mounted) return;
      _showMessage("Backup restored. Reopen screens to refresh loaded data.");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final storeName = _storeDetails['store_name']?.trim() ?? '';
          final ownerName = _storeDetails['store_owner']?.trim() ?? '';
          final defaultDiscountMode = _controller.defaultDiscountMode;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSection(
                title: "Appearance",
                subtitle: "Change how the application looks",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: Icon(Icons.phone_android_rounded),
                          label: Text("System"),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text("Light"),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text("Dark"),
                        ),
                      ],
                      selected: {_controller.themeMode},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        _controller.setThemeMode(selection.first);
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Current: ${_controller.themeModeLabel(_controller.themeMode)}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              _buildSection(
                title: "Record Sale Defaults",
                subtitle:
                    "Choose which discount option opens first in Record Sale",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'manual',
                          icon: Icon(Icons.edit_outlined),
                          label: Text("Manual"),
                        ),
                        ButtonSegment<String>(
                          value: 'sold_price',
                          icon: Icon(Icons.sell_outlined),
                          label: Text("Sold Price"),
                        ),
                        ButtonSegment<String>(
                          value: 'percentage',
                          icon: Icon(Icons.percent_rounded),
                          label: Text("Percentage"),
                        ),
                      ],
                      selected: {defaultDiscountMode},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        _controller.setDefaultDiscountMode(selection.first);
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Current: ${_controller.discountModeLabel(defaultDiscountMode)}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              _buildSection(
                title: "Invoice and Store Details",
                subtitle:
                    "Store information that can be used in invoices and business details",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName.isEmpty ? "Store name not set" : storeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ownerName.isEmpty ? "Owner/contact not set" : ownerName,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openStoreDetails,
                        icon: const Icon(Icons.store_mall_directory_outlined),
                        label: const Text("Edit Store Details"),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSection(
                title: "Backup Data",
                subtitle:
                    "Create a local backup file or restore from an existing backup",
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isBusy ? null : _backupData,
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text("Take Local Backup"),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _restoreData,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text("Restore From Backup"),
                      ),
                    ),
                    if (_isBusy) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              _buildSection(
                title: "How to Use This Application",
                subtitle: "Quick help for daily use",
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HowToUseScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.help_outline_rounded),
                    label: const Text("Open Guide"),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
