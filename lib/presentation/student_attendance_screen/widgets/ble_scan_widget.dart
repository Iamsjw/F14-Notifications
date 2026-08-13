import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../services/ble_service.dart';

class BleScanWidget extends StatefulWidget {
  final int currentRssi;
  final int rssiThreshold;

  const BleScanWidget({
    super.key,
    required this.currentRssi,
    required this.rssiThreshold,
  });

  @override
  State<BleScanWidget> createState() => _BleScanWidgetState();
}

class _BleScanWidgetState extends State<BleScanWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  late Animation<double> _radarAnim;
  late Animation<double> _pulseAnim;
  bool _showRadar = true;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    
    _radarAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _radarController, curve: Curves.linear));

    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.08).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_radarController);
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Color _statusColor(bool isInRange, bool isDetected) {
    if (isInRange) return AppTheme.success;
    if (isDetected) return AppTheme.warning;
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final isDetected = widget.currentRssi > -105;
    final isInRange = widget.currentRssi >= widget.rssiThreshold - 5;
    final statusColor = _statusColor(isInRange, isDetected);

    return Container(
      decoration: AppTheme.glassMorphism(
        borderRadius: BorderRadius.circular(20),
        opacity: isInRange
            ? 0.10
            : isDetected
            ? 0.08
            : 0.05,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface.withAlpha(13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withAlpha(77), width: 1),
            ),
            child: Row(
              children: [
                // Radar animation (Increased size to 80x80 for clean details)
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_showRadar)
                        AnimatedBuilder(
                          animation: _radarAnim,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _RadarPainter(
                                progress: _radarAnim.value,
                                color: statusColor,
                                isDetected: isDetected,
                              ),
                              size: const Size(80, 80),
                            );
                          },
                        ),
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _showRadar = !_showRadar);
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor.withAlpha(51),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withAlpha(30),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                            child: Icon(
                              _showRadar ? Icons.bluetooth_searching_rounded : Icons.bluetooth_rounded,
                              color: statusColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInRange
                            ? 'In Range — Verifying...'
                            : isDetected
                            ? 'Signal Weak — Move Closer'
                            : 'Scanning for Teacher Device...',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDetected
                            ? 'RSSI: ${widget.currentRssi} dBm · ${BleService.rssiQualityLabel(widget.currentRssi)}'
                            : 'Looking for BLE broadcast nearby',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Progress indicator
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          backgroundColor: AppTheme.shadowLight.withAlpha(20),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            statusColor,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDetected;

  _RadarPainter({
    required this.progress,
    required this.color,
    required this.isDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const minRadius = 21.0; // Outer boundary of 42px center button

    // 1. Concentric rings expanding outward from the center button border
    for (int i = 0; i < 3; i++) {
      final ringProgress = ((progress - i * 0.33) % 1.0);
      final radius = minRadius + (maxRadius - minRadius) * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0) * 0.35;

      final paint = Paint()
        ..color = color.withAlpha((opacity * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawCircle(center, radius, paint);
    }

    // 2. Rotating sweep sector (gradient trail)
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: 2 * pi,
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.02),
          color.withOpacity(0.12),
          color.withOpacity(0.25),
        ],
        stops: const [0.0, 0.5, 0.85, 1.0],
        transform: GradientRotation(progress * 2 * pi - pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    // We draw an arc or circle, the shader takes care of fading trail
    canvas.drawCircle(center, maxRadius, sweepPaint);

    // 3. Rotating sweep radial line (adds military scanner feel)
    final angle = progress * 2 * pi - pi / 2;
    final edgePaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final edgeOffset = Offset(
      center.dx + cos(angle) * maxRadius,
      center.dy + sin(angle) * maxRadius,
    );
    canvas.drawLine(center, edgeOffset, edgePaint);


  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDetected != isDetected;
}
