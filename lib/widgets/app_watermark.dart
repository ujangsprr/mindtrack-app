import 'package:flutter/material.dart';

/// Widget Watermark standar untuk seluruh aplikasi MindTrack.
/// Didesain minimalis, elegan, dan proporsional tanpa mengalihkan fokus pengguna.
class AppWatermark extends StatelessWidget {
  final Color? color;
  final double topPadding;
  final double bottomPadding;

  const AppWatermark({
    super.key,
    this.color,
    this.topPadding = 24.0,
    this.bottomPadding = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? const Color(0xFF94A3B8); // Slate 400

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: baseColor.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sensors_rounded,
                size: 13,
                color: baseColor.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                'MindTrack Pro',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: baseColor.withValues(alpha: 0.75),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Text(
                'v1.2.0',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  letterSpacing: 0.3,
                  color: baseColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

