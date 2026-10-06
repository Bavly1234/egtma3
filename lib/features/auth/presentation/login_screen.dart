import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../data/auth_repository.dart';
import 'splash_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await runGuarded(context,
        () => ref.read(authRepositoryProvider).signIn(_email.text, _password.text));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgot() async {
    final ctrl = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نسيت كلمة المرور'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اكتبي بريدك الإلكتروني وسنرسل لك رابطاً لتغيير كلمة المرور.'),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
        ]),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('إرسال')),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).sendPasswordReset(email),
      successMessage: 'تم إرسال الرابط إلى بريدك الإلكتروني.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AppLogo(size: 96)),
                      const SizedBox(height: 16),
                      Text('اجتماع السيدات',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text('تسجيل الدخول',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 19, color: AppColors.textMuted)),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'اكتبي البريد الإلكتروني بشكل صحيح'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'إظهار' : 'إخفاء',
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'اكتبي كلمة المرور'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white))
                            : const Icon(Icons.login),
                        label: const Text('دخول'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _forgot,
                          child: const Text('نسيت كلمة المرور؟')),
                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: () => context.go(Routes.setup),
                        icon: const Icon(Icons.settings_suggest),
                        label: const Text('الإعداد الأول (للأب الكاهن)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
