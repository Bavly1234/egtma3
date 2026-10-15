import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_logger.dart';

/// "فيه نسخة جديدة" for the Android app (not from the Play Store).
///
/// `tool/release.sh` publishes `app_update.json` on the website (the free
/// plan does not allow hosting the APK itself, so the APK link points to
/// Google Drive). Each phone compares its build number with the published
/// one and, if older, offers to download the new APK. Android installs it OVER the
/// old app (same id + same signing key), so all data and logins are kept.
abstract final class UpdateChecker {
  static const versionUrl = 'https://egtma3-church-app.web.app/app_update.json';
  static bool _checked = false;

  static Future<void> checkOnce(BuildContext context) async {
    if (kIsWeb || _checked) return; // the website is always the newest
    _checked = true;
    try {
      final res = await http
          .get(Uri.parse('$versionUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final info = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final latest = (info['build'] as num?)?.toInt() ?? 0;
      final current = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      if (latest <= current || !context.mounted) return;
      final apk = info['apk'] as String? ?? '';
      if (apk.isEmpty) return;
      await _show(context, apk, info['notes'] as String? ?? '',
          info['version'] as String? ?? '');
    } catch (e) {
      AppLog.w('Update check failed', e); // offline: try next time
    }
  }

  static Future<void> _show(
      BuildContext context, String apkUrl, String notes, String version) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🎉 فيه نسخة جديدة من البرنامج'),
          content: Text(
            '${notes.isEmpty ? '' : '$notes\n\n'}'
            'اضغطي "حدّث دلوقتي"، وبعد ما الملف يتحمل افتحيه واضغطي "تحديث". '
            'كل البيانات هتفضل زي ما هي.'
            '${version.isEmpty ? '' : '\n\n(النسخة $version)'}',
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('بعدين')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.system_update),
              label: const Text('حدّث دلوقتي'),
            ),
          ],
        ),
      );
}
