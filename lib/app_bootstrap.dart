import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_flavor.dart';
import 'app_settings_controller.dart';
import 'app.dart';

Future<void> runSaleBuddy(AppFlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFlavorConfig.initialize(config);
  await AppSettingsController.instance.load();

  final shouldInitializeAds =
      config.adsEnabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  if (shouldInitializeAds) {
    await MobileAds.instance.initialize();
  }

  runApp(
    MyApp(controller: AppSettingsController.instance, title: config.appTitle),
  );
}
