# SeekNirvana Complete SDK Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [SDK Best Practices Compliance](#sdk-best-practices-compliance)
3. [Data Flow: Ring → Native → Flutter](#data-flow-ring--native--flutter)
4. [Feature Capability Matrix](#feature-capability-matrix)
5. [Implementation Guidelines](#implementation-guidelines)
6. [Calculation Algorithms](#calculation-algorithms)
7. [SDK Interface Reference](#sdk-interface-reference)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Flutter UI (Dart)                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │   Providers  │  │   Services   │  │   Screens    │  │  Feature Detection│ │
│  │  (Riverpod)  │  │(RingDataSvc) │  │   (Widgets)  │  │   (Capability)   │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘ │
│         │                 │                 │                   │           │
│         └─────────────────┼─────────────────┼───────────────────┘           │
│                           │                 │                               │
│                    RingPlugin (Dart)        │                               │
│                   (MethodChannel API)       │                               │
└───────────────────────────┬─────────────────┼───────────────────────────────┘
                            │                 │
                    MethodChannel/EventChannel│
                            │                 │
┌───────────────────────────┼─────────────────┼───────────────────────────────┐
│                      RingPlugin.kt (Android) │  RingPlugin.swift (iOS)       │
│                   (FlutterPlugin +           │  (FlutterPlugin +             │
│                    IResponseListener)        │   BCLRingManager)             │
│  ┌──────────────┐  ┌──────────────┐         │  ┌──────────────┐             │
│  │   LmAPI.*    │  │   BLEUtils   │         │  │BCLRingManager│             │
│  │   Commands   │  │  (Connect)   │         │  │  (Composite) │             │
│  └──────┬───────┘  └──────┬───────┘         │  └──────┬───────┘             │
│         │                 │                 │         │                     │
│         └─────────────────┼─────────────────┼─────────┘                     │
│                           │                 │                               │
│                    ChipletRing SDK          │       BCLRingSDK              │
│                     (v1.0.44)               │      (v1.1.29)                │
│                   (com.lm.sdk.*)            │                               │
└───────────────────────────┬─────────────────┼───────────────────────────────┘
                            │                 │
                           BLE               BLE
                            │                 │
┌───────────────────────────┼─────────────────┼───────────────────────────────┐
│                      Smart Ring Hardware                                     │
│              (PPG + Temp + Accelerometer + Gyroscope)                        │
│                                                                              │
│  Features Supported (varies by model):                                       │
│  • Heart Rate & HRV           • Blood Pressure (specific models)            │
│  • SpO2                       • Blood Glucose (specific models)              │
│  • Temperature                • ECG (specific models)                       │
│  • Step Count                 • Voice Recording (specific models)            │
│  • Sleep Tracking             • HID Gestures (specific models)               │
│  • Vibration/Alarms           • File System (specific models)                │
│  • Sport Mode                 • 6-Axis Sensor (specific models)              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## SDK Best Practices Compliance

### ⏱️ Command Timing Requirements (MANDATORY)

| Requirement | Specification | Implementation Status |
|-------------|---------------|----------------------|
| Post-Connection Delay | Wait **3 seconds** after BLE connect before sending commands | ⚠️ **NOT IMPLEMENTED** (Currently 500ms) |
| Command Spacing | **300ms minimum** between consecutive commands | ⚠️ **NOT IMPLEMENTED** (Currently ~200ms) |
| Sequential Execution | Never send multiple commands simultaneously | ⚠️ **PARTIAL** (Needs command queue) |
| History Sync Blocking | No measurements during history sync | ⚠️ **NOT IMPLEMENTED** |

### 📋 Composite Command Usage (STRONGLY RECOMMENDED)

**iOS Implementation (REQUIRED):**
```swift
// Use appEventConnectRing instead of individual commands
BCLRingManager.shared.appEventConnectRing(
    date: Date(),
    timeZone: BCLRingTimeZone.getCurrentSystemTimeZone(),
    filterTime: nil,
    callbacks: dataSyncCallbacks
) { result in
    // Single response contains:
    // - firmwareVersion, hardwareVersion
    // - batteryLevel, chargingState
    // - stepCount, collectInterval
    // - selfInspection results
    // - HID support flags
    // - Feature capability flags
    // - PLUS automatic history sync
}
```

**Android Implementation:**
```kotlin
// Check for LmAPILite composite command availability
// If not available, implement 300ms spacing between individual commands
```

### 🔍 Feature Capability Detection (REQUIRED)

**Capabilities to Detect After Connection:**

| Capability Flag | Description | UI Impact |
|-----------------|-------------|-----------|
| `isHIDSupported` | Gesture control available | Show/Hide gesture settings |
| `isBloodPressureMeasurementSupported` | BP measurement available | Show/Hide BP card |
| `isBloodGlucoseMeasurementSupported` | BG measurement available | Show/Hide glucose feature |
| `isEcgFunctionSupported` | ECG recording available | Show/Hide ECG feature |
| `isVibrationAlarmSupported` | Vibration/alarms available | Show/Hide alarm settings |
| `isVoiceRecordingSupported` | Audio recording available | Show/Hide voice feature |
| `isFileSystemSupported` | File storage available | Show/Hide file manager |
| `isSportModeSupported` | Exercise tracking available | Show/Hide sport mode |
| `isGoMoreSleepAlgorithmSupported` | Advanced sleep algorithm | Use GoMore vs Traditional |

---

## Data Flow: Ring → Native → Flutter

### 1. Connection Flow (WITH COMPOSITE COMMAND)

```
User taps "Connect" → RingPlugin.connect(mac) → MethodChannel
                            ↓
                    ┌───────┴───────┐
                    ↓               ↓
            Android (Kotlin)    iOS (Swift)
                    ↓               ↓
            BLEUtils.connect   BCLRingManager.startConnect
                    ↓               ↓
            lmBleConnectionSucceeded
                    ↓
            WAIT 3 SECONDS (per documentation)
                    ↓
            ┌───────┴───────┐
            ↓               ↓
    Individual Commands   Composite Command
    (Android fallback)    (iOS preferred)
            ↓               ↓
    GET_BATTERY        appEventConnectRing
    GET_VERSION (HW)        ↓
    GET_VERSION (SW)   All device info + capabilities
    SYNC_TIME               ↓
    STEP_COUNTING      Auto history sync
    READ_HISTORY            ↓
            ↓               ↓
    scanEventSink.success(deviceList) → Flutter Stream
```

### 2. Real-time Measurement Flow

**Heart Rate Measurement:**
```
User taps "Measure HR" → RingPlugin.startHeartRate() → MethodChannel
                                ↓
                        LmAPI.GET_HEART_ROTA(0x01, 0x30, listener)
                        BCLRingManager.shared.startHeartRate()
                                ↓
                        Smart Ring starts PPG measurement
                                ↓
                        ┌──────────────┬──────────────┬──────────────┐
                        ↓              ↓              ↓              ↓
                    progress()   resultData()   waveformData()   rriData()
                    (0-100%)     (HR/HRV/Stress)   (PPG)         (RR intervals)
                        ↓              ↓              ↓              ↓
                        └──────────────┼──────────────┴──────────────┘
                                       ↓
                        sendHealthData() → healthEventSink → Flutter
                                       ↓
                        RingDataService._init() receives event
                                       ↓
                        ref.read(heartRateProvider.notifier).state = data
```

**SpO2 Measurement:**
```
RingPlugin.startSpO2() → LmAPI.GET_HEART_Q2() / BCLRingManager.shared.startBloodOxygen()
                                ↓
                        IQ2Listener / BCLBloodOxygenResponse
                                ↓
                        resultData(heart, spo2, temp)
                                ↓
                        sendHealthData("spo2", {...})
```

**Blood Pressure (Android - Estimation):**
```
RingPlugin.startBloodPressure() → Custom estimation algorithm
                                        ↓
                                Start HR measurement for data collection
                                        ↓
                                Collect PPG waveform data
                                        ↓
                                Extract peaks/valleys from signal
                                        ↓
                                Calculate amplitude and variation
                                        ↓
                                Estimate systolic/diastolic values
                                        ↓
                                Apply physiological limits (90-180/60-110)
                                        ↓
                                sendHealthData("bloodPressure", {...})
```

### 3. History/Sleep Data Sync Flow

```
On connect (composite cmd) → Automatic history sync starts
                                    ↓
                            IHistoryListener / BCLDataSyncCallbacks
                                    ↓
                            ┌───────┴───────┐
                            ↓               ↓
                        progress()      onCompleted()
                        (per record)    (all records)
                            ↓               ↓
                    sendHealthData()    Sleep calculation
                    ("historyData")         ↓
                            ↓         GoMore algorithm OR
                            ↓         Traditional calculation
                            ↓               ↓
                            └───────────────┤
                                            ↓
                                    RingDataService processing
                                            ↓
                                    Sleep stage aggregation
                                            ↓
                                    Update sleep providers
```

### 4. Event Types Reference

| Event Type | Source | Data Fields | Flutter Provider | Platform |
|------------|--------|-------------|------------------|----------|
| `heartRate` | IHeartListener | `heartRate`, `hrv`, `stress`, `temperature` | `heartRateProvider` | Both |
| `heartRateProgress` | IHeartListener | `progress` (0-100) | `heartRateMeasuringProvider` | Both |
| `heartWaveform` | IHeartListener | `data` (CSV) | `ppgWaveformProvider` | Both |
| `spo2` | IQ2Listener | `heartRate`, `spo2`, `temperature` | `spo2Provider` | Both |
| `temperature` | ITempListener | `temperature` (×10) | `temperatureProvider` | Both |
| `bloodPressure` | Estimated/Native | `systolic`, `diastolic`, `confidence` | BP providers | Varies |
| `historyData` | IHistoryListener | Full record | Sleep providers | Both |
| `battery` | IResponseListener | `level`, `isCharging` | `batteryLevelProvider` | Both |
| `version` | IResponseListener | `versionType`, `version` | `firmwareVersionProvider` | Both |
| `steps` | IResponseListener | `steps` | `stepsProvider` | Both |
| `rssi` | BLE Callback | `rssi` | Connection quality | Both |
| `capabilityFlags` | Composite Cmd | Feature flags | Feature detection | iOS |

---

## Feature Capability Matrix

### Core Features (All Models)

| Feature | Android | iOS | Status | Notes |
|---------|---------|-----|--------|-------|
| BLE Scan | ✅ | ✅ | Complete | Filter by name "Ring" |
| Connect/Disconnect | ✅ | ✅ | Complete | With auto-reconnect |
| Battery Level | ✅ | ✅ | Complete | Includes charging state |
| Firmware Version | ✅ | ✅ | Complete | HW + SW versions |
| Time Sync | ✅ | ✅ | Complete | Auto on connect |
| Step Count | ✅ | ✅ | Complete | Daily accumulation |
| Heart Rate | ✅ | ✅ | Complete | With HRV + Stress |
| SpO2 | ✅ | ✅ | Complete | With temperature |
| Temperature | ✅ | ✅ | Complete | From HR/SpO2 or direct |
| History Sync | ✅ | ✅ | Complete | 5-min interval records |

### Extended Features (Model-Dependent)

| Feature | Android | iOS | Detection Method | Implementation |
|---------|---------|-----|------------------|----------------|
| Blood Pressure | ⚠️ Estimation | ✅ Native | `isBloodPressureMeasurementSupported` | Check before showing |
| Blood Glucose | ❌ | ❌ | `isBloodGlucoseMeasurementSupported` | Future firmware |
| Vibration/Alarms | ❌ | ✅ | `isVibrationAlarmSupported` | iOS only currently |
| HID Gestures | ❌ | ✅ | `isHIDSupported` | Touch + Gesture modes |
| Voice Recording | ❌ | ❌ | `isMicrophoneSupported` | Specific models |
| ECG | ❌ | ❌ | `isEcgFunctionSupported` | ECG-specific rings |
| File System | ❌ | ❌ | `isFileSystemSupported` | Data logging models |
| Sport Mode | ❌ | ❌ | `isSportModeSupported` | Exercise tracking |
| GoMore Sleep | ❌ | ❌ | `isGoMoreSleepAlgorithmSupported` | Advanced sleep |

### iOS-Only Features (BCLRingSDK v1.1.29)

| Feature | Status | Notes |
|---------|--------|-------|
| Clear Steps | ✅ | `clearStepCount()` |
| Delete History | ✅ | `deleteRingAllHistoryData()` |
| Bluetooth Name | ✅ | Get/Set Bluetooth name |
| Personal Info | ✅ | Sex/Age/Height/Weight |
| Factory Reset | ✅ | `restoreFactorySettings()` |
| Collection Period | ✅ | Set/Get measurement interval |
| PPG Settings | ✅ | Frequency and status |
| Sensor Status | ✅ | Gyro/Accel/Temp/PPG status |
| Auto Collection | ✅ | Enable/disable auto-measure |
| Self Inspection | ✅ | `oneKeySelfInspection()` |
| HID Mode | ✅ | Touch/Gesture control |
| RSSI Monitoring | ✅ | `startReadRSSI()` |

### Android-Only Features

| Feature | Status | Notes |
|---------|--------|-------|
| LmAPILite | ✅ | Simplified API with native types |
| Temperature Testing | ✅ | `ITempListener.testing()` |
| PPG Waveform BP | ✅ | Raw PPG data for BP estimation |
| Foreground Service | ⚠️ | Needs implementation |

---

## Implementation Guidelines

### 1. Command Queue Implementation (REQUIRED)

```kotlin
// Android: CommandQueue.kt
class CommandQueue {
    private val handler = Handler(Looper.getMainLooper())
    private var lastCommandTime = 0L
    private val commandInterval = 300L // 300ms per documentation
    
    fun enqueue(command: () -> Unit) {
        val now = System.currentTimeMillis()
        val timeSinceLastCommand = now - lastCommandTime
        val delay = if (timeSinceLastCommand < commandInterval) {
            commandInterval - timeSinceLastCommand
        } else 0
        
        handler.postDelayed({
            command()
            lastCommandTime = System.currentTimeMillis()
        }, delay)
    }
    
    fun clear() {
        handler.removeCallbacksAndMessages(null)
        lastCommandTime = 0
    }
}
```

### 2. Feature Detection Implementation

```dart
// Dart: feature_detection_service.dart
class FeatureDetectionService {
  static Map<String, bool> _capabilities = {};
  
  static void updateCapabilities(Map<String, dynamic> flags) {
    _capabilities = {
      'bpSupported': flags['isBloodPressureMeasurementSupported'] ?? false,
      'vibrationSupported': flags['isVibrationAlarmSupported'] ?? false,
      'hidSupported': flags['isHIDSupported'] ?? false,
      'ecgSupported': flags['isEcgFunctionSupported'] ?? false,
      'voiceSupported': flags['isMicrophoneSupported'] ?? false,
      'fileSystemSupported': flags['isFileSystemSupported'] ?? false,
      'sportModeSupported': flags['isSportModeSupported'] ?? false,
      'goMoreSleep': flags['isGoMoreSleepAlgorithmSupported'] ?? false,
    };
  }
  
  static bool get supportsBloodPressure => _capabilities['bpSupported'] ?? false;
  static bool get supportsVibration => _capabilities['vibrationSupported'] ?? false;
  static bool get supportsHID => _capabilities['hidSupported'] ?? false;
  static bool get supportsECG => _capabilities['ecgSupported'] ?? false;
  // ... etc
}
```

### 3. Android Foreground Service (REQUIRED for reliability)

```kotlin
// Application.onCreate()
BLEUtils.contentTitle = "SeekNirvana - Ring Connected"

val notificationIntent = Intent(this, MainActivity::class.java).apply {
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
}
BLEUtils.pendingIntent = PendingIntent.getActivity(
    this, 0, notificationIntent,
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)
```

### 4. Measurement Guard (Prevents conflicts with history sync)

```dart
// In RingPlugin.dart
static final _commandLock = Lock();
static bool _isHistorySyncing = false;

static Future<void> startHeartRate() async {
  if (_isHistorySyncing) {
    throw RingBusyException('Cannot measure while history is syncing');
  }
  await _commandLock.synchronized(() async {
    await _channel.invokeMethod('startHeartRate');
  });
}

// In RingDataService
void _init() {
  RingPlugin.rawHealthData.listen((data) {
    switch (data['type']) {
      case 'historyStart':
        RingPlugin.setHistorySyncing(true);
        break;
      case 'historyComplete':
      case 'historyError':
        RingPlugin.setHistorySyncing(false);
        break;
    }
  });
}
```

---

## Calculation Algorithms

### 1. HRV (Heart Rate Variability)

**Source:** SDK provides directly via `IHeartListener.resultData(heart, heartRota, yaLi, temp)`

```kotlin
// heartRota = HRV in milliseconds (ms)
override fun resultData(heart: Int, heartRota: Int, yaLi: Int, temp: Int) {
    sendHealthData("heartRate", mapOf(
        "heartRate" to heart,
        "hrv" to heartRota,      // Direct from SDK
        "stress" to yaLi,        // Stress index
        "temperature" to temp
    ))
}
```

**HRV Interpretation:**
| Range (ms) | Interpretation |
|------------|----------------|
| < 20 | Very low (possible health concern) |
| 20-40 | Low |
| 40-60 | Normal |
| 60-80 | Good |
| > 80 | Excellent |

### 2. Sleep Stages

**Source:** History data from `IHistoryListener.progress(progress, historyDataBean)`

**Sleep Type Encoding:**
| Type | Meaning | Duration per Record |
|------|---------|---------------------|
| 0 | Invalid/No sleep | - |
| 1 | Light Sleep | +5 minutes |
| 2 | Deep Sleep | +5 minutes |
| 3 | Awake | +5 minutes (not counted in total) |
| 4 | REM Sleep | +5 minutes |

**Calculation:**
```dart
final deep = ref.read(deepSleepMinutesProvider);
final light = ref.read(lightSleepMinutesProvider);
final rem = ref.read(remSleepMinutesProvider);
final totalSleepHours = (deep + light + rem) / 60.0;
```

### 3. Blood Pressure Estimation (Android)

**⚠️ Warning:** This is an estimation algorithm, not medical-grade measurement.

**Algorithm Steps:**

1. **Collect PPG Data:**
   ```kotlin
   override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
       val values = waveData.split(",").mapNotNull { it.toIntOrNull() }
       bpPpgValues.addAll(values)
   }
   ```

2. **Extract Signal Features:**
   ```kotlin
   // Find peaks and valleys
   val peaks = mutableListOf<Int>()
   val valleys = mutableListOf<Int>()
   
   for (i in 1 until ppgValues.size - 1) {
       if (ppgValues[i] > ppgValues[i-1] && ppgValues[i] > ppgValues[i+1]) {
           peaks.add(ppgValues[i])
       } else if (ppgValues[i] < ppgValues[i-1] && ppgValues[i] < ppgValues[i+1]) {
           valleys.add(ppgValues[i])
       }
   }
   
   val avgPeak = peaks.average()
   val avgValley = valleys.average()
   val amplitude = avgPeak - avgValley
   val peakToPeakVariation = peaks.maxOrNull()?.minus(peaks.minOrNull() ?: 0) ?: 0
   ```

3. **Estimate BP Values:**
   ```kotlin
   var systolic = 115  // Base value
   var diastolic = 75  // Base value
   
   // Higher amplitude → stronger pulse → higher BP
   val normalizedAmp = amplitude / 1000.0
   systolic += (normalizedAmp * 15).toInt().coerceIn(-10, 25)
   diastolic += (normalizedAmp * 8).toInt().coerceIn(-5, 15)
   
   // More variation → arterial stiffness → higher BP
   val variationFactor = peakToPeakVariation / 500.0
   systolic += (variationFactor * 10).toInt().coerceIn(-5, 15)
   
   // Apply limits
   systolic = systolic.coerceIn(90, 180)
   diastolic = diastolic.coerceIn(60, 110)
   
   // Ensure proper pulse pressure (30-60 mmHg)
   if (systolic - diastolic < 30) {
       systolic = diastolic + 35
   } else if (systolic - diastolic > 60) {
       diastolic = systolic - 50
   }
   ```

### 4. Temperature Normalization

**Format Differences:**
| Source | Format | Example |
|--------|--------|---------|
| `ITempListener.resultData()` | ×10 | 365 = 36.5°C |
| `IHeartListener.resultData()` temp | ×100 | 3638 = 36.38°C |
| `IQ2Listener.resultData()` temp | ×100 | 3638 = 36.38°C |

**Conversion:**
```dart
int normalizeTemperature(int rawTemp) {
  // If > 1000, it's likely ×100 format from HR/SpO2
  // Otherwise it's ×10 format from ITempListener
  final normalized = rawTemp > 1000 ? rawTemp / 10 : rawTemp;
  return normalized / 10.0; // Convert to °C
}
```

---

## SDK Interface Reference

### LmAPI Commands (Android)

| Command | Parameters | Description | Response |
|---------|------------|-------------|----------|
| `init(Application)` | `app` | Initialize SDK | - |
| `addWLSCmdListener(Activity, IResponseListener)` | `activity`, `listener` | Register for device events | - |
| `GET_HEART_ROTA(start, freq, listener)` | `0x01/0x00`, `0x30`, `IHeartListener` | Start/stop HR | Callbacks |
| `GET_HEART_Q2(start, listener)` | `0x01/0x00`, `IQ2Listener` | Start/stop SpO2 | Callbacks |
| `READ_TEMP(listener)` | `ITempListener` | Read temperature | Callbacks |
| `GET_BATTERY(type)` | `0x00` | Get battery | `battery()` callback |
| `GET_VERSION(type)` | `0x00` (HW), `0x01` (SW) | Get version | `VERSION()` callback |
| `SYNC_TIME()` | - | Sync time | `syncTime()` callback |
| `STEP_COUNTING()` | - | Get steps | `stepCount()` callback |
| `READ_HISTORY(type, listener)` | `0x01`, `IHistoryListener` | Read history | Callbacks |
| `STOP_BLOOD_PRESSURE_M()` | - | Stop BP | - |
| `GET_SN(listener)` | `ISNListener` | Get serial number | `getSn()` callback |
| `SET_SN(sn, listener)` | `String`, `ISNListener` | Set serial number | `setSn()` callback |
| `SET_HID(bytes, activity)` | `byte[3]`, `Activity` | Set HID mode | `SET_HID()` callback |
| `START_SPORT(listener)` | `ISportListenerLite` | Start sport mode | Callbacks |
| `STOP_SPORT(listener)` | `ISportListenerLite` | Stop sport mode | Callbacks |
| `HIS_SPORT(listener)` | `ISportListenerLite` | Get sport history | Callbacks |
| `STAR_ELEC(listener)` | `IECGListenerLite` | Start ECG | Callbacks |
| `STOP_ELECTROCARDIOGRAM()` | - | Stop ECG | - |

### BCLRingManager (iOS)

| Method | Parameters | Description |
|--------|------------|-------------|
| `startScan()` | `completion` | Scan for devices |
| `stopScan()` | - | Stop scanning |
| `startConnect()` | `device`, `isAutoReconnect`, `completion` | Connect to ring |
| `disconnect()` | - | Disconnect |
| `appEventConnectRing()` | `date`, `timeZone`, `filterTime`, `callbacks`, `completion` | **Composite command** |
| `readBattery()` | `completion` | Get battery |
| `readChargingState()` | `completion` | Get charging status |
| `readFirmware()` | `completion` | Get firmware version |
| `readHardware()` | `completion` | Get hardware version |
| `syncTime()` | `completion` | Sync time |
| `readStepCount()` | `completion` | Get steps |
| `clearStepCount()` | `completion` | Clear steps |
| `startHeartRate()` | `params...`, `completion` | Measure HR |
| `stopHeartRate()` | `completion` | Stop HR |
| `startBloodOxygen()` | `params...`, `completion` | Measure SpO2 |
| `stopBloodOxygen()` | `completion` | Stop SpO2 |
| `startBloodPressure()` | `params...`, `completion` | Measure BP |
| `stopBloodPressure()` | `completion` | Stop BP |
| `readTemperature()` | `completion` | Measure temperature |
| `readUnUploadData()` | `timestamp`, `callbacks`, `completion` | Sync history |
| `deleteRingAllHistoryData()` | `completion` | Delete history |
| `setAlarmClock()` | `items`, `completion` | Set alarms |
| `setBluetoothName()` | `name`, `completion` | Set BT name |
| `getBluetoothName()` | `completion` | Get BT name |
| `setPersonalInformation()` | `params...`, `completion` | Set user info |
| `getPersonalInformation()` | `completion` | Get user info |
| `restoreFactorySettings()` | `completion` | Factory reset |
| `oneKeySelfInspection()` | `completion` | Self inspection |
| `setHIDMode()` | `params...`, `completion` | Set HID mode |
| `linearMotorTimerVibration()` | `seconds`, `type`, `completion` | Vibrate |
| `startReadRSSI()` | `interval`, `callback` | Monitor RSSI |
| `stopReadRSSI()` | - | Stop RSSI |

---

## Troubleshooting

### Connection Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Connect Fail (null)" | Null MAC address | Ensure MAC is saved and passed correctly |
| Connection timeout | BLE interference / Ring not ready | Add 3-second delay after connect |
| Stuck on "Connecting" | Previous bond issue | `BLEUtils.removeBond()` before connect |
| Connection drops | Out of range / Background | Implement foreground service + reconnection |
| Commands timeout | Concurrent commands | Implement 300ms command spacing |
| History sync fails | Measurement in progress | Block measurements during sync |

### Data Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| No HR data | Listener not registered | Register HR listener during init |
| No temperature | Missing HR listener | SDK requires HR listener for temp |
| BP always 118/78 | Not enough PPG data | Ensure proper finger position |
| Sleep data missing | History not synced | Call history sync after connection |
| Steps not updating | 5-min clear ring | Use `GET_CURRENT_STEP_FROM_SERVER` |
| Feature not working | Not supported by ring | Check capability flags first |

### Platform-Specific Issues

| Platform | Issue | Solution |
|----------|-------|----------|
| Android | Background disconnect | Implement foreground service |
| Android | Command conflicts | Use CommandQueue with 300ms spacing |
| iOS | Permission denied | Request Bluetooth permission explicitly |
| Both | Concurrent measurements | Implement measurement guard |

### Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Not worn | Ensure ring is on finger |
| 1 | Reserved | - |
| 2 | Charging (can't measure) | Wait for charging to complete |
| 4 | Busy | Wait for current operation |
| 5 | Data collection timeout | Retry measurement |

---

## References

- [Yongxin SDK Documentation](https://yongxin.gitbook.io/yongxin-docs/documentation)
- [SDK Best Practices](https://yongxin.gitbook.io/yongxin-docs/documentation/zhi-neng-jie-zhi-sdk-shi-yong/zhi-ling-shi-yong-zhu-yi-dian-zhong-yao)
- [Composite Commands](https://yongxin.gitbook.io/yongxin-docs/documentation/zhi-neng-jie-zhi-sdk-shi-yong/er-dai-xie-yi)
- [Android Demo](https://github.com/BravechipSpace/ChipletRing-APPSDK/tree/main/Android/example/ringDemo)
- [iOS Demo](https://github.com/BravechipSpace/ChipletRing-APPSDK/tree/main/IOS/example/BCLRingSDKDemo_New/BCLRingSDKDemo)

---

*Documentation Version: 2.0*
*Last Updated: 2026-02-22*
*SDK Versions: Android 1.0.44, iOS 1.1.29*
