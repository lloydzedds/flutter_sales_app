import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';

class AccountSyncService extends ChangeNotifier {
  AccountSyncService._();

  static final AccountSyncService instance = AccountSyncService._();

  static const _backupFileName = 'sale_buddy_sales.db';
  static const _scopes = <String>[drive.DriveApi.driveAppdataScope];
  static const _autoBackupFrequencyKey = 'auto_cloud_backup_frequency';
  static const _autoBackupNetworkKey = 'cloud_backup_network';
  static const _lastAutoBackupAtKey = 'last_auto_cloud_backup_at';
  static const _developmentWebClientId =
      '244833529337-7u9dh7p43iva3j5fdhad2nus2lbm9u0u.apps.googleusercontent.com';
  static const _bundledWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  GoogleSignInAccount? _account;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  bool _initialized = false;
  bool _isBusy = false;
  String _configuredWebClientId = '';
  String _automaticBackupFrequency = 'off';
  String _cloudBackupNetwork = 'any';
  DateTime? _lastAutomaticBackupAt;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;
  bool get isBusy => _isBusy;
  String? get email => _account?.email;
  String? get displayName => _account?.displayName;
  String? get photoUrl => _account?.photoUrl;
  String get configuredWebClientId => _configuredWebClientId;
  bool get hasConfiguredWebClientId => _configuredWebClientId.isNotEmpty;
  String get automaticBackupFrequency => _automaticBackupFrequency;
  String get cloudBackupNetwork => _cloudBackupNetwork;
  DateTime? get lastAutomaticBackupAt => _lastAutomaticBackupAt;
  String get dataProfileLabel => DatabaseHelper.instance.activeProfileLabel;
  String get dataProfileKey => DatabaseHelper.instance.activeProfileKey;

  Future<void> initialize() async {
    if (_initialized) return;
    _configuredWebClientId = await _loadConfiguredWebClientId();

    await GoogleSignIn.instance.initialize(
      serverClientId: _configuredWebClientId.isEmpty
          ? null
          : _configuredWebClientId,
    );
    _initialized = true;

    _authSubscription = GoogleSignIn.instance.authenticationEvents.listen((
      event,
    ) {
      unawaited(_handleAuthenticationEvent(event));
    }, onError: (_) {});

    final lightweightAuth = GoogleSignIn.instance
        .attemptLightweightAuthentication();
    if (lightweightAuth != null) {
      try {
        await _applyAccount(await lightweightAuth);
      } catch (_) {
        await _applyAccount(null);
      }
    } else {
      await _applyAccount(null);
    }
  }

  Future<void> signIn() async {
    _configuredWebClientId = await _loadConfiguredWebClientId();
    if (_configuredWebClientId.isEmpty) {
      throw Exception(
        'Google sign-in is not configured for this build. Add GOOGLE_WEB_CLIENT_ID when running or building the app.',
      );
    }

    await initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw Exception('Google sign-in is not supported on this platform.');
    }

    _setBusy(true);
    try {
      final account = await GoogleSignIn.instance.authenticate();
      await _applyAccount(account);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await initialize();
    _setBusy(true);
    try {
      await GoogleSignIn.instance.signOut();
      await _applyAccount(null);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _handleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        await _applyAccount(event.user);
      case GoogleSignInAuthenticationEventSignOut():
        await _applyAccount(null);
    }
    notifyListeners();
  }

  Future<void> _applyAccount(GoogleSignInAccount? account) async {
    _account = account;
    await DatabaseHelper.instance.setActiveAccountEmail(account?.email);
    await _loadProfileConfiguration();
  }

  Future<CloudBackupInfo?> getLatestBackupInfo() async {
    final api = await _driveApi();
    final file = await _latestBackupFile(api);
    if (file == null) return null;
    return CloudBackupInfo(
      fileId: file.id ?? '',
      modifiedTime: file.modifiedTime,
      sizeBytes: int.tryParse(file.size ?? ''),
    );
  }

