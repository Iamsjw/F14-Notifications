import 'dart:ui';
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

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;

  // Top Section: 0 = Received Notifications, 1 = Sent Notifications
  int _sectionTab = 0;

  // Sub-filter Tab: 0 = All, 1 = Unread, 2 = With Links
  int _activeTab = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _animationController;

  static const Color darkBackground = Color(0xFF0A0C13);
  static const Color darkSurface = Color(0xFF131722);
  static const Color darkCardColor = Color(0xFF161B27);
  static const Color darkCardRead = Color(0xFF11141F);
  static const Color darkBorder = Color(0xFF262D42);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
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
        _animationController.forward(from: 0.0);
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

  List<NotificationItem> get _receivedNotifications {
    return _notifications
        .where((n) => n.senderId == null || n.senderId != widget.currentUser.id)
        .toList();
  }

  List<NotificationItem> get _sentNotifications {
    return _notifications
        .where((n) => n.senderId != null && n.senderId == widget.currentUser.id)
        .toList();
  }

  List<NotificationItem> get _filteredNotifications {
    List<NotificationItem> list = _sectionTab == 0 ? _receivedNotifications : _sentNotifications;

    if (_activeTab == 1) {
      list = list.where((n) => !n.isRead).toList();
    } else if (_activeTab == 2) {
      list = list.where((n) => n.linkUrl != null && n.linkUrl!.trim().isNotEmpty).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.message.toLowerCase().contains(q) ||
              (n.senderName != null && n.senderName!.toLowerCase().contains(q)))
          .toList();
    }

    return list;
  }

  Future<void> _handleNotificationTap(NotificationItem item) async {
    if (!item.isRead && _sectionTab == 0) {
      setState(() {
        item.isRead = true;
      });
      await NotificationService.markAsRead(item.id, widget.currentUser.id);
    }

    if (item.linkUrl != null && item.linkUrl!.trim().isNotEmpty) {
      await NotificationService.openLink(item.linkUrl);
    }
  }

  Future<void> _showEditNotificationDialog(NotificationItem item) async {
    final titleCtrl = TextEditingController(text: item.title);
    final bodyCtrl = TextEditingController(text: item.message);
    final linkCtrl = TextEditingController(text: item.linkUrl ?? '');

    final bool? updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141721),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.primaryCyan.withAlpha(50)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryCyan, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Modify Notification',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0B0D13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: darkBorder.withAlpha(60)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryCyan),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: bodyCtrl,
                maxLines: 3,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Message Content',
                  labelStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0B0D13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: darkBorder.withAlpha(60)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryCyan),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: linkCtrl,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryCyan, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Clickable Link URL (Optional)',
                  labelStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0B0D13),
                  prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.primaryCyan, size: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: darkBorder.withAlpha(60)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryCyan),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
              final ok = await NotificationService.updateNotification(
                id: item.id,
                title: titleCtrl.text,
                message: bodyCtrl.text,
                linkUrl: linkCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
            label: Text('Save Changes',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );

    if (updated == true) {
      _loadNotifications();
    }
  }

  Future<void> _deleteNotification(NotificationItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141721),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.error.withAlpha(60)),
        ),
        title: Text(
          'Delete Notification?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to remove "${item.title}"? Recipients will no longer see this notification.',
          style: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete Notice',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NotificationService.deleteNotification(item.id);
      _loadNotifications();
    }
  }

  String _formatFullDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $period';

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[local.month - 1];
    final dateStr = '${local.day} $monthStr ${local.year}';

    final diff = DateTime.now().difference(dt);
    String relative = '';
    if (diff.inMinutes < 1) {
      relative = 'Just now';
    } else if (diff.inMinutes < 60) {
      relative = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      relative = '${diff.inHours}h ago';
    } else {
      relative = '${diff.inDays}d ago';
    }

    return '$dateStr • $timeStr ($relative)';
  }

  String _formatTargetBadge(String targetType) {
    switch (targetType) {
      case 'everyone':
        return 'GLOBAL NOTICE';
      case 'all_teachers':
        return 'FACULTY ONLY';
      case 'all_students':
        return 'STUDENT BROADCAST';
      case 'class':
      case 'multi_class':
        return 'CLASS ANNOUNCEMENT';
      case 'student':
      case 'teacher':
        return 'DIRECT MESSAGE';
      default:
        return 'NOTIFICATION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacherOrAdmin = widget.currentUser.role == 'admin' || widget.currentUser.role == 'teacher';
    final unreadReceivedCount = _receivedNotifications.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: darkBackground,
      body: Stack(
        children: [
          // Background Ambient Glow Orbs
          Positioned(
            top: -70,
            right: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryCyan.withAlpha(30),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryBlue.withAlpha(20),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Custom Header Bar
                _buildHeaderBar(isTeacherOrAdmin, unreadReceivedCount),

                // Main Section Switcher: Received vs Sent
                _buildSectionSwitcher(isTeacherOrAdmin, unreadReceivedCount),

                // Search & Filter Sub-Tabs
                _buildSearchAndFilterSection(),

                // List View
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.primaryCyan, strokeWidth: 2.5),
                        )
                      : _filteredNotifications.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _loadNotifications,
                              color: AppTheme.primaryCyan,
                              backgroundColor: darkSurface,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          ),
        ],
      ),
      floatingActionButton: isTeacherOrAdmin
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withAlpha(70),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: _openSendDialog,
                backgroundColor: AppTheme.primaryCyan,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                label: Text(
                  'Send Alert',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHeaderBar(bool isTeacherOrAdmin, int unreadCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: darkSurface,
        border: Border(bottom: BorderSide(color: darkBorder, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2436),
                shape: BoxShape.circle,
                border: Border.all(color: darkBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Notification Hub',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadCount UNREAD',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Received Alerts & Sent Broadcasts',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              await NotificationService.instance.testNotification();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Status bar test notification sent! Swipe down your phone status bar.'),
                    backgroundColor: AppTheme.primaryCyan,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryCyan.withAlpha(50)),
              ),
              child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryCyan, size: 18),
            ),
            tooltip: 'Test Status Bar Notification',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _loadNotifications,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2436),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: darkBorder),
              ),
              child: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
            ),
            tooltip: 'Sync Notifications',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSwitcher(bool isTeacherOrAdmin, int unreadReceived) {
    final hasSent = _sentNotifications.isNotEmpty || isTeacherOrAdmin;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF121522),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: darkBorder),
      ),
      child: Row(
        children: [
          // Received Button
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _sectionTab = 0),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: _sectionTab == 0
                      ? const LinearGradient(
                          colors: [AppTheme.primaryCyan, Color(0xFF0070F3)],
                        )
                      : null,
                  color: _sectionTab == 0 ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _sectionTab == 0
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryCyan.withAlpha(70),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.move_to_inbox_rounded,
                      size: 16,
                      color: _sectionTab == 0 ? Colors.white : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Received (${_receivedNotifications.length})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: _sectionTab == 0 ? FontWeight.bold : FontWeight.w600,
                        color: _sectionTab == 0 ? Colors.white : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (hasSent) ...[
            const SizedBox(width: 4),
            // Sent Button
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _sectionTab = 1),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: _sectionTab == 1
                        ? const LinearGradient(
                            colors: [AppTheme.primaryCyan, Color(0xFF0070F3)],
                          )
                        : null,
                    color: _sectionTab == 1 ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _sectionTab == 1
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryCyan.withAlpha(70),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.outbox_rounded,
                        size: 16,
                        color: _sectionTab == 1 ? Colors.white : const Color(0xFF9CA3AF),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Sent (${_sentNotifications.length})',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: _sectionTab == 1 ? FontWeight.bold : FontWeight.w600,
                          color: _sectionTab == 1 ? Colors.white : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: darkBackground,
        border: Border(bottom: BorderSide(color: darkBorder, width: 0.8)),
      ),
      child: Column(
        children: [
          // Live Search Field
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF141724),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: darkBorder),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: Colors.white),
              decoration: InputDecoration(
                hintText: _sectionTab == 0
                    ? 'Search received alerts...'
                    : 'Search sent notifications...',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF6B7280)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6B7280)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF6B7280)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Filter Segmented Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabSegment('All', 0, _filteredTabCount(0)),
                const SizedBox(width: 8),
                _buildTabSegment('Unread', 1, _filteredTabCount(1)),
                const SizedBox(width: 8),
                _buildTabSegment('Links & Files', 2, _filteredTabCount(2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _filteredTabCount(int tabIndex) {
    final list = _sectionTab == 0 ? _receivedNotifications : _sentNotifications;
    if (tabIndex == 1) return list.where((n) => !n.isRead).length;
    if (tabIndex == 2) return list.where((n) => n.linkUrl != null && n.linkUrl!.trim().isNotEmpty).length;
    return list.length;
  }

  Widget _buildTabSegment(String label, int index, int count) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryCyan.withAlpha(35) : const Color(0xFF141724),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryCyan : darkBorder,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryCyan : const Color(0xFF262D42),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                shape: BoxShape.circle,
                border: Border.all(color: darkBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withAlpha(20),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _sectionTab == 0 ? Icons.move_to_inbox_rounded : Icons.outbox_rounded,
                size: 40,
                color: AppTheme.primaryCyan,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _sectionTab == 0 ? 'No Received Notifications' : 'No Sent Notifications',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No notifications match "$_searchQuery"'
                  : _sectionTab == 0
                      ? (_activeTab == 1
                          ? 'All caught up! No unread notifications.'
                          : 'No incoming alerts or class announcements broadcasted yet.')
                      : 'You have not dispatched any notifications yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: const Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final hasLink = item.linkUrl != null && item.linkUrl!.trim().isNotEmpty;
    final isSentByMe = item.senderId != null && item.senderId == widget.currentUser.id;
    final canModify = isSentByMe || widget.currentUser.role == 'admin';
    final targetBadgeText = _formatTargetBadge(item.targetType);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: item.isRead ? darkCardRead : darkCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isRead ? darkBorder : AppTheme.primaryCyan.withAlpha(90),
          width: item.isRead ? 1.0 : 1.5,
        ),
        boxShadow: item.isRead
            ? []
            : [
                BoxShadow(
                  color: AppTheme.primaryCyan.withAlpha(20),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _handleNotificationTap(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header: Badge & Actions
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSentByMe
                            ? AppTheme.primaryBlue.withAlpha(30)
                            : AppTheme.primaryCyan.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSentByMe
                              ? AppTheme.primaryBlue.withAlpha(70)
                              : AppTheme.primaryCyan.withAlpha(60),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isSentByMe ? 'SENT NOTICE • $targetBadgeText' : targetBadgeText,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isSentByMe ? AppTheme.primaryBlue : AppTheme.primaryCyan,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Text(
                          _formatFullDateTime(item.createdAt),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (!item.isRead && _sectionTab == 0)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryCyan,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (canModify)
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
                        color: const Color(0xFF1C2234),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: darkBorder),
                        ),
                        onSelected: (val) {
                          if (val == 'edit') {
                            _showEditNotificationDialog(item);
                          } else if (val == 'delete') {
                            _deleteNotification(item);
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_rounded, size: 16, color: AppTheme.primaryCyan),
                                const SizedBox(width: 8),
                                Text('Modify Alert',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
                                const SizedBox(width: 8),
                                Text('Delete Notice',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // Title
                Text(
                  item.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 4),

                // Sender / Recipient Info
                Text(
                  isSentByMe
                      ? 'Dispatched by You'
                      : 'Dispatched by ${item.senderName ?? 'System Admin'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    color: const Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 8),

                // Body Message
                Text(
                  item.message,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: const Color(0xFFD1D5DB),
                    height: 1.45,
                  ),
                ),

                // Clickable Link Button Pill
                if (hasLink) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withAlpha(18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryCyan.withAlpha(45)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryCyan.withAlpha(35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.link_rounded, size: 14, color: AppTheme.primaryCyan),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attachment Link',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryCyan,
                                ),
                              ),
                              Text(
                                item.linkUrl!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryCyan,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Open',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.open_in_new_rounded, size: 12, color: Colors.white),
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
      ),
    );
  }
}
