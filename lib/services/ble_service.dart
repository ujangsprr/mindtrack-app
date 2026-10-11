import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  String? get connectedDeviceName => _connectedDevice?.platformName;
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
  // SCANNING
  // ═══════════════════════════════════════════════════════════════════════

  /// Start scanning for BLE devices.
  /// Results are filtered to show devices with a name (ignore unnamed).
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;

    _scanResults.clear();
    _isScanning = true;
    notifyListeners();

    try {
      // Listen for scan results
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        _scanResults.clear();
        for (final r in results) {
          // Only show devices that advertise a name
          if (r.device.platformName.isNotEmpty) {
            _scanResults.add(r);
          }
        }
        notifyListeners();
      });

      // Start the scan with timeout
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop an on-going scan immediately.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONNECTING
  // ═══════════════════════════════════════════════════════════════════════

  /// Connect to a BLE device, discover services, and subscribe to the
  /// MindTrack data characteristic (Notify).
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      debugPrint('[BLE] Connecting to ${device.platformName}...');

      // Connect with auto-reconnect disabled so we can manage it ourselves
      await device.connect(license: License.free, autoConnect: false, timeout: const Duration(seconds: 10));

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
