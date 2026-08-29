import 'package:package_info_plus/package_info_plus.dart';

abstract interface class AppVersionProvider {
  Future<String> load();
}

class PackageInfoAppVersionProvider implements AppVersionProvider {
  @override
  Future<String> load() async {
    final info = await PackageInfo.fromPlatform();
    final value = info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
    return value.length <= 64 ? value : value.substring(0, 64);
  }
}
