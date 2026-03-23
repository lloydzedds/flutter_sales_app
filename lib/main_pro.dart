import 'app_bootstrap.dart';
import 'app_flavor.dart';

Future<void> main() async {
  await runSaleBuddy(AppFlavorConfig.pro());
}
