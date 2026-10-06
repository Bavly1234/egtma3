import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../errors/app_failure.dart';
import '../utils/phone.dart';

/// Opens the dialer / WhatsApp. Never sends anything automatically.
class ContactLauncher {
  Future<void> call(String phone) async {
    final uri = Uri(scheme: 'tel', path: PhoneUtils.normalize(phone));
    if (!await launchUrl(uri)) {
      throw const AppFailure('تعذر فتح الاتصال على هذا الجهاز.');
    }
  }

  Future<void> whatsApp(String phone) async {
    final n = PhoneUtils.normalize(phone);
    if (!PhoneUtils.isValidMobile(n)) {
      throw const AppFailure('هذا الرقم ليس رقم موبايل صالح لواتساب.');
    }
    final uri = Uri.parse('https://wa.me/${PhoneUtils.toInternational(n)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const AppFailure('تعذر فتح واتساب. تأكدي أنه مثبت على الجهاز.');
    }
  }
}

final contactLauncherProvider = Provider((ref) => ContactLauncher());
