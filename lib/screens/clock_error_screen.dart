import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/clock_validation_service.dart';

class ClockGuard extends StatefulWidget {
  const ClockGuard({super.key, required this.child});

  final Widget child;

  @override
  State<ClockGuard> createState() => _ClockGuardState();
}

class _ClockGuardState extends State<ClockGuard> {
  ClockValidationResult _result = const ClockValidationResult.valid();
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkClock();
  }

  Future<void> _checkClock() async {
    setState(() {
      _checking = true;
    });
    final result = await ClockValidationService.checkDeviceClock();
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checking && !_result.isValid) {
      return ClockErrorScreen(result: _result, onRetry: _checkClock);
    }

    return widget.child;
  }
}

class ClockErrorScreen extends StatelessWidget {
  const ClockErrorScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  final ClockValidationResult result;
  final VoidCallback onRetry;

  String _formatDate(DateTime? value) {
    if (value == null) return 'Unavailable';
    return DateFormat('MMM d, yyyy h:mm a').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 72,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  "Incorrect date and time",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Sale Buddy cannot continue because your device date or time does not match internet time.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Device: ${_formatDate(result.deviceTime)}"),
                      const SizedBox(height: 6),
                      Text("Internet: ${_formatDate(result.trustedTime)}"),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("I Fixed It, Try Again"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
