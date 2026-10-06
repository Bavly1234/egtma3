import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../theme/app_theme.dart';

/// Success / error messages in large, clear Arabic.
abstract final class AppToast {
  static void success(BuildContext context, String message) =>
      _show(context, message, AppColors.present, Icons.check_circle);

  static void error(BuildContext context, Object error) => _show(
        context,
        error is AppFailure ? error.message : AppFailure.from(error).message,
        AppColors.absent,
        Icons.error,
      );

  static void info(BuildContext context, String message) =>
      _show(context, message, AppColors.primary, Icons.info);

  static void _show(
      BuildContext context, String msg, Color color, IconData icon) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      backgroundColor: color,
      duration: const Duration(seconds: 4),
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text(msg)),
      ]),
    ));
  }
}

/// Confirmation before any destructive or important action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.absent)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs [action] showing errors as friendly messages; returns success.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  try {
    await action();
    if (successMessage != null && context.mounted) {
      AppToast.success(context, successMessage);
    }
    return true;
  } catch (e) {
    if (context.mounted) AppToast.error(context, e);
    return false;
  }
}
