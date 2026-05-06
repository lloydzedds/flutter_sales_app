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

class _CloudDataManagementScreen extends StatefulWidget {
  const _CloudDataManagementScreen();

  @override
  State<_CloudDataManagementScreen> createState() =>
      _CloudDataManagementScreenState();
}

class _CloudDataManagementScreenState
    extends State<_CloudDataManagementScreen> {
  final _syncService = AccountSyncService.instance;

  CloudBackupInfo? _backupInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_handleSyncChanged);
    _loadBackupInfo();
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

  Future<void> _loadBackupInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final info = await _syncService.getLatestBackupInfo();
      if (!mounted) return;
      setState(() {
        _backupInfo = info;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _backupInfo = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatCloudDate(DateTime? value) {
    if (value == null) return 'No cloud backup found';
    return DateFormat('MMM d, yyyy h:mm a').format(value.toLocal());
  }

  String _formatBackupSize(int? bytes) {
    if (bytes == null) return 'Size unavailable';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDelete() async {
    final email = _syncService.email ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var typedEmail = '';
        var showError = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Delete cloud backup?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "This will permanently delete the Google Drive backup saved for $email.",
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    onChanged: (value) {
                      typedEmail = value;
                      if (showError) {
                        setDialogState(() {
                          showError = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: "Confirm Google account email",
                      errorText: showError
                          ? "Email does not match the signed-in account"
                          : null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () {
                    final matches =
                        typedEmail.trim().toLowerCase() ==
                        email.trim().toLowerCase();
                    if (!matches) {
                      setDialogState(() {
                        showError = true;
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text("Delete"),
                ),
              ],
            );
          },
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _deleteCloudBackup() async {
    final confirmed = await _confirmDelete();
    if (!confirmed) return;

    try {
      await _syncService.deleteLatestCloudBackup();
      if (!mounted) return;
      setState(() {
        _backupInfo = null;
      });
      _showMessage("Cloud backup deleted");
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _saveCloudBackupLocally() async {
    try {
      final file = await _syncService.saveLatestCloudBackupToDownloads();
      if (!mounted) return;
      _showMessage("Cloud backup saved to ${file.path}");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _syncService.isBusy || _isLoading;
    final email = _syncService.email ?? 'No Google account';

    return Scaffold(
      appBar: AppBar(title: const Text("Manage My Cloud Data")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: const Icon(Icons.cloud_done_outlined),
                    ),
                    title: Text(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      "Last cloud backup: ${_formatCloudDate(_backupInfo?.modifiedTime)}\n${_formatBackupSize(_backupInfo?.sizeBytes)}",
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy || _backupInfo == null
                          ? null
                          : _saveCloudBackupLocally,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text("Save Cloud Backup Locally"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy || _backupInfo == null
                          ? null
                          : _deleteCloudBackup,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text("Delete Cloud Backup"),
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountsAndBackupScreen extends StatefulWidget {
  const AccountsAndBackupScreen({super.key});

  @override
  State<AccountsAndBackupScreen> createState() =>
      _AccountsAndBackupScreenState();
}

class _AccountsAndBackupScreenState extends State<AccountsAndBackupScreen> {
  final _syncService = AccountSyncService.instance;

  CloudBackupInfo? _cloudBackupInfo;
  bool _isLocalBackupBusy = false;
  bool _canMoveLocalData = false;
  bool _isCheckingLocalData = true;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_handleSyncChanged);
    _loadGoogleSignInConfiguration();
    _loadCloudBackupInfo();
    _refreshLocalMoveState();
    _runScheduledCloudBackup();
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

  Future<void> _loadGoogleSignInConfiguration() async {
    await _syncService.loadConfiguration();
  }

  Future<void> _refreshLocalMoveState() async {
    if (!_syncService.isSignedIn) {
      if (!mounted) return;
      setState(() {
        _canMoveLocalData = false;
        _isCheckingLocalData = false;
      });
      return;
    }

    setState(() {
      _isCheckingLocalData = true;
    });

    final hasLocalData = await _syncService.hasLocalDeviceData;
    final activeHasData = await _syncService.activeProfileHasData;
    final dismissed = await _syncService.isLocalDataMoveDismissed();
    if (!mounted) return;
    setState(() {
      _canMoveLocalData = hasLocalData && !activeHasData && !dismissed;
      _isCheckingLocalData = false;
    });
  }

  Future<void> _runScheduledCloudBackup() async {
    final info = await _syncService.runScheduledBackupIfDue();
    if (!mounted || info == null) return;
    setState(() {
      _cloudBackupInfo = info;
    });
    _showMessage("Automatic cloud backup saved");
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatCloudDate(DateTime? value) {
    if (value == null) return 'No cloud backup yet';
    return DateFormat('MMM d, yyyy h:mm a').format(value.toLocal());
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _syncService.signIn();
      await _loadCloudBackupInfo();
      await _refreshLocalMoveState();
      await _runScheduledCloudBackup();
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
    await _refreshLocalMoveState();
    if (!mounted) return;
    _showMessage("Signed out");
  }

  Future<void> _changeGoogleAccount() async {
    try {
      await _syncService.signOut();
      await _loadCloudBackupInfo();
      await _refreshLocalMoveState();
      await _syncService.signIn();
      await _loadCloudBackupInfo();
      await _refreshLocalMoveState();
      await _runScheduledCloudBackup();
      if (!mounted) return;
      _showMessage("Signed in as ${_syncService.email}");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
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

  Future<void> _moveLocalDataToAccount() async {
    final email = _syncService.email ?? 'this account';
    final shouldMove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Move local data?"),
          content: Text(
            "This will move the products, customers, bills, sales, and returns currently stored on this device into $email. The local database will be archived on this device as a recovery copy.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Move Data"),
            ),
          ],
        );
      },
    );

    if (shouldMove != true) return;

    try {
      final archiveFile = await _syncService
          .moveLocalDeviceDataToSignedInAccount();
      await AppSettingsController.instance.reload();
      await _loadCloudBackupInfo();
      await _refreshLocalMoveState();
      if (!mounted) return;
      _showMessage("Local data moved. Recovery copy: ${archiveFile.path}");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _keepLocalDataSeparate() async {
    await _syncService.keepLocalDeviceDataSeparate();
    await _refreshLocalMoveState();
    if (!mounted) return;
    _showMessage("Local device data will stay separate");
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
      await AppSettingsController.instance.reload();
      await _refreshLocalMoveState();
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

  Future<void> _openCloudDataManager() async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CloudDataManagementScreen()),
    );

    if (!mounted || deleted != true) return;
    await _loadCloudBackupInfo();
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

  Future<void> _backupData() async {
    final action = await _pickBackupAction();
    if (action == null) return;

    setState(() {
      _isLocalBackupBusy = true;
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
          _isLocalBackupBusy = false;
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
      _isLocalBackupBusy = true;
    });

    try {
      await DatabaseHelper.instance.restoreDatabaseFromFile(selectedPath);
      await AppSettingsController.instance.reload();
      await _refreshLocalMoveState();

      if (!mounted) return;
      _showMessage("Backup restored successfully");
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLocalBackupBusy = false;
        });
      }
    }
  }

  Future<void> _changeAutomaticBackupFrequency(String? value) async {
    if (value == null) return;
    await _syncService.setAutomaticBackupFrequency(value);
    if (!mounted) return;
    _showMessage(
      "Automatic cloud backups set to ${_backupFrequencyLabel(value)}",
    );
    await _runScheduledCloudBackup();
  }

  Future<void> _changeCloudBackupNetwork(String? value) async {
    if (value == null) return;
    await _syncService.setCloudBackupNetwork(value);
    if (!mounted) return;
    _showMessage("Cloud backup network set to ${_backupNetworkLabel(value)}");
    await _runScheduledCloudBackup();
  }

  String _backupFrequencyLabel(String value) {
    switch (value) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      default:
        return 'Off';
    }
  }

  String _backupNetworkLabel(String value) {
    switch (value) {
      case 'wifi':
        return 'Wi-Fi only';
      case 'mobile':
        return 'Mobile data only';
      default:
        return 'Any network';
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
    final hasClientId = _syncService.hasConfiguredWebClientId;
    final name = _syncService.displayName?.trim() ?? '';
    final email = _syncService.email ?? '';
    final title = signedIn
        ? (name.isEmpty ? email : name)
        : "No Google account connected";
    final subtitle = signedIn
        ? "$email\nLast cloud backup: ${_formatCloudDate(_cloudBackupInfo?.modifiedTime)}"
        : "Sign in with Google to save and restore this device's data from your account.";

    return _buildSection(
      title: "Google Account",
      subtitle: "Save and restore data with Google Drive app data",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            isThreeLine: signedIn,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              subtitle,
              maxLines: signedIn ? 3 : 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: signedIn
                ? IconButton(
                    onPressed: busy ? null : _changeGoogleAccount,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: "Change Google account",
                  )
                : null,
          ),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  signedIn
                      ? Icons.folder_shared_outlined
                      : Icons.phone_android_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    signedIn
                        ? "Active data profile: ${_syncService.dataProfileLabel}. Products, customers, bills, and sales stay separate for this account."
                        : "Active data profile: local device data. Sign in to switch to that Google account's separate app data.",
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (signedIn && _isCheckingLocalData) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (signedIn && _canMoveLocalData) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Local device data found",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Move existing local products, customers, bills, and sales into this Google account, keep them separate, or restore this account from Google Drive.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: busy ? null : _moveLocalDataToAccount,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: const Text("Move Local Data"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _restoreFromCloud,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text("Restore from Google"),
                  ),
                  TextButton(
                    onPressed: busy ? null : _keepLocalDataSeparate,
                    child: const Text("Keep Separate"),
                  ),
                ],
              ),
            ),
          ],
          if (!hasClientId && !signedIn)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                "Google sign-in is not configured for this build.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          if (!signedIn)
            ElevatedButton.icon(
              onPressed: busy || !hasClientId ? null : _signInWithGoogle,
              icon: const Icon(Icons.login_rounded),
              label: const Text("Sign in with Google"),
            )
          else ...[
            ElevatedButton.icon(
              onPressed: busy ? null : _backupToCloud,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text("Save Backup to Google"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : _restoreFromCloud,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text("Restore from Google"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : _openCloudDataManager,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text("Manage My Cloud Data"),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: busy ? null : _signOutFromGoogle,
              icon: const Icon(Icons.logout_rounded),
              label: const Text("Sign Out"),
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

  Widget _buildBackupSettingsSection() {
    final busy = _syncService.isBusy;

    return _buildSection(
      title: "Automatic Backup Settings",
      subtitle: "Choose when and how Google Drive backups are uploaded",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _syncService.automaticBackupFrequency,
            decoration: const InputDecoration(
              labelText: "Automatic cloud backup",
            ),
            items: const [
              DropdownMenuItem(value: 'off', child: Text("Off")),
              DropdownMenuItem(value: 'daily', child: Text("Daily")),
              DropdownMenuItem(value: 'weekly', child: Text("Weekly")),
            ],
            onChanged: busy ? null : _changeAutomaticBackupFrequency,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _syncService.cloudBackupNetwork,
            decoration: const InputDecoration(labelText: "Backup network"),
            items: const [
              DropdownMenuItem(value: 'any', child: Text("Any network")),
              DropdownMenuItem(value: 'wifi', child: Text("Wi-Fi only")),
              DropdownMenuItem(
                value: 'mobile',
                child: Text("Mobile data only"),
              ),
            ],
            onChanged: busy ? null : _changeCloudBackupNetwork,
          ),
          const SizedBox(height: 12),
          Text(
            _syncService.lastAutomaticBackupAt == null
                ? "Automatic backups run when the signed-in app is opened and Drive permission is already available."
                : "Last automatic backup: ${_formatCloudDate(_syncService.lastAutomaticBackupAt)}",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBackupSection() {
    return _buildSection(
      title: "Local Backup",
      subtitle:
          "Create a device backup file or restore from an existing backup",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _isLocalBackupBusy ? null : _backupData,
            icon: const Icon(Icons.backup_outlined),
            label: const Text("Take Local Backup"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLocalBackupBusy ? null : _restoreData,
            icon: const Icon(Icons.restore_rounded),
            label: const Text("Restore Local Backup"),
          ),
          if (_isLocalBackupBusy) ...[
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
      appBar: AppBar(title: const Text("Accounts and Backup")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAccountSection(),
          _buildLocalBackupSection(),
          _buildBackupSettingsSection(),
        ],
      ),
    );
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = AppSettingsController.instance;

  Map<String, String> _storeDetails = {};

  @override
  void initState() {
    super.initState();
    _loadStoreDetails();
  }

  @override
  void dispose() {
    super.dispose();
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

  Future<void> _openAccountsAndBackup() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountsAndBackupScreen()));
    await _controller.reload();
    await _loadStoreDetails();
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalControl(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        );
      },
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
                title: "Accounts and Backup",
                subtitle:
                    "Google sign-in, cloud backup, restore, and data controls",
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openAccountsAndBackup,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text("Accounts and Backup"),
                  ),
                ),
              ),
              _buildSection(
                title: "Appearance",
                subtitle: "Change how the application looks",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHorizontalControl(
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
                    _buildHorizontalControl(
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
                            label: Text("Percent"),
                          ),
                        ],
                        selected: {defaultDiscountMode},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          _controller.setDefaultDiscountMode(selection.first);
                        },
                        showSelectedIcon: false,
                      ),
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
