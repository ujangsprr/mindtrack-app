/// Holds a single snapshot of sensor readings from the MindTrack wearable device.
class SensorData {
  final bool isWorn;        // true if device is on wrist (worn == 1)
  final int heartRate;      // BPM (hr)
  final int ibi;            // ms — Inter-Beat Interval (ibi)
  final int hrv;            // ms — HRV RMSSD (hrv, -1 during calibration)
  final double temperature; // °C (t)
  final int motionScore;    // 0–100 — computed from movement or IMU
  final int stressIndex;    // 0–100 — Fusion Index from device (st)
  final int gsrPercent;     // 0–100% — skin conductance (g)
  final int irRaw;          // raw IR intensity from MAX30102 (ir)
  final int sensorStatus;   // bitmask health: bit0=HR, bit1=HRV, bit2=GSR, bit3=Temp, bit4=IMU (ss)
  final int uptimeSeconds;  // device uptime in seconds (ts)
  final double accelX;      // m/s² (ax)
  final double accelY;      // m/s² (ay)
  final double accelZ;      // m/s² (az)
  final DateTime timestamp;

  const SensorData({
    this.isWorn = true,
    required this.heartRate,
    required this.ibi,
    required this.hrv,
    required this.temperature,
    required this.motionScore,
    required this.stressIndex,
    required this.gsrPercent,
    required this.irRaw,
    this.sensorStatus = 0x1F,
    this.uptimeSeconds = 0,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.timestamp,
  });

  // ── Sensor Health Status (Bitmask `ss` Decoding) ──────────────────────────
  bool get isHeartRateValid => (sensorStatus & 0x01) != 0 && isWorn && heartRate > 0;
  bool get isHrvValid => (sensorStatus & 0x02) != 0 && hrv >= 0;
  bool get isGsrValid => (sensorStatus & 0x04) != 0;
  bool get isTempValid => (sensorStatus & 0x08) != 0;
  bool get isMotionValid => (sensorStatus & 0x10) != 0;
  bool get allSensorsReady => sensorStatus == 0x1F;

  // ── Smart Processing (Age & BMI Aware) ───────────────────────────────────

  /// Calculates a more accurate stress index adjusted for age and BMI.
  int getAdjustedStress(int? age, double? height, double? weight) {
    if (!isWorn) return 0;
    if (age == null) return stressIndex;

    double adjustmentFactor = 1.0;
    
    // 1. Age Normalization (HRV naturally declines with age)
    if (age > 30) adjustmentFactor -= 0.05;
    if (age > 45) adjustmentFactor -= 0.10;
    if (age > 60) adjustmentFactor -= 0.15;

    // 2. BMI Influence
    if (height != null && weight != null && height > 0) {
      final hMeter = height / 100.0;
      final bmiValue = weight / (hMeter * hMeter);
      if (bmiValue > 25) adjustmentFactor -= 0.05;
      if (bmiValue > 30) adjustmentFactor -= 0.08;
    }

    // 3. Heart Rate Reserve adjustment
    int mhr = 220 - age;
    double hrIntensity = heartRate / mhr;

    int adjusted = (stressIndex * adjustmentFactor).toInt();
    if (hrIntensity > 0.8) adjusted += 10;
    
    return adjusted.clamp(0, 100);
  }

  /// Label based on age-adjusted stress index.
  String getStressLabel(int? age, double? height, double? weight) {
    if (!isWorn) return 'Dilepas ⚠️';
    final idx = getAdjustedStress(age, height, weight);
    if (idx <= 30) return 'Santai 😊';
    if (idx <= 60) return 'Normal 😐';
    return 'Tegang 😟';
  }

