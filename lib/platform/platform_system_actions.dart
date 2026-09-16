/// Application-owned entry points for system intents.
///
/// OHOS cannot use the standard url_launcher platform implementation in this
/// project, so external links cross the native channel here. Other platforms
/// retain url_launcher's existing behavior.
library;

import 'package:url_launcher/url_launcher.dart';

import 'package:mg_read/platform/platform_capabilities.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

Future<bool> openExternalUri(Uri uri) {
  if (platformCapabilities.isOhos) return OhosSystemClient.openUri(uri);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
