import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationItem {
  final String id;
  final String? senderId;
  final String targetType; // 'everyone', 'all_teachers', 'all_students', 'class', 'multi_class', 'teacher', 'student'
  final String? recipientId;
  final String? classId;
  final List<String> classIds;
  final String title;
  final String message;
  final String? linkUrl;
  final DateTime createdAt;
  final String? senderName;
  bool isRead;

  NotificationItem({
    required this.id,
    this.senderId,
    required this.targetType,
    this.recipientId,
    this.classId,
    this.classIds = const [],
    required this.title,
    required this.message,
    this.linkUrl,
    required this.createdAt,
    this.senderName,
    this.isRead = false,
  });

  factory NotificationItem.fromMap(Map<String, dynamic> map, {bool isRead = false}) {
    List<String> parsedClassIds = [];
    if (map['class_ids'] != null) {
      if (map['class_ids'] is List) {
        parsedClassIds = (map['class_ids'] as List).map((e) => e.toString()).toList();
      }
    }

    return NotificationItem(
      id: map['id'] as String,
      senderId: map['sender_id'] as String?,
      targetType: map['target_type'] as String? ?? 'everyone',
      recipientId: map['recipient_id'] as String?,
      classId: map['class_id'] as String?,
      classIds: parsedClassIds,
      title: map['title'] as String? ?? 'Notification',
      message: map['message'] as String? ?? '',
      linkUrl: map['link_url'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      senderName: (map['users'] as Map?)?['name'] as String? ?? 'System Admin',
      isRead: isRead,
    );
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  factory NotificationService() => instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  RealtimeChannel? _realtimeChannel;

  /// Start live Realtime listener to trigger Android Status Bar push notification on receipt
  void startRealtimeListener({
    required String userId,
    required String role,
    String? classId,
    Function()? onNewNotification,
  }) {
    _realtimeChannel?.unsubscribe();

    try {
      final client = Supabase.instance.client;
      _realtimeChannel = client.channel('public:notifications').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        callback: (payload) {
          final map = payload.newRecord;
          if (map.isEmpty) return;

          final targetType = map['target_type'] as String? ?? 'everyone';
          final recipientId = map['recipient_id'] as String?;
          final targetClassId = map['class_id'] as String?;
          List<String> targetClassIds = [];
          if (map['class_ids'] != null && map['class_ids'] is List) {
            targetClassIds = (map['class_ids'] as List).map((e) => e.toString()).toList();
          }

          final senderId = map['sender_id'] as String?;
          bool isRecipient = false;

          if (senderId != null && senderId == userId) {
            isRecipient = true;
          } else if (role == 'admin') {
            isRecipient = true;
          } else if (targetType == 'everyone') {
            isRecipient = true;
          } else if (targetType == 'all_students' && role == 'student') {
            isRecipient = true;
          } else if (targetType == 'all_teachers' && role == 'teacher') {
            isRecipient = true;
          } else if ((targetType == 'student' || targetType == 'teacher') && recipientId == userId) {
            isRecipient = true;
          } else if (targetType == 'class' && classId != null && targetClassId == classId) {
            isRecipient = true;
          } else if (targetType == 'multi_class' && classId != null && targetClassIds.contains(classId)) {
            isRecipient = true;
          }

          if (isRecipient) {
            // Sound/vibration push only for incoming messages from others
            if (senderId == null || senderId != userId) {
              final title = map['title'] as String? ?? 'New Notification';
              final body = map['message'] as String? ?? '';
              final linkUrl = map['link_url'] as String?;
              final idHash = (map['id'] as String? ?? DateTime.now().toIso8601String()).hashCode;

              showLocalNotification(
                id: idHash,
                title: title,
                body: body,
                payloadUrl: linkUrl,
              );
            }

            onNewNotification?.call();
          }
        },
      );
      _realtimeChannel?.subscribe();
    } catch (e) {
      debugPrint('[NotificationService] Error starting realtime listener: $e');
    }
  }

  void stopRealtimeListener() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

  /// Initialize local Android system notification settings & explicit notification channel
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Use launcher_icon as primary icon for Android notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          openLink(payload);
        }
      },
    );

    // Explicitly create high-importance notification channel for Android 8.0+
    const channel = AndroidNotificationChannel(
      'upasthitix_channel_v2',
      'UpasthitiX Alerts',
      description: 'Class Announcements and Push Alerts for UpasthitiX',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }

    _isInitialized = true;
  }

  /// Trigger outside local Android status bar heads-up notification
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payloadUrl,
  }) async {
    try {
      await initialize();

      const androidDetails = AndroidNotificationDetails(
        'upasthitix_channel_v2',
        'UpasthitiX Alerts',
        channelDescription: 'Class Announcements and Push Alerts for UpasthitiX',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/launcher_icon',
        playSound: true,
        enableVibration: true,
        ticker: 'New UpasthitiX Notice',
        styleInformation: BigTextStyleInformation(''),
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payloadUrl,
      );
    } catch (e) {
      debugPrint('[NotificationService] Local notification error: $e');
    }
  }

  /// Fire a test notification directly to Android status bar
  Future<void> testNotification() async {
    final testId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await showLocalNotification(
      id: testId,
      title: '🔔 UpasthitiX Status Bar Test',
      body: 'Status bar system notifications are working correctly!',
      payloadUrl: 'https://google.com',
    );
  }

  /// Launch clickable external link securely
  static Future<bool> openLink(String? urlStr) async {
    if (urlStr == null || urlStr.trim().isEmpty) return false;
    try {
      final formattedUrl = urlStr.trim().startsWith('http://') || urlStr.trim().startsWith('https://')
          ? urlStr.trim()
          : 'https://${urlStr.trim()}';

      final uri = Uri.parse(formattedUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[NotificationService] Cannot launch URL: $urlStr');
        return false;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error launching URL: $e');
      return false;
    }
  }

  /// Send notification to Supabase database
  static Future<bool> sendNotification({
    required String senderId,
    required String targetType, // 'everyone', 'all_teachers', 'all_students', 'class', 'multi_class', 'teacher', 'student'
    String? recipientId,
    String? classId,
    List<String>? classIds,
    required String title,
    required String message,
    String? linkUrl,
  }) async {
    try {
      final client = Supabase.instance.client;

      final insertData = <String, dynamic>{
        'sender_id': senderId,
        'target_type': targetType,
        'title': title.trim(),
        'message': message.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      if (recipientId != null && recipientId.isNotEmpty) insertData['recipient_id'] = recipientId;
      if (classId != null && classId.isNotEmpty) insertData['class_id'] = classId;
      if (classIds != null && classIds.isNotEmpty) insertData['class_ids'] = classIds;
      if (linkUrl != null && linkUrl.trim().isNotEmpty) insertData['link_url'] = linkUrl.trim();

      await client.from('notifications').insert(insertData);
      return true;
    } catch (e) {
      debugPrint('[NotificationService] Failed to send notification: $e');
      return false;
    }
  }

  /// Update/modify an existing notification
  static Future<bool> updateNotification({
    required String id,
    required String title,
    required String message,
    String? linkUrl,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('notifications').update({
        'title': title.trim(),
        'message': message.trim(),
        'link_url': (linkUrl != null && linkUrl.trim().isNotEmpty) ? linkUrl.trim() : null,
      }).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[NotificationService] Update error: $e');
      return false;
    }
  }

  /// Delete a notification
  static Future<bool> deleteNotification(String id) async {
    try {
      final client = Supabase.instance.client;
      await client.from('notifications').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[NotificationService] Delete error: $e');
      return false;
    }
  }

  /// Fetch notifications for current user with read/unread tracking
  static Future<List<NotificationItem>> getNotificationsForUser({
    required String userId,
    required String role, // 'admin', 'teacher', 'student'
    String? classId,
  }) async {
    try {
      final client = Supabase.instance.client;

      // 1. Fetch user read notification IDs
      final readRes = await client
          .from('notification_reads')
          .select('notification_id')
          .eq('user_id', userId);
      
      final readIds = (readRes as List)
          .map((r) => r['notification_id'] as String)
          .toSet();

      // 2. Query notifications table
      final response = await client
          .from('notifications')
          .select('*, users!notifications_sender_id_fkey(name)')
          .order('created_at', ascending: false);

      final List<NotificationItem> items = [];

      for (final map in (response as List)) {
        final targetType = map['target_type'] as String? ?? 'everyone';
        final recipientId = map['recipient_id'] as String?;
        final targetClassId = map['class_id'] as String?;
        List<String> targetClassIds = [];
        if (map['class_ids'] != null && map['class_ids'] is List) {
          targetClassIds = (map['class_ids'] as List).map((e) => e.toString()).toList();
        }

        final senderId = map['sender_id'] as String?;
        bool isRecipient = false;

        if (senderId != null && senderId == userId) {
          isRecipient = true; // SENDER ALWAYS SEES MESSAGES THEY DISPATCHED!
        } else if (role == 'admin') {
          isRecipient = true;
        } else if (targetType == 'everyone') {
          isRecipient = true;
        } else if (targetType == 'all_students' && role == 'student') {
          isRecipient = true;
        } else if (targetType == 'all_teachers' && role == 'teacher') {
          isRecipient = true;
        } else if ((targetType == 'student' || targetType == 'teacher') && recipientId == userId) {
          isRecipient = true;
        } else if (targetType == 'class' && classId != null && targetClassId == classId) {
          isRecipient = true;
        } else if (targetType == 'multi_class' && classId != null && targetClassIds.contains(classId)) {
          isRecipient = true;
        }

        if (isRecipient) {
          final notifId = map['id'] as String;
          items.add(NotificationItem.fromMap(map, isRead: readIds.contains(notifId)));
        }
      }

      return items;
    } catch (e) {
      debugPrint('[NotificationService] Error loading notifications: $e');
      return [];
    }
  }

  /// Mark notification as read for current user
  static Future<void> markAsRead(String notificationId, String userId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('notification_reads').upsert({
        'notification_id': notificationId,
        'user_id': userId,
        'read_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[NotificationService] Error marking as read: $e');
    }
  }
}
