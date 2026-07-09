import 'package:flutter/material.dart';

import '../app_settings_controller.dart';
import '../services/onboarding_service.dart';
import 'home_screen.dart';
import 'store_details_screen.dart';
import 'welcome_screen.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _isLoading = true;
  bool _showWelcome = false;
  bool _storePromptQueued = false;

  @override
  void initState() {
    super.initState();
    _loadStartupState();
  }

  Future<void> _loadStartupState() async {
    final onboarded = await OnboardingService.isOnboardingComplete();
    final storeSetupDone = await OnboardingService.isStoreSetupComplete();
    if (!mounted) return;

    setState(() {
      _showWelcome = !onboarded;
      _isLoading = false;
    });

    if (onboarded && !storeSetupDone) {
      _queueStoreDetails();
    }
  }

  void _queueStoreDetails() {
    if (_storePromptQueued) return;
    _storePromptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openStoreDetails();
      }
    });
  }

  Future<void> _openStoreDetails() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const StoreDetailsScreen(isOnboarding: true),
      ),
    );
    await OnboardingService.markStoreSetupComplete();
    await AppSettingsController.instance.reload();
  }

  Future<void> _handleWelcomeFinished() async {
    if (!mounted) return;
    setState(() {
      _showWelcome = false;
    });

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _openStoreDetails();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_showWelcome) {
      return WelcomeScreen(onFinished: _handleWelcomeFinished);
    }

    return const HomeScreen();
  }
}
