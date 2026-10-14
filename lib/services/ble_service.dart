import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data.dart';

/// BLE (Bluetooth Low Energy) service for MindTrack.
///
/// Handles scanning, connecting, and receiving compact JSON sensor data
/// from a MindTrack wearable device via BLE Notify (500 ms interval).
///
/// ## ESP32 JSON Format (~300 bytes)
/// ```json
/// {"hr":95,"ibi":630,"hrv":28,"st":62,"t":35.8,
///  "g":72,"ir":123456,"ax":0.12,"ay":0.05,"az":0.98,"ts":171932123}
/// ```
/// Key mapping: hr=Heart Rate(BPM), ibi=Inter-Beat Interval(ms),
/// hrv=HRV SDNN(ms), st=Stress(0-100), t=Temp °C, g=GSR %(0-100),
/// ir=IR raw, ax/ay/az=Accel m/s², ts=uptime s
///
/// ## UUIDs
/// - Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
/// - Data Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
/// - Command Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a9`
class BleService extends ChangeNotifier {
  // ── MindTrack GATT UUIDs ───────────────────────────────────────────────────
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String dataCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String cmdCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';

  // ── Connection state ───────────────────────────────────────────────────
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  BluetoothCharacteristic? _cmdChar;
  bool get canSendCommand => _cmdChar != null;

  DateTime? _lastPongTime;
  DateTime? get lastPongTime => _lastPongTime;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool get isConnected => _connectedDevice != null;

  String? _customConnectedName;
  String? get connectedDeviceName =>
      _customConnectedName ??
      (_connectedDevice?.platformName.isNotEmpty == true
          ? _connectedDevice!.platformName
          : 'MindTrack Wearable');
  String? get connectedDeviceId => _connectedDevice?.remoteId.str;

  // ── Data streams ───────────────────────────────────────────────────────

  /// Stream of parsed sensor readings arriving from the device.
  final StreamController<SensorData> _dataController =
      StreamController<SensorData>.broadcast();
  Stream<SensorData> get dataStream => _dataController.stream;

  /// Last successfully received reading (useful for immediate display).
  SensorData? _lastReading;
  SensorData? get lastReading => _lastReading;

  /// History buffer kept in-memory (capped at 500 entries).
  final List<SensorData> _history = [];
  List<SensorData> get history => List.unmodifiable(_history);

  // ── Scan results ───────────────────────────────────────────────────────
  final List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  // ── Internal subscriptions ─────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  // ── Partial buffer for chunked JSON ────────────────────────────────────
  String _jsonBuffer = '';

  // ═══════════════════════════════════════════════════════════════════════
  // PERMISSIONS & ADAPTER CHECK
  // ═══════════════════════════════════════════════════════════════════════

  /// Request needed Bluetooth and Location permissions (especially for Android 12+)
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? true;
      final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;
      final locGranted = statuses[Permission.location]?.isGranted ?? true;

