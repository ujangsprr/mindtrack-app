import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/ble_service.dart';
import '../widgets/app_watermark.dart';

/// Halaman data teknis – menampilkan seluruh data mentah dari perangkat.
/// Cocok untuk pemantauan presisi: HR, IBI, HRV, GSR, Akselerometer, & Suhu.
class SensorDetailScreen extends StatefulWidget {
  final BleService bleService;
  const SensorDetailScreen({super.key, required this.bleService});

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  final _rng = Random();
  late SensorData _current;
  Timer? _mockTimer;
  StreamSubscription<SensorData>? _bleSub;

  BleService get _ble => widget.bleService;
  final Color _slateBg = const Color(0xFF0F172A);
  final Color _cardBg = const Color(0xFF1E293B);
  final Color _accentIndigo = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _current = _generateReading();
    _ble.addListener(_onBleStateChanged);
    _bleSub = _ble.dataStream.listen((data) {
      if (mounted) setState(() => _current = data);
    });
    _updateDataSource();
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _bleSub?.cancel();
    _ble.removeListener(_onBleStateChanged);
    super.dispose();
  }

  void _onBleStateChanged() {
    _updateDataSource();
    if (mounted) setState(() {});
  }

  void _updateDataSource() {
    if (_ble.isConnected) {
      _mockTimer?.cancel();
      _mockTimer = null;
    } else {
      _mockTimer ??= Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (mounted) setState(() => _current = _generateReading());
      });
    }
  }

  SensorData _generateReading() {
    final hr = _rng.nextInt(51) + 60;
    return SensorData(
      isWorn: true,
      heartRate: hr,
      ibi: (60000 ~/ hr) + _rng.nextInt(60) - 30,
      hrv: _rng.nextInt(35) + 8,
      temperature: 36.0 + _rng.nextDouble() * 1.5,
      motionScore: _rng.nextInt(61),
      stressIndex: _rng.nextInt(81) + 10,
      gsrPercent: _rng.nextInt(81) + 10,
      irRaw: _rng.nextInt(50000) + 100000,
      sensorStatus: 0x1F,
      uptimeSeconds: 120 + _rng.nextInt(3600),
      accelX: (_rng.nextDouble() - 0.5) * 0.4,
      accelY: (_rng.nextDouble() - 0.5) * 0.4,
      accelZ: 9.7 + _rng.nextDouble() * 0.2,
      timestamp: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _slateBg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: _slateBg.withValues(alpha: 0.95),
              elevation: 0,
              centerTitle: false,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pusat Data Sensor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _ble.isConnected ? 'Menampilkan data real-time' : 'Mode Demo Simulasi',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), // Slate 400
                  ),
                ],
              ),
              actions: [
                _buildStatusChip(),
              ],
            ),

            // ── Body ────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _TimestampHUD(data: _current),
                  const SizedBox(height: 12),

                  // Status Pemakaian & Health Bitmask dari ESP32
                  _WearStatusHUD(data: _current, cardBg: _cardBg),
                  const SizedBox(height: 10),
                  _SensorHealthHUD(data: _current, cardBg: _cardBg),
                  const SizedBox(height: 24),

                  const _SectionLabel(icon: Icons.monitor_heart_rounded, label: 'Jantung & Oksigen', color: Colors.pinkAccent),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _HUDCard(
                          label: 'Heart Rate',
                          value: _current.heartRateDisplayText,
                          unit: _current.isWorn && _current.heartRate > 0 ? 'BPM' : '',
                          color: Colors.pinkAccent,
                          icon: Icons.heart_broken_rounded,
                          cardBg: _cardBg,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HUDCard(
                          label: 'Variabilitas (HRV)',
                          value: _current.hrvDisplayText,
                          unit: _current.hrv >= 0 ? 'ms' : '',
                          color: Colors.purpleAccent,
                          icon: Icons.timeline_rounded,
                          cardBg: _cardBg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _HUDCard(
                    label: 'Inter-Beat Interval (IBI)',
                    value: '${_current.ibi}',
                    unit: 'ms',
                    color: Colors.cyanAccent,
                    icon: Icons.show_chart_rounded,
                    fullWidth: true,
                    cardBg: _cardBg,
                  ),
                  const SizedBox(height: 24),

                  const _SectionLabel(icon: Icons.thermostat_rounded, label: 'Suhu & Kulit', color: Colors.orangeAccent),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _HUDCard(
                          label: 'Suhu Tubuh',
                          value: _current.temperature.toStringAsFixed(2),
                          unit: '°C',
                          color: Colors.orangeAccent,
                          icon: Icons.thermostat_rounded,
                          cardBg: _cardBg,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HUDCard(
                          label: 'Respon Kulit',
                          value: '${_current.gsrPercent}',
                          unit: '%',
                          color: Colors.tealAccent,
                          icon: Icons.water_drop_rounded,
                          cardBg: _cardBg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const _SectionLabel(icon: Icons.directions_run_rounded, label: 'Akselerasi & Gerak', color: Colors.blueAccent),
                  const SizedBox(height: 10),
                  _HUDCard(
                    label: 'Skor Gerak Aktif',
                    value: '${_current.motionScore}',
                    unit: '/ 100',
                    color: Colors.blueAccent,
                    icon: Icons.directions_run_rounded,
                    fullWidth: true,
                    cardBg: _cardBg,
                  ),
                  const SizedBox(height: 8),
                  _AccelBar(current: _current, cardBg: _cardBg),
                  const SizedBox(height: 32),

                  const _SectionLabel(icon: Icons.psychology_rounded, label: 'Kesehatan Mental', color: Colors.deepOrangeAccent),
                  const SizedBox(height: 10),
                  _StressFusionCard(data: _current, cardBg: _cardBg, accentColor: _accentIndigo),
                  const SizedBox(height: 48),

                  const AppWatermark(color: Color(0xFF334155)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    final bool connected = _ble.isConnected;
    final color = connected ? const Color(0xFF10B981) : const Color(0xFF94A3B8); // Slate 400
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'LIVE' : 'DEMO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── HUD Sub-widgets ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionLabel({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.5, 
              color: Color(0xFF64748B) // Slate 500
            ),
          ),
        ),
      ],
    );
  }
}