  Future<CloudBackupInfo> uploadCurrentDatabase() async {
    return _uploadCurrentDatabase(promptIfNecessary: true);
  }

  Future<CloudBackupInfo> _uploadCurrentDatabase({
    required bool promptIfNecessary,
  }) async {
    await _ensureBackupNetworkAllowed();
    final api = await _driveApi(promptIfNecessary: promptIfNecessary);
    _setBusy(true);
    try {
      final tempDirectory = await getTemporaryDirectory();
      final backupFile = await DatabaseHelper.instance.createBackup(
        '${tempDirectory.path}/$_backupFileName',
      );
      final media = drive.Media(
        backupFile.openRead(),
        await backupFile.length(),
        contentType: 'application/x-sqlite3',
      );
      final metadata = drive.File()
        ..name = _backupFileName
        ..parents = ['appDataFolder'];

      final existing = await _latestBackupFile(api);
      final savedFile = existing?.id == null
          ? await api.files.create(
              metadata,
              uploadMedia: media,
              $fields: 'id,modifiedTime,size',
            )
          : await api.files.update(
              drive.File()..name = _backupFileName,
              existing!.id!,
              uploadMedia: media,
              $fields: 'id,modifiedTime,size',
            );

      return CloudBackupInfo(
        fileId: savedFile.id ?? '',
        modifiedTime: savedFile.modifiedTime,
        sizeBytes: int.tryParse(savedFile.size ?? ''),
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<CloudBackupInfo> restoreLatestDatabase() async {
    final api = await _driveApi();
    _setBusy(true);
    try {
      final latest = await _latestBackupFile(api);
      if (latest?.id == null) {
        throw Exception(
          'No cloud backup found for ${email ?? 'this account'}.',
        );
      }

      final media =
          await api.files.get(
                latest!.id!,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;
      final tempDirectory = await getTemporaryDirectory();
      final restoreFile = File(
        '${tempDirectory.path}/restore_$_backupFileName',
      );
      final sink = restoreFile.openWrite();
      await media.stream.pipe(sink);

      await DatabaseHelper.instance.restoreDatabaseFromFile(restoreFile.path);
      return CloudBackupInfo(
        fileId: latest.id ?? '',
        modifiedTime: latest.modifiedTime,
        sizeBytes: int.tryParse(latest.size ?? ''),
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<File> saveLatestCloudBackupToDownloads() async {
    final api = await _driveApi();
    _setBusy(true);
    try {
      final latest = await _latestBackupFile(api);
      if (latest?.id == null) {
        throw Exception(
          'No cloud backup found for ${email ?? 'this account'}.',
        );
      }

      final media =
          await api.files.get(
                latest!.id!,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;
      final directory = await _downloadsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      final file = File(
        '${directory.path}/sale_buddy_cloud_backup_$timestamp.db',
      );
      final sink = file.openWrite();
      await media.stream.pipe(sink);
      return file;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteLatestCloudBackup() async {
    final api = await _driveApi();
    _setBusy(true);
    try {
      final latest = await _latestBackupFile(api);
      if (latest?.id == null) {
        throw Exception(
          'No cloud backup found for ${email ?? 'this account'}.',
        );
      }

      await api.files.delete(latest!.id!);
    } finally {
      _setBusy(false);
    }
  }

  Future<Directory> _downloadsDirectory() async {
    Directory? directory = await getDownloadsDirectory();
    if (directory == null && Platform.isAndroid) {
      directory = Directory('/storage/emulated/0/Download');
    }
    directory ??= await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<drive.DriveApi> _driveApi({bool promptIfNecessary = true}) async {
    await initialize();
    final user = _account;
    if (user == null) {
      throw Exception('Sign in with Google first.');
    }

    final headers = await user.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: promptIfNecessary,
    );
    if (headers == null) {
      throw Exception('Google Drive permission was not granted.');
    }

    return drive.DriveApi(_GoogleAuthClient(headers));
  }

  Future<drive.File?> _latestBackupFile(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_backupFileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime,size)',
    );
    final files = result.files ?? const <drive.File>[];
    if (files.isEmpty) return null;
    return files.first;
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  Future<void> loadConfiguration() async {
    await _loadProfileConfiguration();
    notifyListeners();
  }

  Future<void> _loadProfileConfiguration() async {
    final value = await _loadConfiguredWebClientId();
    final frequency = await DatabaseHelper.instance.getAppSetting(
      _autoBackupFrequencyKey,
    );
    final network = await DatabaseHelper.instance.getAppSetting(
      _autoBackupNetworkKey,
    );
    final lastBackup = await DatabaseHelper.instance.getAppSetting(
      _lastAutoBackupAtKey,
    );
    _configuredWebClientId = value;
    _automaticBackupFrequency = _normalizeFrequency(frequency);
    _cloudBackupNetwork = _normalizeNetwork(network);
    _lastAutomaticBackupAt = DateTime.tryParse(lastBackup ?? '');
  }

  Future<void> setAutomaticBackupFrequency(String value) async {
    _automaticBackupFrequency = _normalizeFrequency(value);
    await DatabaseHelper.instance.saveAppSetting(
      _autoBackupFrequencyKey,
      _automaticBackupFrequency,
    );
    notifyListeners();
  }

  Future<void> setCloudBackupNetwork(String value) async {
    _cloudBackupNetwork = _normalizeNetwork(value);
    await DatabaseHelper.instance.saveAppSetting(
      _autoBackupNetworkKey,
      _cloudBackupNetwork,
    );
    notifyListeners();
  }

  Future<CloudBackupInfo?> runScheduledBackupIfDue() async {
    await loadConfiguration();
    if (!isSignedIn || _automaticBackupFrequency == 'off' || _isBusy) {
      return null;
    }

    final now = DateTime.now();
    final last = _lastAutomaticBackupAt;
    final dueAfter = _automaticBackupFrequency == 'weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);
    if (last != null && now.difference(last) < dueAfter) {
      return null;
    }

    try {
      final info = await _uploadCurrentDatabase(promptIfNecessary: false);
      _lastAutomaticBackupAt = now;
      await DatabaseHelper.instance.saveAppSetting(
        _lastAutoBackupAtKey,
        now.toIso8601String(),
      );
      notifyListeners();
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<String> _loadConfiguredWebClientId() async {
    final bundledValue = _bundledWebClientId.trim();
    if (bundledValue.isNotEmpty) return bundledValue;
    return _developmentWebClientId;
  }

  String _normalizeFrequency(String? value) {
    switch (value) {
      case 'daily':
      case 'weekly':
      case 'off':
        return value!;
      default:
        return 'off';
    }
  }

  String _normalizeNetwork(String? value) {
    switch (value) {
      case 'wifi':
      case 'mobile':
      case 'any':
        return value!;
      default:
        return 'any';
    }
  }

  Future<void> _ensureBackupNetworkAllowed() async {
    final network = _normalizeNetwork(_cloudBackupNetwork);
    final results = await Connectivity().checkConnectivity();
    final hasConnection = !results.contains(ConnectivityResult.none);
    if (!hasConnection) {
      throw Exception('No internet connection available for cloud backup.');
    }

    if (network == 'any') return;
    if (network == 'wifi' && results.contains(ConnectivityResult.wifi)) return;
    if (network == 'mobile' && results.contains(ConnectivityResult.mobile)) {
      return;
    }

    throw Exception(
      network == 'wifi'
          ? 'Cloud backup is set to Wi-Fi only. Connect to Wi-Fi or change the backup network setting.'
          : 'Cloud backup is set to mobile data only. Connect to mobile data or change the backup network setting.',
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

class CloudBackupInfo {
  const CloudBackupInfo({
    required this.fileId,
    this.modifiedTime,
    this.sizeBytes,
  });

  final String fileId;
  final DateTime? modifiedTime;
  final int? sizeBytes;
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