  /// High-granularity analysis based on multi-dimensional sensor data.
  String getStressAnalysis(int? age, double? height, double? weight) {
    if (!isWorn) {
      return "Perangkat Tidak Terpasang: Sensor inframerah tidak mendeteksi kontak dengan kulit. Pasang alat ke pergelangan tangan untuk melanjutkan pemantauan biometrik.";
    }

    final idx = getAdjustedStress(age, height, weight);
    final isMoving = motionScore > 40;

    // --- CATEGORY: TEGANG (HIGH STRESS) ---
    if (idx > 60) {
      if (heartRate > 100 && !isMoving) {
        return "Stres Mental Tinggi: Detak jantung Anda sangat cepat padahal tubuh tidak banyak bergerak. Ini menandakan lonjakan kortisol atau kecemasan akut.";
      }
      if (gsrPercent > 70) {
        return "Reaksi Emosional Kuat: Aktivitas kelenjar keringat (GSR) meningkat drastis, menunjukkan respon 'fight or flight' terhadap pemicu eksternal.";
      }
      if (hrv >= 0 && hrv < 20) {
        return "Kelelahan Sistem Saraf: Variabilitas detak jantung Anda sangat rendah. Sistem saraf Anda kehilangan fleksibilitas untuk kembali tenang.";
      }
      if (temperature > 37.5) {
        return "Beban Termal & Stres: Suhu tubuh meningkat bersamaan dengan indeks stres, mungkin karena lingkungan panas atau kelelahan fisik yang berlebihan.";
      }
      return "Stres Akumulatif: Data biometrik menunjukkan beban sistem saraf yang tinggi dari berbagai faktor gabungan.";
    }

    // --- CATEGORY: NORMAL (MODERATE) ---
    else if (idx > 30) {
      if (isMoving) {
        return "Aktivitas Produktif: Detak jantung dan stres berada dalam rentang normal untuk tubuh yang sedang aktif bergerak.";
      }
      if (gsrPercent > 50) {
        return "Interaksi Sosial/Kerja: Ada sedikit lonjakan respons kulit, mungkin karena percakapan mendalam atau fokus pada tugas yang menantang.";
      }
      return "Kondisi Stabil: Sistem tubuh Anda bekerja dengan efisien dalam mode fungsional harian.";
    }

    // --- CATEGORY: SANTAI (LOW STRESS) ---
    else {
      if (heartRate < 65 && hrv > 40) {
        return "Pemulihan Optimal: Detak jantung rendah dan HRV tinggi menunjukkan fase restorasi yang sangat baik bagi organ tubuh.";
      }
      if (temperature < 36.2) {
        return "Relaksasi Dalam: Tubuh berada dalam mode hemat energi, sangat baik untuk meditasi atau persiapan tidur.";
      }
      return "Ketenangan Mental: Pikiran dan tubuh Anda sedang dalam sinkronisasi yang tenang dan seimbang.";
    }
  }

  /// Highly specific recommendations based on the analysis above.
  String getRecommendation(int? age, double? height, double? weight) {
    if (!isWorn) {
      return "Pastikan jam tangan MindTrack terpasang dengan baik pada pergelangan tangan agar sensor dapat membaca denyut nadi, suhu, dan konduktansi kulit.";
    }

    final idx = getAdjustedStress(age, height, weight);
    final isMoving = motionScore > 40;

    // --- RECOMMENDATIONS FOR TEGANG (HIGH STRESS) ---
    if (idx > 60) {
      if (heartRate > 100 && !isMoving) {
        return "Segera lakukan pernapasan perut (Diaphragmatic Breathing). Hirup 4 detik melalui hidung, buang 6 detik melalui mulut. Ulangi 10 kali untuk menurunkan detak jantung.";
      }
      if (gsrPercent > 70) {
        return "Basuh wajah atau lengan dengan air dingin. Suhu dingin akan memicu refleks penyelaman yang secara instan menenangkan sistem saraf simpatis Anda.";
      }
      if (hrv >= 0 && hrv < 20) {
        return "Anda butuh istirahat total. Matikan layar gawai, tutup mata selama 5 menit, dan biarkan sistem saraf Anda melakukan reboot tanpa stimulasi visual.";
      }
      return "Cari tempat yang tenang dengan udara segar. Lakukan peregangan leher dan bahu untuk melepas ketegangan otot yang menghambat aliran darah ke otak.";
    }

    // --- RECOMMENDATIONS FOR NORMAL (MODERATE) ---
    else if (idx > 30) {
      if (isMoving) {
        return "Pertahankan momentum ini. Pastikan Anda minum air putih (250ml) setiap 30 menit agar volume darah tetap stabil dan jantung tidak bekerja terlalu keras.";
      }
      return "Gunakan zona fokus ini untuk menyelesaikan tugas sulit. Namun, pastikan berdiri dan berjalan selama 2 menit setiap satu jam untuk menjaga sirkulasi.";
    }

    // --- RECOMMENDATIONS FOR SANTAI (LOW STRESS) ---
    else {
      if (hrv > 50) {
        return "Waktu yang tepat untuk refleksi atau merencanakan strategi besar. Kejelasan mental Anda sedang berada di puncak tertingginya.";
      }
      return "Sangat baik untuk melanjutkan hobi ringan atau membaca buku. Tubuh Anda sedang mengisi ulang tangki energi untuk tantangan berikutnya.";
    }
  }

  // ── Basic Raw Labels ──────────────────────────────────────────────────────

  String get stressLabel {
    if (!isWorn) return 'Dilepas ⚠️';
    if (stressIndex <= 30) return 'Santai 😊';
    if (stressIndex <= 60) return 'Normal 😐';
    return 'Tegang 😟';
  }

