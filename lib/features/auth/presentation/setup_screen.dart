import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../users/data/users_repository.dart';
import '../data/auth_repository.dart';

/// One-time setup of the first father account. Requires the secret
/// BOOTSTRAP_CODE configured on Cloud Functions, and only works while no
/// father exists — so it cannot be used to escalate privileges later.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = ref.read(firebaseAuthProvider);
    final ok = await runGuarded(context, () async {
      if (auth.currentUser == null) {
        try {
          await auth.createUserWithEmailAndPassword(
              email: _email.text.trim(), password: _password.text);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          await auth.signInWithEmailAndPassword(
              email: _email.text.trim(), password: _password.text);
        }
      }
      await ref
          .read(usersRepositoryProvider)
          .bootstrapFather(_code.text.trim(), _name.text.trim());
    }, successMessage: 'تم إعداد حساب الأب الكاهن بنجاح.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider).value != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعداد الأول'),
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => context.go(Routes.login),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: AppColors.goldLight,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      'هذه الصفحة لإنشاء حساب الأب الكاهن لأول مرة فقط. '
                      'تحتاج إلى "رمز الإعداد" الموجود في إعدادات الخادم.',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'الاسم', prefixIcon: Icon(Icons.person)),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 3 ? 'اكتب الاسم' : null,
                  ),
                  if (!signedIn) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icon(Icons.email)),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'البريد غير صحيح'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور (8 أحرف على الأقل)',
                          prefixIcon: Icon(Icons.lock)),
                      validator: (v) => (v?.length ?? 0) < 8
                          ? 'كلمة المرور قصيرة'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _code,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'رمز الإعداد', prefixIcon: Icon(Icons.key)),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'اكتب رمز الإعداد' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: const Icon(Icons.check),
                    label: const Text('إنشاء حساب الأب الكاهن'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
