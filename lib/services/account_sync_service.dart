import 'dart:async';
import 'dart:io';

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
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  GoogleSignInAccount? _account;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  bool _initialized = false;
  bool _isBusy = false;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;
  bool get isBusy => _isBusy;
  String? get email => _account?.email;
  String? get displayName => _account?.displayName;
  String? get photoUrl => _account?.photoUrl;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await GoogleSignIn.instance.initialize(
      serverClientId: _webClientId.isEmpty ? null : _webClientId,
    );

    _authSubscription = GoogleSignIn.instance.authenticationEvents.listen((
      event,
    ) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          _account = event.user;
        case GoogleSignInAuthenticationEventSignOut():
          _account = null;
      }
      notifyListeners();
    }, onError: (_) {});

    if (_webClientId.isEmpty) return;
    final lightweight = GoogleSignIn.instance
        .attemptLightweightAuthentication();
    if (lightweight != null) {
      unawaited(_restoreLightweightAccount(lightweight));
    }
  }

  Future<void> _restoreLightweightAccount(
    Future<GoogleSignInAccount?> lightweight,
  ) async {
    try {
      _account = await lightweight;
      notifyListeners();
    } catch (_) {
      _account = null;
      notifyListeners();
    }
  }

  Future<void> signIn() async {
    await initialize();
    if (_webClientId.isEmpty) {
      throw Exception(
        'Google sign-in is not configured yet. Add GOOGLE_WEB_CLIENT_ID when running the app.',
      );
    }

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw Exception('Google sign-in is not supported on this platform.');
    }

    _setBusy(true);
    try {
      _account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      await _account!.authorizationClient.authorizeScopes(_scopes);
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
      _account = null;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
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
    final api = await _driveApi();
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

  Future<drive.DriveApi> _driveApi() async {
    await initialize();
    final user = _account;
    if (user == null) {
      throw Exception('Sign in with Google first.');
    }

    final headers = await user.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
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
