# Panduan Kompilasi & Eksekusi: MindTrack Pro (Android & iOS)

Dokumen ini menyediakan instruksi teknis untuk instalasi dependensi, pengujian lokal, serta proses kompilasi rilis (*release build*) aplikasi MindTrack Pro pada platform Android dan iOS.

---

## 1. Prasyarat Lingkungan Pengembangan

Sebelum memulai proses *build*, pastikan perangkat kerja macOS telah memenuhi spesifikasi dependensi berikut:

| Perangkat Lunak | Versi Rekomendasi | Fungsi |
| :--- | :--- | :--- |
| **Flutter SDK** | `>= 3.24.x` (Channel stable) | Kerangka kerja pengembangan lintas platform. |
| **Xcode** | `>= 15.0` | Kompilasi rantai alat iOS dan simulator CoreSimulator. |
| **CocoaPods** | `>= 1.14.x` | Manajemen paket dependensi native iOS. |
| **Android Studio / SDK** | API level 34 (`Android 14`) | Android SDK Build-Tools, Platform-Tools, dan AVD Manager. |
| **Java Development Kit (JDK)**| JDK 17 | Kompatibilitas terhadap Gradle daemon. |

Jalankan pemeriksaan kesiapan konfigurasi sistem:
```bash
flutter doctor -v
```

---

## 2. Inisialisasi Proyek

1. Navigasikan terminal ke direktori root proyek:
   ```bash
   cd "/Users/ujang/Jam Pintar/MindTrack/MindTrack"
   ```

2. Unduh pustaka dependensi Dart:
   ```bash
   flutter pub get
   ```

3. *(Opsional)* Jika melakukan pembersihan cache atau setelah migrasi dependensi pod:
   ```bash
   flutter clean
   flutter pub get
   cd ios && pod install --repo-update && cd ..
   ```

---

## 3. Platform iOS

### A. Eksekusi pada Simulator iOS
Simulator iOS dapat digunakan untuk menguji fungsionalitas UI, navigasi, dan algoritma normalisasi stres menggunakan generator telemetri simulasi (*Mock Data*).

1. Periksa ketersediaan simulator yang terpasang:
   ```bash
   flutter emulators
   ```

2. Jalankan simulator:
   ```bash
   flutter emulators --launch apple_ios_simulator
   ```

3. Jalankan aplikasi pada simulator aktif:
   ```bash
   flutter run -d ios
   ```

### B. Kompilasi Khusus Simulator (Validasi Build)
```bash
flutter build ios --simulator
```
Hasil artefak:  
`build/ios/iphonesimulator/Runner.app`

### C. Eksekusi pada Perangkat Fisik iPhone (Uji Coba BLE)
Pengujian konektivitas nirkabel terhadap mikrokontroler ESP32 memerlukan modul Bluetooth fisik pada perangkat nyata.

1. Hubungkan iPhone ke komputer Mac menggunakan kabel USB.
2. Buka proyek kerja Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
3. Di dalam antarmuka Xcode:
   - Pilih target **Runner** > panel **Signing & Capabilities**.
   - Tentukan akun pengembang pada menu dropdown **Team**.
   - Sesuaikan **Bundle Identifier** unik jika diperlukan.
4. Pada perangkat iPhone:
   - Aktifkan **Developer Mode** (*Settings > Privacy & Security > Developer Mode*).
   - Berikan izin *Trust Developer* (*Settings > General > VPN & Device Management*).
5. Jalankan aplikasi melalui terminal:
   ```bash
   flutter run -d <DEVICE_ID_IPHONE>
   ```

### D. Kompilasi Distribusi Rilis (.ipa / TestFlight)
```bash
flutter build ipa --release
```
Hasil arsip tersimpan pada direktori `build/ios/archive/Runner.xcarchive` untuk diunggah ke App Store Connect.

---

## 4. Platform Android

### A. Eksekusi pada Android Emulator (AVD)
1. Periksa daftar profil perangkat virtual Android:
   ```bash
   flutter emulators
   ```

2. Jalankan emulator:
   ```bash
   flutter emulators --launch Medium_Phone_API_36.1
   ```
   *Catatan: Pastikan kapasitas penyimpanan hard drive memiliki ruang kosong sekurang-kurangnya 3–5 GB.*

3. Luncurkan aplikasi ke emulator:
   ```bash
   flutter run -d android
   ```

### B. Eksekusi pada Perangkat Fisik Android (Uji Coba BLE)
1. Aktifkan mode pengembang pada ponsel Android:  
   *Pengaturan > Tentang Ponsel > Ketuk "Nomor Versi" sebanyak 7 kali.*
2. Masuk ke menu *Opsi Pengembang (Developer Options)* dan aktifkan **USB Debugging**.
3. Hubungkan ponsel via kabel data dan setujui dialog otorisasi kunci RSA.
4. Verifikasi deteksi perangkat:
   ```bash
   flutter devices
   ```
5. Jalankan aplikasi:
   ```bash
   flutter run -d <DEVICE_ID_ANDROID>
   ```

### C. Kompilasi Debug APK
Digunakan untuk instalasi pengujian internal secara cepat tanpa penandatanganan rilis:
```bash
flutter build apk --debug
```
Hasil biner:  
`build/app/outputs/flutter-apk/app-debug.apk`

### D. Kompilasi Produksi (Release APK & App Bundle)

1. **Standalone Release APK:**
   ```bash
   flutter build apk --release
   ```
   Hasil biner:  
   `build/app/outputs/flutter-apk/app-release.apk`

2. **Google Play App Bundle (.aab):**
   ```bash
   flutter build appbundle --release
   ```
   Hasil bundel:  
   `build/app/outputs/bundle/release/app-release.aab`

---

## 5. Ringkasan Perintah Debugging Terminal

Saat sesi `flutter run` aktif pada jendela terminal, gunakan pintasan berikut untuk berinteraksi dengan lingkungan aplikasi:

| Perintah | Deskripsi |
| :---: | :--- |
| `r` | **Hot Reload** — Memperbarui perubahan kode antarmuka tanpa mereset status aplikasi. |
| `R` | **Hot Restart** — Merestart status siklus hidup aplikasi dari halaman awal. |
| `h` | **Daftar Bantuan** — Menampilkan daftar lengkap pintasan diagnostik runtime. |
| `d` | **Detach Session** — Menghentikan proses pelacakan terminal tanpa menutup aplikasi di perangkat. |
| `q` | **Terminate** — Menutup aplikasi dan menghentikan proses eksekusi. |

---

## 6. Prosedur Penanganan Kendala (Troubleshooting)

1. **Kendala Kapasitas Disk Penuh (`No space left on device`):**
   - Hapus cache Xcode sementara:
     ```bash
     rm -rf ~/Library/Developer/Xcode/DerivedData/*
     ```
   - Hapus direktori build sementara Flutter:
     ```bash
     flutter clean
     ```
2. **Inkonsistensi Integrasi CocoaPods:**
   - Hapus lockfile dan instal ulang pod:
     ```bash
     cd ios && rm -rf Podfile.lock Pods && pod install && cd ..
     ```
3. **Pemindaian BLE Tidak Menampilkan Perangkat pada Android:**
   - Pastikan layanan **Lokasi (GPS)** dan **Bluetooth** aktif secara simultan.
   - Periksa izin runtime aplikasi pada menu pengaturan ponsel untuk memastikan hak akses *Perangkat Terdekat (Nearby Devices)* telah diberikan.
