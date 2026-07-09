import 'package:flutter/material.dart';

import '../app_settings_controller.dart';
import '../services/account_sync_service.dart';
import '../services/onboarding_service.dart';
import 'legal_consent.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _syncService = AccountSyncService.instance;
  bool _isBusy = false;
  bool _legalAccepted = false;

  @override
  void initState() {
    super.initState();
    _loadLegalAcceptance();
  }

  Future<void> _loadLegalAcceptance() async {
    final accepted = await OnboardingService.hasAcceptedLegalTerms();
    if (!mounted) return;
    setState(() {
      _legalAccepted = accepted;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continueWithGoogle() async {
    if (!_legalAccepted) {
      _showMessage("Accept the terms before signing in.");
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await _syncService.signIn();
      await OnboardingService.acceptLegalTerms();
      await OnboardingService.completeWithGoogle();
      await AppSettingsController.instance.reload();
      if (!mounted) return;
      widget.onFinished();
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

  Future<void> _continueLocally() async {
    if (!_legalAccepted) {
      _showMessage("Accept the terms before continuing.");
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      if (_syncService.isSignedIn) {
        await _syncService.signOut();
      }
      await OnboardingService.acceptLegalTerms();
      await OnboardingService.completeWithoutAccount();
      await AppSettingsController.instance.reload();
      if (!mounted) return;
      widget.onFinished();
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

  Widget _buildFeatureChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/branding/sale_buddy_icon.png',
                  height: 62,
                  width: 62,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    "Sale Buddy",
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              "Run your shop from one simple place.",
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              "Track products, stock, sales, bills, returns, customers, and backups with account-based data when you need it.",
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildFeatureChip(
                  icon: Icons.receipt_long_outlined,
                  label: "Bills",
                  color: colorScheme.primary,
                ),
                _buildFeatureChip(
                  icon: Icons.inventory_2_outlined,
                  label: "Inventory",
                  color: colorScheme.tertiary,
                ),
                _buildFeatureChip(
                  icon: Icons.cloud_done_outlined,
                  label: "Cloud backup",
                  color: colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Choose how to start",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Google keeps each account's data separate. Local mode stores data only on this device.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    LegalConsentCard(
                      accepted: _legalAccepted,
                      onChanged: (value) {
                        setState(() {
                          _legalAccepted = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _isBusy || !_legalAccepted
                          ? null
                          : _continueWithGoogle,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(
                        _isBusy
                            ? "Please wait..."
                            : "Sign in or Sign up with Google",
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isBusy || !_legalAccepted
                          ? null
                          : _continueLocally,
                      icon: const Icon(Icons.phone_android_rounded),
                      label: const Text("Continue without account"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "You can connect or change your Google account later from Accounts.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
