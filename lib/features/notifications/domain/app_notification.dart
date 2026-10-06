import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.relatedEntityId,
    this.relatedEntityType,
    this.readAt,
  });

  final String id;
  final String recipientId;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime createdAt;
  final String? relatedEntityId;

  /// 'woman' | 'suggestion' | 'conference' | 'meeting'
  final String? relatedEntityType;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) =>
      AppNotification(
        id: id,
        recipientId: (m['recipientId'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        type: NotificationType.fromWire(m['type'] as String?),
        createdAt: tsToDate(m['createdAt']) ?? DateTime.now(),
        relatedEntityId: m['relatedEntityId'] as String?,
        relatedEntityType: m['relatedEntityType'] as String?,
        readAt: tsToDate(m['readAt']),
      );
}