  String get stressLabelShort {
    if (!isWorn) return 'Dilepas';
    if (stressIndex <= 30) return 'Santai';
    if (stressIndex <= 60) return 'Normal';
    return 'Tegang';
  }

  String get hrvLabel {
    if (hrv < 0) return 'Menghitung...';
    if (hrv <= 10) return 'Rendah';
    if (hrv <= 30) return 'Normal';
    return 'Baik';
  }

  String get hrvDisplayText {
    return hrv < 0 ? '--' : '$hrv';
  }

  String get gsrLabel {
    if (gsrPercent <= 30) return 'Kering';
    if (gsrPercent <= 60) return 'Normal';
    return 'Lembab';
  }

  String get activityLabel {
    if (motionScore <= 20) return 'Istirahat';
    if (motionScore <= 50) return 'Ringan';
    if (motionScore <= 75) return 'Sedang';
    return 'Aktif';
  }

  String get heartRateLabel {
    if (!isWorn) return 'Dilepas';
    if (heartRate < 60) return 'Rendah';
    if (heartRate <= 100) return 'Normal';
    if (heartRate <= 140) return 'Sedikit Tinggi';
    return 'Tinggi';
  }

  String get heartRateDisplayText {
    if (!isWorn || heartRate <= 0) return '--';
    return '$heartRate';
  }

  String get temperatureLabel {
    if (temperature < 36.0) return 'Rendah';
    if (temperature <= 37.5) return 'Normal';
    return 'Demam';
  }

  double get accelMagnitude {
    final sum = accelX * accelX + accelY * accelY + accelZ * accelZ;
    return _sqrt(sum);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double z = v;
    for (int i = 0; i < 20; i++) {
      z = (z + v / z) / 2;
    }
    return z;
  }

  factory SensorData.fromBleJson(Map<String, dynamic> json) {
    // 1. Wear detection from 'worn' key, fallback to IR threshold > 50000
    final wornVal = json['worn'];
    final irVal = (json['ir'] as num?)?.toInt() ?? 0;
    final bool isWorn = wornVal != null
        ? (wornVal == 1 || wornVal == true)
        : (irVal > 50000);

    // 2. Sensor health bitmask: bit0=HR, bit1=HRV, bit2=GSR, bit3=Temp, bit4=IMU
    final int sensorStatus = (json['ss'] as num?)?.toInt() ?? 0x1F;

    // 3. System uptime seconds
    final int uptime = (json['ts'] as num?)?.toInt() ?? 0;

    // 4. HRV (-1 denotes calculating phase in Arduino firmware)
    final int rawHrv = (json['hrv'] as num?)?.toInt() ?? -1;

    // 5. Accelerometer readings
    final ax = (json['ax'] as num?)?.toDouble() ?? 0.0;
    final ay = (json['ay'] as num?)?.toDouble() ?? 0.0;
    final az = (json['az'] as num?)?.toDouble() ?? (json.containsKey('az') ? 0.0 : 9.8);

    // 6. Motion score computation
    final int motionScore;
    if (json.containsKey('ax') || json.containsKey('ay') || json.containsKey('az')) {
      final mag = _sqrt(ax * ax + ay * ay + az * az);
      final netMotion = (mag - 9.81).abs();
      motionScore = (netMotion * 12.0).clamp(0.0, 100.0).toInt();
    } else {
      motionScore = 0;
    }

    return SensorData(
      isWorn:        isWorn,
      heartRate:     (json['hr']  as num?)?.toInt() ?? 0,
      ibi:           (json['ibi'] as num?)?.toInt() ?? 0,
      hrv:           rawHrv,
      temperature:   (json['t']   as num?)?.toDouble() ?? 0.0,
      motionScore:   motionScore,
      stressIndex:   ((json['st'] as num?)?.toInt() ?? 0).clamp(0, 100),
      gsrPercent:    ((json['g']  as num?)?.toInt() ?? 0).clamp(0, 100),
      irRaw:         irVal,
      sensorStatus:  sensorStatus,
      uptimeSeconds: uptime,
      accelX:        ax,
      accelY:        ay,
      accelZ:        az,
      timestamp:     DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'worn': isWorn ? 1 : 0,
      'hr':   heartRate,
      'ibi':  ibi,
      'hrv':  hrv,
      'st':   stressIndex,
      't':    temperature,
      'g':    gsrPercent,
      'ir':   irRaw,
      'ss':   sensorStatus,
      'ts':   uptimeSeconds > 0 ? uptimeSeconds : timestamp.millisecondsSinceEpoch ~/ 1000,
      'ax':   accelX,
      'ay':   accelY,
      'az':   accelZ,
    };
  }
}