      return (scanGranted && connectGranted) || locGranted;
    } catch (e) {
      debugPrint('[BLE] Permission request error: $e');
      return false;
    }
  }

  /// Get friendly display name for a scanned device
  static String getDeviceName(ScanResult result) {
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return 'MindTrack Device (${result.device.remoteId.str.substring(0, 5)})';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCANNING
  // ═══════════════════════════════════════════════════════════════════════

  /// Start scanning for BLE devices.
  /// Automatically requests permissions and checks Bluetooth adapter status.
  Future<BleScanStatus> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return BleScanStatus.alreadyScanning;

    // 1. Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint('[BLE] Bluetooth not supported by this device.');
      return BleScanStatus.notSupported;
    }

    // 2. Request permissions on Android
    final granted = await requestPermissions();
    if (!granted) {
      debugPrint('[BLE] Bluetooth / Location permissions not granted.');
      return BleScanStatus.permissionDenied;
    }

    // 3. Check if Bluetooth is turned on
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      // Try to turn on Bluetooth automatically on Android
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
          // Short wait to see if adapter turns on
          await Future.delayed(const Duration(milliseconds: 1000));
          adapterState = await FlutterBluePlus.adapterState.first;
        } catch (_) {}
      }

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('[BLE] Bluetooth is OFF.');
        return BleScanStatus.bluetoothOff;
      }
    }

    _scanResults.clear();
    _isScanning = true;
    notifyListeners();

    try {
      // Listen for scan results
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        _scanResults.clear();
        for (final r in results) {
          final advName = r.advertisementData.advName;
          final platName = r.device.platformName;
          final name = advName.isNotEmpty ? advName : platName;

          final matchesUuid = r.advertisementData.serviceUuids
              .any((u) => u.toString().toLowerCase() == serviceUuid.toLowerCase());
          final matchesName = name.toLowerCase().contains('mindtrack');

          // Include device if it has a name, matches service UUID, or is MindTrack
          if (name.isNotEmpty || matchesUuid || matchesName) {
            _scanResults.add(r);
          }
        }

        // Sort MindTrack devices first, then by signal strength (RSSI)
        _scanResults.sort((a, b) {
          final aName = getDeviceName(a).toLowerCase();
          final bName = getDeviceName(b).toLowerCase();
          final aIsMT = aName.contains('mindtrack');
          final bIsMT = bName.contains('mindtrack');

          if (aIsMT && !bIsMT) return -1;
          if (!aIsMT && bIsMT) return 1;
          return b.rssi.compareTo(a.rssi);
        });

        notifyListeners();
      });

      // Start scan
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      return BleScanStatus.success;
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
      return BleScanStatus.error;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop an on-going scan immediately.
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanSub?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONNECTING
  // ═══════════════════════════════════════════════════════════════════════

  /// Connect to a BLE device, discover services, and subscribe to the
  /// MindTrack data characteristic (Notify).
  Future<bool> connectToDevice(BluetoothDevice device, {String? customName}) async {
    try {
      _customConnectedName = customName;
      debugPrint('[BLE] Connecting to ${device.platformName} (${device.remoteId})...');

      // Connect
      await device.connect(
        license: License.free,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      // Request MTU 247 on Android for non-fragmented JSON transfer
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(247);
        } catch (_) {}
      }

      // Wait a moment for GATT to stabilize
      await Future.delayed(const Duration(milliseconds: 500));

      // Discover GATT services
      final services = await device.discoverServices();

      // Find the MindTrack service by UUID
      BluetoothService? targetService;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == serviceUuid) {
          targetService = s;
          break;
        }
      }

      if (targetService == null) {
        debugPrint('[BLE] MindTrack service not found on this device.');
        await device.disconnect();
        return false;
      }

      // Find data and command characteristics
      BluetoothCharacteristic? dataChr;
      _cmdChar = null;
      for (final c in targetService.characteristics) {
        final uuidStr = c.uuid.toString().toLowerCase();
        if (uuidStr == dataCharUuid) {
          dataChr = c;
        } else if (uuidStr == cmdCharUuid) {
          _cmdChar = c;
        }
      }

      if (dataChr == null) {
        debugPrint('[BLE] Data characteristic not found.');
        await device.disconnect();
        return false;
      }

      // Subscribe to Notify
      await dataChr.setNotifyValue(true);
      _notifySub = dataChr.onValueReceived.listen(_onBleDataReceived);

      // Listen for disconnection events
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDeviceDisconnected();
        }
      });

      _connectedDevice = device;
      _jsonBuffer = '';
      notifyListeners();

      debugPrint('[BLE] Connected & subscribed to ${device.platformName} (Command available: ${_cmdChar != null})');
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      return false;
    }
  }

  /// Send a string command to the wearable (via CHAR_CMD_UUID)
  Future<bool> sendCommand(String command) async {
    if (_cmdChar == null) {
      debugPrint('[BLE] Command characteristic not ready.');
      return false;
    }
    try {
      final bytes = utf8.encode(command);
      await _cmdChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent command to device: $command');
      return true;
    } catch (e) {
      debugPrint('[BLE] Error sending command: $e');
      return false;
    }
  }

  /// Ping the wearable to test bidirectional link (device responds with {"pong":1})
  Future<bool> sendPing() => sendCommand('ping');

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _cmdChar = null;
    _jsonBuffer = '';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DATA PARSING
  // ═══════════════════════════════════════════════════════════════════════

  /// Called when raw bytes arrive via BLE Notify.
  /// MindTrack device sends compact JSON:
  /// {"worn":1,"hr":75,"ibi":800,"hrv":42,"st":34,"t":36.5,"g":30,"ir":120500,"ss":31,"ts":128}
  ///
  /// BLE MTU can be as small as 20 bytes, so the JSON may arrive split
  /// across multiple packets. We buffer until we receive a complete JSON object.
  void _onBleDataReceived(List<int> rawBytes) {
    try {
      final chunk = utf8.decode(rawBytes, allowMalformed: true);
      _jsonBuffer += chunk;

      // Process all complete JSON objects found in buffer
      while (true) {
        final openIdx = _jsonBuffer.indexOf('{');
        if (openIdx == -1) {
          // No opening brace yet, clear garbage
          _jsonBuffer = '';
          return;
        }

        final closeIdx = _jsonBuffer.indexOf('}', openIdx);
        if (closeIdx == -1) {
          // Incomplete JSON, wait for more chunks
          return;
        }

        // Extract the complete JSON object
        final jsonStr = _jsonBuffer.substring(openIdx, closeIdx + 1);
        _jsonBuffer = _jsonBuffer.substring(closeIdx + 1);

        final map = jsonDecode(jsonStr) as Map<String, dynamic>;

        // 1. Check for ping-pong response
        if (map.containsKey('pong')) {
          debugPrint('[BLE] Pong received from wearable!');
          _lastPongTime = DateTime.now();
          notifyListeners();
          continue;
        }

        // 2. Check for TEST_BLE mode payload
        if (map.containsKey('test')) {
          debugPrint('[BLE] Test BLE packet received: n=${map['n']}, ts=${map['ts']}');
          continue;
        }

        // 3. Normal sensor payload
        final data = SensorData.fromBleJson(map);

        _lastReading = data;
        _dataController.add(data);

        // Keep history (max 500 entries)
        _history.add(data);
        if (_history.length > 500) {
          _history.removeAt(0);
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('[BLE] Parse error: $e');
    }
  }

  /// Called when the device unexpectedly disconnects.
  void _onDeviceDisconnected() {
    debugPrint('[BLE] Device disconnected');
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _connectedDevice = null;
    _cmdChar = null;
    _jsonBuffer = '';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _dataController.close();
    super.dispose();
  }
}

/// Status result when starting BLE scan
enum BleScanStatus {
  success,
  alreadyScanning,
  bluetoothOff,
  permissionDenied,
  notSupported,
  error,
}

