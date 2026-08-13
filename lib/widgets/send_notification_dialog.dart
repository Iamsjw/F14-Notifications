import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/attendance_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class SendNotificationDialog extends StatefulWidget {
  final UserModel currentUser;
  final List<ClassModel> availableClasses;

  const SendNotificationDialog({
    super.key,
    required this.currentUser,
    required this.availableClasses,
  });

  @override
  State<SendNotificationDialog> createState() => _SendNotificationDialogState();
}

class _SendNotificationDialogState extends State<SendNotificationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _linkController = TextEditingController();

  // Target type selection
  String _targetType = 'everyone';

  // Selection state
  String? _selectedClassId;
  List<String> _selectedClassIds = [];
  String? _selectedRecipientId;

  // Search lists for dropdowns
  List<UserModel> _students = [];
  List<UserModel> _teachers = [];
  bool _isLoadingUsers = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.isTeacher) {
      _targetType = 'class';
    } else {
      _targetType = 'everyone';
    }
    _loadUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final client = SupabaseService.client;
      final studentData = await client
          .from('users')
          .select('id, name, roll_no, email, role, class_id')
          .eq('role', 'student')
          .order('name');

      if (widget.currentUser.isAdmin) {
        final teacherData = await client
            .from('users')
            .select('id, name, email, role')
            .eq('role', 'teacher')
            .order('name');
        _teachers = (teacherData as List).map((m) => UserModel.fromMap(m)).toList();
      }

      _students = (studentData as List).map((m) => UserModel.fromMap(m)).toList();
    } catch (e) {
      debugPrint('[SendNotificationDialog] Error loading users: $e');
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _handleSend() async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetType == 'class' && _selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target class.')),
      );
      return;
    }

    if (_targetType == 'multi_class' && _selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one class.')),
      );
      return;
    }

    if ((_targetType == 'student' || _targetType == 'teacher') && _selectedRecipientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target user.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final success = await NotificationService.sendNotification(
        senderId: widget.currentUser.id,
        targetType: _targetType,
        recipientId: _selectedRecipientId,
        classId: _selectedClassId,
        classIds: _selectedClassIds,
        title: _titleController.text.trim(),
        message: _messageController.text.trim(),
        linkUrl: _linkController.text.trim(),
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Notification sent successfully!',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send notification.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[SendNotificationDialog] Send error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.currentUser.isAdmin;

    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.circle_notifications_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send Targeted Notification',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Broadcast alerts with clickable links',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.shadowLight),
                const SizedBox(height: 12),

                // Audience Selector
                Text(
                  'Target Audience *',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _targetType,
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceVariant,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                      items: [
                        if (isAdmin) ...[
                          const DropdownMenuItem(
                            value: 'everyone',
                            child: Text('Everyone (All Teachers & Students)'),
                          ),
                          const DropdownMenuItem(
                            value: 'all_teachers',
                            child: Text('All Teachers (Faculty Update)'),
                          ),
                          const DropdownMenuItem(
                            value: 'teacher',
                            child: Text('Specific Teacher'),
                          ),
                          const DropdownMenuItem(
                            value: 'all_students',
                            child: Text('All Students (System Announcement)'),
                          ),
                        ],
                        const DropdownMenuItem(
                          value: 'class',
                          child: Text('Single Class Section'),
                        ),
                        const DropdownMenuItem(
                          value: 'multi_class',
                          child: Text('Multiple Classes (Combined)'),
                        ),
                        const DropdownMenuItem(
                          value: 'student',
                          child: Text('Specific Student'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _targetType = val;
                            _selectedClassId = null;
                            _selectedClassIds = [];
                            _selectedRecipientId = null;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Sub-selectors based on targetType
                if (_targetType == 'class') ...[
                  Text(
                    'Select Class *',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedClassId,
                        hint: const Text('Choose Class Section...'),
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceVariant,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                        items: widget.availableClasses.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedClassId = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else if (_targetType == 'multi_class') ...[
                  Text(
                    'Select Multiple Classes *',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: widget.availableClasses.map((c) {
                      final isSelected = _selectedClassIds.contains(c.id);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(c.name),
                        labelStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                        ),
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedClassIds.add(c.id);
                            } else {
                              _selectedClassIds.remove(c.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ] else if (_targetType == 'student') ...[
                  Text(
                    'Select Specific Student *',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoadingUsers
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRecipientId,
                              hint: const Text('Choose Student by Name/Roll...'),
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceVariant,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                              items: _students.map((st) {
                                final roll = st.rollNo != null ? ' (${st.rollNo})' : '';
                                return DropdownMenuItem(
                                  value: st.id,
                                  child: Text('${st.name}$roll'),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedRecipientId = val),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                ] else if (_targetType == 'teacher') ...[
                  Text(
                    'Select Specific Teacher *',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoadingUsers
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRecipientId,
                              hint: const Text('Choose Teacher...'),
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceVariant,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                              items: _teachers.map((t) {
                                return DropdownMenuItem(
                                  value: t.id,
                                  child: Text(t.name),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedRecipientId = val),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                ],

                // Title Input
                TextFormField(
                  controller: _titleController,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Notification Title *',
                    hintText: 'e.g. App Update v1.0.2 or Assignment Notes',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),

                // Message Body Input
                TextFormField(
                  controller: _messageController,
                  maxLines: 3,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Message Body *',
                    hintText: 'Enter notification message details...',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? 'Message is required' : null,
                ),
                const SizedBox(height: 12),

                // Clickable Link Input
                TextFormField(
                  controller: _linkController,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Clickable Action Link (Optional)',
                    hintText: 'e.g. https://play.google.com/store/... or Drive Link',
                    prefixIcon: const Icon(Icons.link_rounded, size: 18, color: AppTheme.primary),
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSending ? null : _handleSend,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        _isSending ? 'Sending...' : 'Send Notification',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
