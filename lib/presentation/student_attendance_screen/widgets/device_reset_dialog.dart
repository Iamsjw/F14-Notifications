import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../theme/app_theme.dart';
import '../../../../services/supabase_service.dart';

class DeviceResetDialog extends StatefulWidget {
  final String studentId;
  final String email;
  final String newDeviceId;
  final VoidCallback onResetSuccess;

  const DeviceResetDialog({
    super.key,
    required this.studentId,
    required this.email,
    required this.newDeviceId,
    required this.onResetSuccess,
  });

  @override
  State<DeviceResetDialog> createState() => _DeviceResetDialogState();
}

class _DeviceResetDialogState extends State<DeviceResetDialog> {
  bool _isLoading = false;
  bool _otpSent = false;
  int _remainingResets = 2;
  String? _errorMessage;
  String? _successMessage;

  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkLimits();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkLimits() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final check = await SupabaseService.checkSelfResetLimit(widget.studentId);
      if (mounted) {
        setState(() {
          _remainingResets = check['remaining'] ?? 0;
          if (check['allowed'] != true) {
            _errorMessage = check['error'] ?? 'Self-reset limit exceeded.';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to check reset limits.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendOTP() async {
    if (_remainingResets <= 0) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService.sendResetDeviceOTP(widget.email, widget.studentId);
      if (mounted) {
        setState(() {
          _otpSent = true;
          _isLoading = false;
          _successMessage = 'Verification code sent to your email.';
        });
        Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() => _successMessage = null);
          }
        });
        _otpFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOTP() async {
    final token = _otpController.text.trim();
    if (token.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService.verifyDeviceResetOTP(
        email: widget.email,
        studentId: widget.studentId,
        token: token,
        newDeviceId: widget.newDeviceId,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage = 'Device verified successfully!';
        });

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            widget.onResetSuccess();
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid or expired verification code. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceVariant.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      actionsPadding: const EdgeInsets.only(bottom: 16, right: 16, left: 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Header
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _otpSent ? AppTheme.successSoft : AppTheme.warningSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _otpSent ? Icons.mark_email_read_rounded : Icons.phonelink_setup_rounded,
              color: _otpSent ? AppTheme.success : AppTheme.warning,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            _otpSent ? 'Verify Device ID' : 'New Device Detected',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            _otpSent
                ? 'Enter the 6-digit verification code sent to ${widget.email} to register this device.'
                : 'It looks like you are logging in from a new device or reinstalled the application. You must verify your device via OTP to continue.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Monthly Limit Counter Banner
          if (!_otpSent && _errorMessage == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.shadowLight.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$_remainingResets of 2 self-service resets remaining this month',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

          // Error Message
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.errorSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Success Message
          if (_successMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.successSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: Text(
                _successMessage!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.success,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // OTP input textfield
          if (_otpSent) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              focusNode: _otpFocusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: AppTheme.textPrimary,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textMuted.withOpacity(0.4),
                  letterSpacing: 8,
                ),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: AppTheme.shadowLight.withAlpha(8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.shadowLight.withAlpha(20)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
          ],

          if (_isLoading) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ],
      ),
      actions: [
        if (!_otpSent) ...[
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
            ),
          ),
          if (_remainingResets > 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: _isLoading ? null : _sendOTP,
              child: Text(
                'Send Verification OTP',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
        ] else ...[
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    setState(() {
                      _otpSent = false;
                      _otpController.clear();
                      _errorMessage = null;
                    });
                  },
            child: Text(
              'Back',
              style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: _isLoading ? null : _verifyOTP,
            child: Text(
              'Verify & Bind Device',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ]
      ],
    );
  }
}
