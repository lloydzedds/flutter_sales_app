import 'dart:io';

import 'package:http/http.dart' as http;

class ClockValidationResult {
  const ClockValidationResult.valid()
    : isValid = true,
      trustedTime = null,
      deviceTime = null,
      difference = Duration.zero;

  const ClockValidationResult.invalid({
    required this.trustedTime,
    required this.deviceTime,
    required this.difference,
  }) : isValid = false;

  final bool isValid;
  final DateTime? trustedTime;
  final DateTime? deviceTime;
  final Duration difference;
}

class ClockValidationService {
  static const allowedSkew = Duration(minutes: 10);
  static final _timeEndpoint = Uri.parse('https://www.google.com/generate_204');

  static Future<ClockValidationResult> checkDeviceClock() async {
    try {
      final response = await http
          .head(_timeEndpoint)
          .timeout(const Duration(seconds: 5));
      final dateHeader = response.headers['date'];
      final trustedTime = dateHeader == null
          ? null
          : HttpDate.parse(dateHeader).toLocal();
      if (trustedTime == null) {
        return const ClockValidationResult.valid();
      }

      final deviceTime = DateTime.now();
      final difference = deviceTime.difference(trustedTime).abs();
      if (difference <= allowedSkew) {
        return const ClockValidationResult.valid();
      }

      return ClockValidationResult.invalid(
        trustedTime: trustedTime,
        deviceTime: deviceTime,
        difference: difference,
      );
    } catch (_) {
      return const ClockValidationResult.valid();
    }
  }
}
