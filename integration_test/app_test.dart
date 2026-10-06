// Integration smoke test — runs on a device/emulator:
//   flutter test integration_test -d <deviceId>
// Requires the Firebase project configured (lib/firebase_options.dart).
import 'package:egtma3/app.dart';
import 'package:egtma3/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to the Arabic login screen when signed out', (t) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await initializeDateFormatting('ar');
    await t.pumpWidget(const ProviderScope(child: Egtma3App()));
    await t.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });
}
