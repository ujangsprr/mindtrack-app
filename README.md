# 🧠 MindTrack Pro

**MindTrack Pro** adalah aplikasi Flutter canggih untuk memonitor perangkat wearable pendeteksi stres dan kesehatan mental secara real-time. Aplikasi ini tidak hanya menampilkan data mentah, tetapi juga memberikan analisis cerdas dan saran tindakan berdasarkan profil fisik serta data biometrik pengguna (Detak Jantung, HRV, GSR, Suhu, dan Akselerasi).

---

## ✨ Fitur Utama

- 🧠 **Dynamic Stress Insights** — Analisis real-time "Mengapa" stres terjadi dan "Apa" yang harus dilakukan (Saran Tindakan) berdasarkan matriks keputusan multi-dimensi.
- ⚖️ **Personalized Analytics** — Algoritma deteksi stres yang menyesuaikan dengan **Usia, Tinggi Badan, Berat Badan (BMI)**, dan Heart Rate Reserve (HRR).
- 📡 **BLE Integration** — Scan dan terhubung otomatis ke perangkat wearable ESP32 menggunakan protokol GATT dengan sistem buffer JSON yang stabil.
- 👤 **Advanced Profiling** — Setup profil lengkap (Nama, Tanggal Lahir, TB, BB) dengan fitur edit foto profil (Crop & Rotate).
- 📊 **Dashboard Real-Time** — Indikator stres melingkar premium dengan animasi pulsa dan kartu data fisiologis terperinci.
- 📈 **History & Edukasi** — Grafik riwayat stres 24 jam interaktif dan modul edukasi manajemen stres terintegrasi.
- 🔄 **Live Fallback** — Simulasi data cerdas (*Mock Data*) saat koneksi terputus untuk memastikan UI tetap interaktif di simulator maupun device fisik.

---

## 📡 Protokol Komunikasi BLE ESP32

MindTrack Pro membaca data biometrik berformat **JSON** melalui paket BLE *Notify* dengan interval transmisi 500 ms (2 Hz).

### UUID GATT MindTrack
- **Device Name:** `MindTrack_BLE`
- **Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- **Data Characteristic:** `beb5483e-36e1-4688-b7f5-ea07361b26a8` *(READ + NOTIFY)* — Menerima streaming JSON biometrik.
- **Command Characteristic:** `beb5483e-36e1-4688-b7f5-ea07361b26a9` *(WRITE)* — Mengirim perintah interaktif (contoh: `"ping"` yang dibalas `{"pong":1}`).

### Format Data JSON (Stream Telemetri)
```json
{
  "worn": 1,
  "hr": 75,
  "ibi": 800,
  "hrv": 45,
  "st": 42,
  "t": 36.5,
  "g": 35,
  "ir": 120500,
  "ss": 31,
  "ts": 128,
  "ax": 0.12,
  "ay": -0.05,
  "az": 9.81
}
```

| Field JSON | Tipe / Satuan | Keterangan & Penanganan di Aplikasi |
| :--- | :--- | :--- |
| `worn` | `int (0/1)` | Deteksi pemakaian pada pergelangan tangan. Jika `0`, UI menampilkan banner peringatan & standby status. |
| `hr` | `int (BPM)` | Detak jantung per menit dari sensor PPG MAX30102. |
| `ibi` | `int (ms)` | Inter-Beat Interval (durasi jeda antar detak fisiologis). |
| `hrv` | `int (ms)` | RMSSD Heart Rate Variability. Nilai `-1` menandakan fase inisialisasi / kalibrasi. |
| `st` | `int (0–100)` | Indeks Stres Fusi multi-sensor hasil kalkulasi algoritma Kalman & EMA di firmware. |
| `t` | `double (°C)` | Suhu inframerah permukaan kulit tubuh dari MLX90614. |
| `g` | `int (0–100%)` | Konduktansi kulit respon saraf simpatis (Galvanic Skin Response). |
| `ir` | `int (raw)` | Intensitas refleksi inframerah MAX30102 untuk validasi kontak kulit. |
| `ss` | `int (bitmask)` | **Sensor Health Bitmask:** bit0=HR, bit1=HRV, bit2=GSR, bit3=Temp, bit4=IMU (31 = semua optimal). |
| `ts` | `int (detik)` | Uptime perangkat sejak menyala. |
| `ax, ay, az` | `double (m/s²)` | Data akselerometer 3-sumbu MPU6050 pengukur intensitas gerak tubuh. |

> ⌚ **Hardware Firmware:**
> Source code firmware Arduino / ESP32-C3 tersedia di [mindtrack-wearable](https://github.com/ujangsprr/mindtrack-wearable.git).

---

## 🛠️ Panduan Build & Running

### 🤖 Android
1. **Persiapan:** Aktifkan **USB Debugging** dan **Location/GPS** pada perangkat fisik.
2. **Build Release (APK):** Aturan ProGuard dikelola via `android/app/proguard-rules.pro`.
3. **Run:** `flutter run --release`

### 🍎 iOS
1. **Persiapan:** Buka `ios/Runner.xcworkspace` di Xcode dan atur **Signing & Capabilities**.
2. **Izin Privasi:** Bluetooth, Kamera, dan Galeri dikonfigurasi di `Info.plist`.
3. **Run:** `flutter run --release`

### 💻 Simulator vs Physical Device
| Fitur | Simulator (iOS/Android) | Device Fisik |
|-------|--------------------------|--------------|
| **Koneksi BLE** | ❌ (Mock Data) | ✅ Berfungsi Penuh |
| **Edit Foto** | ✅ Berfungsi | ✅ Berfungsi |
| **Analisis Stres** | ✅ Berfungsi (via Mock) | ✅ Berfungsi (via Sensor) |

---

## 🗂️ Struktur Proyek

```
lib/
├── main.dart                  # Entry Point & Navigasi Utama
├── dashboard_screen.dart      # Dashboard Utama & Kartu Analisis
├── history_screen.dart        # Grafik Riwayat Stres 24 Jam
├── models/
│   ├── sensor_data.dart       # Logika Matriks Keputusan & Analisis Stres
│   └── user_profile.dart      # Model User + Dinamic Age & BMI logic
├── screens/
│   ├── onboarding_screen.dart # Setup profil awal & intro modern
│   ├── profile_screen.dart    # Management profil & Image Cropper
│   ├── scan_screen.dart       # BLE Scanner (ESP32)
│   ├── stress_edu_screen.dart # Modul edukasi manajemen stres
│   └── sensor_detail_screen.dart # Detail data mentah sensor
├── services/
│   ├── ble_service.dart       # BLE Engine with JSON Buffering
│   └── storage_service.dart   # Persistensi data lokal (SharedPreferences)
└── widgets/
    ├── stress_indicator.dart  # Custom Gauges & Progress Indicators
    ├── info_card.dart         # UI Card reusable untuk sensor
    └── app_watermark.dart     # Label branding aplikasi
```

---

## 📄 Lisensi & Kontributor
Proyek ini dirilis di bawah lisensi MIT.  
Dikembangkan oleh [Ujang](https://github.com/ujangsprr) sebagai solusi IoT untuk pemantauan kesehatan mental & biometrik.
