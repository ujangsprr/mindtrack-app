import 'package:flutter/material.dart';

/// Widget Watermark standar untuk seluruh aplikasi MindTrack.
/// Digunakan di bagian bawah halaman untuk branding yang konsisten.
class AppWatermark extends StatelessWidget {
  final Color? color;
  const AppWatermark({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.grey.shade400;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 14, color: textColor.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(
            'MindTrack Pro • v1.2.0',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
