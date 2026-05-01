import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_settings_controller.dart';
import '../database/database_helper.dart';
import '../services/account_sync_service.dart';
import '../services/sales_export_service.dart';
import 'how_to_use_screen.dart';
import 'store_details_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = AppSettingsController.instance;
  final _syncService = AccountSyncService.instance;

  Map<String, String> _storeDetails = {};
  bool _isBusy = false;
  CloudBackupInfo? _cloudBackupInfo;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_handleSyncChanged);
    _loadStoreDetails();
    _loadCloudBackupInfo();
  }

  @override
  void dispose() {
    _syncService.removeListener(_handleSyncChanged);
    super.dispose();
  }

  void _handleSyncChanged() {
    if (mounted) {
      setState(() {});
    }
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

  String _formatCloudDate(DateTime? value) {
    if (value == null) return 'No cloud backup yet';
    return DateFormat('MMM d, yyyy h:mm a').format(value.toLocal());
  }

  Future<void> _loadCloudBackupInfo() async {
    if (!_syncService.isSignedIn) {
      if (!mounted) return;
      setState(() {
        _cloudBackupInfo = null;
      });
      return;
    }

    try {
      final info = await _syncService.getLatestBackupInfo();
      if (!mounted) return;
      setState(() {
        _cloudBackupInfo = info;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudBackupInfo = null;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _syncService.signIn();
      await _loadCloudBackupInfo();
      if (!mounted) return;
      _showMessage("Signed in as ${_syncService.email}");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _signOutFromGoogle() async {
    await _syncService.signOut();
    await _loadCloudBackupInfo();
    if (!mounted) return;
    _showMessage("Signed out");
  }

  Future<void> _backupToCloud() async {
    try {
      final info = await _syncService.uploadCurrentDatabase();
      if (!mounted) return;
      setState(() {
        _cloudBackupInfo = info;
      });
      _showMessage("Cloud backup saved for ${_syncService.email}");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _restoreFromCloud() async {
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Restore cloud backup?"),
          content: Text(
            "This will replace the local Sale Buddy data on this device with the backup saved for ${_syncService.email}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Restore"),
            ),
          ],
        );
      },
    );

    if (shouldRestore != true) return;

    try {
      final info = await _syncService.restoreLatestDatabase();
      await _controller.reload();
      await _loadStoreDetails();
      if (!mounted) return;
      setState(() {
        _cloudBackupInfo = info;
      });
      _showMessage("Cloud backup restored");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<String?> _pickBackupAction() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text("Share Backup"),
                subtitle: const Text(
                  "Open the Android share menu and send the backup to another app",
                ),
                onTap: () => Navigator.of(sheetContext).pop('share'),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text("Save to Local"),
                subtitle: const Text(
                  "Save the backup in Android/media/<app>/sale",
                ),
                onTap: () => Navigator.of(sheetContext).pop('save'),
              ),
            ],
          ),
        );
      },
    );
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
    final action = await _pickBackupAction();
    if (action == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final directory = action == 'save'
          ? await SalesExportService.ensureLocalSaleDirectory()
          : await SalesExportService.ensureShareDirectory();
      final fileName =
          "sales_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db";
      final backupPath = "${directory.path}/$fileName";

      final backupFile = await DatabaseHelper.instance.createBackup(backupPath);

      if (action == 'share') {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(backupFile.path)],
            text: "Sale Buddy backup",
          ),
        );
      }

      if (!mounted) return;
      _showMessage(
        action == 'share'
            ? "Share sheet opened for backup"
            : "Backup saved to ${backupFile.parent.path}",
      );
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
      dialogTitle: "Select backup database",
      type: FileType.custom,
      allowedExtensions: ['db'],
      allowMultiple: false,
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
      _showMessage("Backup restored successfully");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
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

  Widget _buildAccountSection() {
    final signedIn = _syncService.isSignedIn;
    final busy = _syncService.isBusy;
    final name = _syncService.displayName?.trim() ?? '';
    final email = _syncService.email ?? '';
    final title = signedIn
        ? (name.isEmpty ? email : name)
        : "No Google account connected";
    final subtitle = signedIn
        ? "$email\nLast cloud backup: ${_formatCloudDate(_cloudBackupInfo?.modifiedTime)}"
        : "Sign in with Google to save and restore this device's data from your account.";

    return _buildSection(
      title: "Account and Cloud Backup",
      subtitle: "Save and restore data with Google Drive app data",
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: _syncService.photoUrl == null
                  ? null
                  : NetworkImage(_syncService.photoUrl!),
              child: _syncService.photoUrl == null
                  ? const Icon(Icons.account_circle_outlined)
                  : null,
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
          ),
          const SizedBox(height: 12),
          if (!signedIn)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : _signInWithGoogle,
                icon: const Icon(Icons.login_rounded),
                label: const Text("Sign in with Google"),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : _backupToCloud,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text("Save Backup to Google"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _restoreFromCloud,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text("Restore from Google"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: busy ? null : _signOutFromGoogle,
                icon: const Icon(Icons.logout_rounded),
                label: const Text("Sign Out"),
              ),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
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
              _buildAccountSection(),
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
