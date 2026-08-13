import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/attendance_model.dart';
import '../../models/user_model.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/send_notification_dialog.dart';

class NotificationScreen extends StatefulWidget {
  final UserModel currentUser;

  const NotificationScreen({super.key, required this.currentUser});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  int _activeTab = 0; // 0: All, 1: Unread, 2: Updates/Links

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final items = await NotificationService.getNotificationsForUser(
        userId: widget.currentUser.id,
        role: widget.currentUser.role,
        classId: widget.currentUser.classId,
      );
      if (mounted) {
        setState(() {
          _notifications = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[NotificationScreen] Load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openSendDialog() async {
    List<ClassModel> classes = [];
    try {
      final res = await SupabaseService.client.from('classes').select('*').order('name');
      if (res != null) {
        classes = (res as List).map((m) => ClassModel.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching classes: $e');
    }

    if (!mounted) return;

    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => SendNotificationDialog(
        currentUser: widget.currentUser,
        availableClasses: classes,
      ),
    );

    if (sent == true) {
      _loadNotifications();
    }
  }

  List<NotificationItem> get _filteredNotifications {
    if (_activeTab == 1) {
      return _notifications.where((n) => !n.isRead).toList();
    } else if (_activeTab == 2) {
      return _notifications.where((n) => n.linkUrl != null && n.linkUrl!.isNotEmpty).toList();
    }
    return _notifications;
  }

  Future<void> _handleNotificationTap(NotificationItem item) async {
    if (!item.isRead) {
      setState(() {
        item.isRead = true;
      });
      await NotificationService.markAsRead(item.id, widget.currentUser.id);
    }

    if (item.linkUrl != null && item.linkUrl!.trim().isNotEmpty) {
      await NotificationService.openLink(item.linkUrl);
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    final canSend = widget.currentUser.isAdmin || widget.currentUser.isTeacher;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceVariant,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Center',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          if (canSend)
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
              onPressed: _openSendDialog,
              tooltip: 'Send Targeted Notification',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textPrimary),
            onPressed: _loadNotifications,
            tooltip: 'Refresh Notifications',
          ),
        ],
      ),
      floatingActionButton: canSend
          ? FloatingActionButton.extended(
              onPressed: _openSendDialog,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                'Send Notification',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.shadowLight.withAlpha(20),
                ),
              ),
            ),
            child: Row(
              children: [
                _buildFilterChip('All', 0, _notifications.length),
                const SizedBox(width: 8),
                _buildFilterChip('Unread', 1, unreadCount),
                const SizedBox(width: 8),
                _buildFilterChip('Links & Updates', 2, _notifications.where((n) => n.linkUrl != null && n.linkUrl!.isNotEmpty).length),
              ],
            ),
          ),

          // List Body
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _filteredNotifications.isEmpty
                    ? Center(
                        child: EmptyStateWidget(
                          icon: Icons.notifications_none_rounded,
                          title: 'No Notifications Found',
                          description: _activeTab == 1
                              ? 'You have read all your notifications.'
                              : 'No announcements or update notifications yet.',
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredNotifications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = _filteredNotifications[index];
                            return _buildNotificationCard(item);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int tabIndex, int count) {
    final isSelected = _activeTab == tabIndex;

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withAlpha(50) : AppTheme.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : AppTheme.textSecondary,
      ),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      onSelected: (_) => setState(() => _activeTab = tabIndex),
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final hasLink = item.linkUrl != null && item.linkUrl!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: item.isRead ? AppTheme.surface : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isRead
              ? AppTheme.shadowLight.withAlpha(20)
              : AppTheme.primary.withAlpha(100),
          width: item.isRead ? 1 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _handleNotificationTap(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasLink
                          ? AppTheme.primaryCyan.withAlpha(25)
                          : item.isRead
                              ? AppTheme.shadowLight.withAlpha(20)
                              : AppTheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      hasLink
                          ? Icons.system_update_rounded
                          : Icons.notifications_active_rounded,
                      size: 20,
                      color: hasLink
                          ? AppTheme.primaryCyan
                          : item.isRead
                              ? AppTheme.textMuted
                              : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (!item.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.senderName ?? 'System'} • ${_formatTimeAgo(item.createdAt)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              if (hasLink) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primaryCyan.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, size: 16, color: AppTheme.primaryCyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.linkUrl!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryCyan,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Open Link',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.open_in_new_rounded,
                              size: 12,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
