import 'package:flutter/foundation.dart';

enum AppFlavor { free, pro }

class AppFlavorConfig {
  const AppFlavorConfig({
    required this.flavor,
    required this.appTitle,
    required this.adsEnabled,
    required this.androidBannerAdUnitId,
    required this.iosBannerAdUnitId,
  });

  static const _androidTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosTestBannerId = 'ca-app-pub-3940256099942544/2934735716';

  static AppFlavorConfig? _instance;

  final AppFlavor flavor;
  final String appTitle;
  final bool adsEnabled;
  final String androidBannerAdUnitId;
  final String iosBannerAdUnitId;

  static AppFlavorConfig get instance {
    final config = _instance;
    if (config == null) {
      throw StateError('AppFlavorConfig has not been initialized');
    }
    return config;
  }

  static void initialize(AppFlavorConfig config) {
    _instance = config;
  }

  bool get isFree => flavor == AppFlavor.free;
  bool get isPro => flavor == AppFlavor.pro;

  String bannerAdUnitIdForPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return androidBannerAdUnitId;
      case TargetPlatform.iOS:
        return iosBannerAdUnitId;
      default:
        return '';
    }
  }

  factory AppFlavorConfig.free() {
    return const AppFlavorConfig(
      flavor: AppFlavor.free,
      appTitle: 'Sale Buddy',
      adsEnabled: true,
      androidBannerAdUnitId: String.fromEnvironment(
        'ADMOB_ANDROID_BANNER_ID',
        defaultValue: _androidTestBannerId,
      ),
      iosBannerAdUnitId: String.fromEnvironment(
        'ADMOB_IOS_BANNER_ID',
        defaultValue: _iosTestBannerId,
      ),
    );
  }

  factory AppFlavorConfig.pro() {
    return const AppFlavorConfig(
      flavor: AppFlavor.pro,
      appTitle: 'Sale Buddy Pro',
      adsEnabled: false,
      androidBannerAdUnitId: '',
      iosBannerAdUnitId: '',
    );
  }
}