class _TimestampHUD extends StatelessWidget {
  final SensorData data;
  const _TimestampHUD({required this.data});

  @override
  Widget build(BuildContext context) {
    final ts = data.timestamp;
    final time = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    final uptime = data.uptimeSeconds;
    final uptimeStr = uptime > 0 ? '${uptime ~/ 60}m ${uptime % 60}s' : '0s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  children: [
                    const TextSpan(text: 'ESP32 > ', style: TextStyle(color: Color(0xFF6366F1))),
                    TextSpan(text: 'FETCH: $time', style: const TextStyle(color: Color(0xFFCBD5E1))),
                  ],
                ),
              ),
            ],
          ),
          Text(
            'UPTIME: $uptimeStr',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status Pemakaian Alat (Wear Detection: IR > 50.000 / doc['worn'] == 1)
class _WearStatusHUD extends StatelessWidget {
  final SensorData data;
  final Color cardBg;
  const _WearStatusHUD({required this.data, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    final isWorn = data.isWorn;
    final color = isWorn ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWorn ? Icons.verified_user_rounded : Icons.warning_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWorn ? 'Sensor Terpasang di Kulit' : 'Sensor Terlepas dari Kulit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  isWorn
                      ? 'MAX30102 mendeteksi pulsa darah'
                      : 'Alat dilepas — Parameter di-standby',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'IR: ${data.irRaw}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status Diagnostik Tiap Sensor Fisiologis (Decoding Bitmask `ss`)
class _SensorHealthHUD extends StatelessWidget {
  final SensorData data;
  final Color cardBg;
  const _SensorHealthHUD({required this.data, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Status Sensor Hardware (ss bitmask)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Text(
                '0b${data.sensorStatus.toRadixString(2).padLeft(5, '0')}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSensorChip('MAX30102 (HR)', data.isHeartRateValid),
              _buildSensorChip('HRV RMSSD', data.isHrvValid, pending: data.hrv < 0),
              _buildSensorChip('GSR ADC', data.isGsrValid),
              _buildSensorChip('MLX90614 (Suhu)', data.isTempValid),
              _buildSensorChip('MPU6050 (IMU)', data.isMotionValid),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorChip(String name, bool isOk, {bool pending = false}) {
    final Color chipColor;
    final String label;

    if (pending) {
      chipColor = const Color(0xFF38BDF8); // Sky blue
      label = '$name: Menghitung';
    } else if (isOk) {
      chipColor = const Color(0xFF10B981); // Emerald green
      label = '$name: OK';
    } else {
      chipColor = const Color(0xFF94A3B8); // Slate 400
      label = '$name: Standby';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: chipColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}


class _HUDCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;
  final bool fullWidth;
  final Color cardBg;

  const _HUDCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    required this.cardBg,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label, 
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)), // Slate 400
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: fullWidth ? 32 : 24, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), // Slate 500
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccelBar extends StatelessWidget {
  final SensorData current;
  final Color cardBg;
  const _AccelBar({required this.current, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    final magnitude = current.accelMagnitude;
    final progress = (magnitude / 15.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Impact Magnitude', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))), // Slate 400
              Text('${magnitude.toStringAsFixed(2)} m/s²', style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(Color.lerp(Colors.blueAccent, Colors.redAccent, progress)!),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StressFusionCard extends StatelessWidget {
  final SensorData data;
  final Color cardBg;
  final Color accentColor;
  const _StressFusionCard({required this.data, required this.cardBg, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final stress = data.stressIndex;
    final Color color = stress <= 30 ? const Color(0xFF10B981) : stress <= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), cardBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_rounded, size: 16, color: color),
              const SizedBox(width: 8),
              const Text('STRESS FUSION INDEX', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              _Chip(label: 'ALGORITMA V2', color: color),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$stress',
                style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace', height: 1.0),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: const Text('/ 100', style: TextStyle(fontSize: 16, color: Color(0xFF475569))), // Slate 600
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(data.stressLabel.toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  const Text('DIPROSES SECARA REAL-TIME', style: TextStyle(fontSize: 8, color: Color(0xFF64748B))), // Slate 500
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stress / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Kalkulasi menggabungkan sensor HR, HRV, GSR (kulit), dan percepatan gerak untuk mendeteksi beban kognitif & emosional.',
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), height: 1.5), // Slate 500
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
