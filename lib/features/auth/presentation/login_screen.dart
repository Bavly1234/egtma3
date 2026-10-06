import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../data/auth_repository.dart';
import 'splash_screen.dart';

/// Login + self sign-up with the join code (كود الانضمام), like eftekad_app.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  UserRole? _role; // must be chosen explicitly
  bool _obscure = true;
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
    if (_register && _role == null) {
      AppToast.error(context, 'اختاري: خادمة أم الأب الكاهن');
      return;
    }
    setState(() => _busy = true);
    final auth = ref.read(authRepositoryProvider);
    await runGuarded(
      context,
      () => _register
          ? auth.signUp(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              role: _role!,
              code: _code.text,
            )
          : auth.signIn(_email.text, _password.text),
    );
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
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('إرسال')),
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

  Widget _roleCard(UserRole r, String label, IconData icon) {
    final selected = _role == r;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      onTap: () => setState(() => _role = r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 36, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
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
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('تسجيل الدخول'), icon: Icon(Icons.login)),
                          ButtonSegment(value: true, label: Text('حساب جديد'), icon: Icon(Icons.person_add)),
                        ],
                        selected: {_register},
                        onSelectionChanged: (s) => setState(() => _register = s.first),
                      ),
                      const SizedBox(height: 24),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                              labelText: 'الاسم', prefixIcon: Icon(Icons.person)),
                          validator: (v) =>
                              (v?.trim().length ?? 0) < 3 ? 'اكتبي الاسم' : null,
                        ),
                        gap,
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email)),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'اكتبي البريد الإلكتروني بشكل صحيح'
                            : null,
                      ),
                      gap,
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textDirection: TextDirection.ltr,
                        autofillHints: [
                          _register ? AutofillHints.newPassword : AutofillHints.password
                        ],
                        onFieldSubmitted: (_) => _register ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'إظهار' : 'إخفاء',
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'اكتبي كلمة المرور';
                          if (_register && v.length < 6) return '6 أحرف على الأقل';
                          return null;
                        },
                      ),
                      if (_register) ...[
                        gap,
                        Row(children: [
                          Expanded(child: _roleCard(UserRole.servant, 'خادمة', Icons.volunteer_activism)),
                          const SizedBox(width: 12),
                          Expanded(child: _roleCard(UserRole.father, 'الأب الكاهن', Icons.church)),
                        ]),
                        gap,
                        TextFormField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'كود الانضمام',
                            prefixIcon: Icon(Icons.key),
                            helperText: 'اطلبيه من الأب الكاهن',
                          ),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'اكتبي كود الانضمام' : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                            : Icon(_register ? Icons.person_add : Icons.login),
                        label: Text(_register ? 'إنشاء الحساب' : 'دخول'),
                      ),
                      if (!_register) ...[
                        const SizedBox(height: 12),
                        TextButton(onPressed: _forgot, child: const Text('نسيت كلمة المرور؟')),
                      ],
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
