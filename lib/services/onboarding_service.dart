import '../database/database_helper.dart';

class OnboardingService {
  OnboardingService._();

  static const _completedKey = 'onboarding_completed';
  static const _accountModeKey = 'onboarding_account_mode';
  static const _storeSetupKey = 'onboarding_store_setup_done';

  static Future<bool> isOnboardingComplete() async {
    final value = await DatabaseHelper.instance.getLocalAppSetting(
      _completedKey,
    );
    return value == 'true';
  }

  static Future<bool> shouldRestoreGoogleAccount() async {
    final completed = await isOnboardingComplete();
    if (!completed) return false;
    final mode = await DatabaseHelper.instance.getLocalAppSetting(
      _accountModeKey,
    );
    return mode == 'google';
  }

  static Future<void> completeWithGoogle() async {
    await DatabaseHelper.instance.saveLocalAppSetting(_completedKey, 'true');
    await DatabaseHelper.instance.saveLocalAppSetting(
      _accountModeKey,
      'google',
    );
  }

  static Future<void> completeWithoutAccount() async {
    await DatabaseHelper.instance.saveLocalAppSetting(_completedKey, 'true');
    await DatabaseHelper.instance.saveLocalAppSetting(_accountModeKey, 'local');
  }

  static Future<bool> isStoreSetupComplete() async {
    final value = await DatabaseHelper.instance.getLocalAppSetting(
      _storeSetupKey,
    );
    return value == 'true';
  }

  static Future<void> markStoreSetupComplete() async {
    await DatabaseHelper.instance.saveLocalAppSetting(_storeSetupKey, 'true');
  }
}
