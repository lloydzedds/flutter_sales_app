import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings_controller.dart';
import 'screens/clock_error_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettingsController.instance.load();
  runApp(MyApp(controller: AppSettingsController.instance));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.controller,
    this.home = const HomeScreen(),
  });

  final AppSettingsController controller;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Sale Buddy',
          debugShowCheckedModeBanner: false,
          themeMode: controller.themeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.14,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: ClockGuard(child: home),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    const scaffoldBackground = Color(0xFFF4F7FB);
    const surface = Color(0xFFFFFFFF);
    const primary = Color(0xFF0F766E);
    const secondary = Color(0xFFF59E0B);
    const tertiary = Color(0xFF2563EB);
    const text = Color(0xFF111827);
    const muted = Color(0xFF64748B);
    const border = Color(0xFFD8E0EA);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFCCFBF1),
        onPrimaryContainer: Color(0xFF134E4A),
        secondary: secondary,
        onSecondary: Color(0xFF1F2937),
        secondaryContainer: Color(0xFFFEF3C7),
        onSecondaryContainer: Color(0xFF78350F),
        tertiary: tertiary,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFDBEAFE),
        onTertiaryContainer: Color(0xFF1E3A8A),
        surface: surface,
        surfaceContainerLowest: scaffoldBackground,
        surfaceContainerHigh: Color(0xFFEAF0F7),
        onSurface: text,
        onSurfaceVariant: muted,
        outline: Color(0xFF9AA8BA),
        outlineVariant: border,
        error: Color(0xFFDC2626),
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: text,
        elevation: 0,
      ),
      pageTransitionsTheme: _buildPageTransitionsTheme(),
      iconTheme: const IconThemeData(color: tertiary),
      listTileTheme: const ListTileThemeData(
        iconColor: tertiary,
        selectedColor: primary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shadowColor: const Color(0x1A0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        labelStyle: const TextStyle(color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primary.withAlpha(28),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 25);
          }
          return const IconThemeData(color: tertiary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const scaffoldBackground = Color(0xFF101820);
    const surface = Color(0xFF18232F);
    const primary = Color(0xFF2DD4BF);
    const secondary = Color(0xFFFBBF24);
    const tertiary = Color(0xFF60A5FA);
    const border = Color(0xFF314255);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFF042F2E),
        primaryContainer: Color(0xFF134E4A),
        onPrimaryContainer: Color(0xFFCCFBF1),
        secondary: secondary,
        onSecondary: Color(0xFF422006),
        secondaryContainer: Color(0xFF78350F),
        onSecondaryContainer: Color(0xFFFEF3C7),
        tertiary: tertiary,
        onTertiary: Color(0xFF172554),
        tertiaryContainer: Color(0xFF1D4ED8),
        onTertiaryContainer: Color(0xFFDBEAFE),
        surface: surface,
        surfaceContainerLowest: scaffoldBackground,
        surfaceContainerHigh: Color(0xFF223142),
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFFB6C2D1),
        outline: Color(0xFF718197),
        outlineVariant: border,
        error: Color(0xFFF87171),
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      pageTransitionsTheme: _buildPageTransitionsTheme(),
      iconTheme: const IconThemeData(color: primary),
      listTileTheme: const ListTileThemeData(iconColor: primary),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primary.withAlpha(70),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 25);
          }
          return const IconThemeData(color: Color(0xFFB6C2D1), size: 24);
        }),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  PageTransitionsTheme _buildPageTransitionsTheme() {
    return const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    );
  }
}
