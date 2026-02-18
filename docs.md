# SeekNirvana SDK Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Flow: Ring → Native → Flutter](#data-flow-ring--native--flutter)
3. [Calculation Algorithms](#calculation-algorithms)
4. [Device Info & Battery Retrieval](#device-info--battery-retrieval)
5. [Ring Naming & BSSID](#ring-naming--bssid)
6. [SDK Interface Reference](#sdk-interface-reference)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter UI (Dart)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │   Providers  │  │   Services   │  │       Screens        │   │
│  │  (Riverpod)  │  │(RingDataSvc) │  │     (Widgets)        │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘   │
│         │                 │                     │               │
│         └─────────────────┼─────────────────────┘               │
│                           │                                     │
│                    RingPlugin (Dart)                            │
│                   (MethodChannel API)                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                    MethodChannel/EventChannel
                            │
┌───────────────────────────┼────────────────────────────────────┐
│                      RingPlugin.kt (Kotlin)                    │
│                   (FlutterPlugin + IResponseListener)          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   LmAPI.*    │  │   BLEUtils   │  │   Data Listeners     │  │
│  │   Commands   │  │  (Connect)   │  │  (IHeartListener...) │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                     │              │
│         └─────────────────┼─────────────────────┘              │
│                           │                                    │
│                    ChipletRing SDK (.aar)                      │
│                     (com.lm.sdk.*)                             │
└───────────────────────────┬────────────────────────────────────┘
                            │
                           BLE
                            │
┌───────────────────────────┼─────────────────────────────────────┐
│                      Smart Ring Hardware                        │
│                 (PPG + Temp + Accelerometer)                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Ring → Native → Flutter

### 1. Connection Flow

```
User taps "Scan" → RingPlugin.startScan() → MethodChannel("startScan")
                              ↓
                    RingPlugin.kt: BLEUtils.startLeScan()
                              ↓
                    BluetoothAdapter.LeScanCallback
                              ↓
                    LogicalApi.getBleDeviceInfoWhenBleScan()
                              ↓
                    scanEventSink.success(deviceList) → Flutter Stream
```

### 2. Real-time Measurement Flow

**Example: Heart Rate Measurement**

```
User taps "Measure HR" → RingPlugin.startHeartRate() → MethodChannel
                                   ↓
                         RingPlugin.kt: LmAPI.GET_HEART_ROTA(0x01, 0x30, listener)
                                   ↓
                         Smart Ring starts PPG measurement
                                   ↓
                         IHeartListener.progress() ← Periodic updates (0-100%)
                         IHeartListener.resultData() ← Final HR/HRV/Stress
                         IHeartListener.waveformData() ← PPG waveform
                                   ↓
                         sendHealthData("heartRate", {...})
                                   ↓
                         healthEventSink.success(event) → Flutter Stream
                                   ↓
                         RingDataService._init() receives event
                                   ↓
                         ref.read(heartRateProvider.notifier).state = data
```

### 3. History/Sleep Data Sync Flow

```
On connect or manual sync → RingPlugin.readHistory() → MethodChannel
                                      ↓
                            RingPlugin.kt: LmAPI.READ_HISTORY(0x01, historyListener)
                                      ↓
                            Ring uploads stored 5-min interval records
                                      ↓
                            IHistoryListener.progress() for each record
                            IHistoryListener.success() when complete
                                      ↓
                            sendHealthData("historyData", record)
                                      ↓
                            Flutter: RingDataService accumulates sleep stages
```

### 4. Event Types Flowing from Native to Flutter

| Event Type | Source | Data Fields | Flutter Provider |
|------------|--------|-------------|------------------|
| `heartRate` | IHeartListener | `heartRate`, `hrv`, `stress`, `temperature` | `heartRateProvider` |
| `heartRateProgress` | IHeartListener | `progress` (0-100) | `heartRateMeasuringProvider` |
| `heartWaveform` | IHeartListener | `data` (CSV string) | `ppgWaveformProvider` |
| `spo2` | IQ2Listener | `heartRate`, `spo2`, `temperature` | `spo2Provider` |
| `spo2Progress` | IQ2Listener | `progress` (0-100) | `spo2MeasuringProvider` |
| `temperature` | ITempListener | `temperature` (*10) | `temperatureProvider` |
| `bloodPressure` | Estimated | `systolic`, `diastolic`, `confidence` | `systolicProvider`, `diastolicProvider` |
| `bpProgress` | Estimated | `progress` (0-100) | `bpMeasuringProvider` |
| `historyData` | IHistoryListener | `time`, `sleepType`, `heartRate`, etc. | Sleep providers |
| `battery` | IResponseListener | `level`, `isCharging` | `batteryLevelProvider` |
| `version` | IResponseListener | `versionType`, `version` | `firmwareVersionProvider` |
| `steps` | IResponseListener | `steps` | `stepsProvider` |

---

## Calculation Algorithms

### 1. HRV (Heart Rate Variability)

**Source**: SDK provides HRV value directly via `IHeartListener.resultData(heart, heartRota, yaLi, temp)`

```kotlin
// Native SDK callback
override fun resultData(heart: Int, heartRota: Int, yaLi: Int, temp: Int) {
    // heartRota = HRV value (ms)
    // yaLi = Stress index
    sendHealthData("heartRate", mapOf(
        "heartRate" to heart,
        "hrv" to heartRota,      // Direct from SDK
        "stress" to yaLi,        // Direct from SDK
        "temperature" to temp
    ))
}
```

**Flutter Usage**:
```dart
final hrData = ref.watch(heartRateProvider);
final hrv = hrData['hrv'] as int? ?? 0;  // HRV in milliseconds
```

> **Note**: The ring's PPG sensor calculates HRV internally using R-R interval analysis. We do not calculate HRV ourselves—we display the value provided by the SDK.

### 2. Sleep Stages

**Source**: History data from `IHistoryListener.progress(progress, historyDataBean)`

**Sleep Type Encoding** (from SDK):
| Type | Meaning | Duration Increment |
|------|---------|-------------------|
| 1 | Light Sleep | +5 minutes |
| 2 | Deep Sleep | +5 minutes |
| 3 | Awake | +5 minutes (not counted in total) |
| 4 | REM Sleep | +5 minutes |

**Calculation Logic** (in `RingDataService`):

```dart
case 'historyData':
  final sleepType = data['sleepType'] as int?;
  if (sleepType != null && sleepType > 0) {
    switch (sleepType) {
      case 1: // Light sleep
        ref.read(lightSleepMinutesProvider.notifier).state += 5;
        break;
      case 2: // Deep sleep
        ref.read(deepSleepMinutesProvider.notifier).state += 5;
        break;
      case 3: // Awake
        ref.read(awakeSleepMinutesProvider.notifier).state += 5;
        break;
      case 4: // REM
        ref.read(remSleepMinutesProvider.notifier).state += 5;
        break;
    }
    // Total sleep = light + deep + REM (excluding awake)
    final deep = ref.read(deepSleepMinutesProvider);
    final light = ref.read(lightSleepMinutesProvider);
    final rem = ref.read(remSleepMinutesProvider);
    ref.read(sleepDurationProvider.notifier).state = (deep + light + rem) / 60.0;
  }
```

**Important**: The ring stores sleep data in **5-minute intervals**. When syncing history, each record represents a 5-minute block, so we increment by 5 minutes per record.

### 3. Blood Pressure Estimation

**⚠️ Important**: The ring SDK **does NOT provide direct blood pressure values**. BP is **estimated** from PPG waveform characteristics and heart rate data.

#### Algorithm Overview

```
PPG Waveform → Extract Peaks/Valleys → Calculate Amplitude → 
Estimate Systolic/Diastolic → Apply Physiologic Limits
```

#### Native Implementation (`RingPlugin.kt`)

**Step 1: Collect PPG Data**
```kotlin
override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
    val values = waveData.split(",").mapNotNull { it.toIntOrNull() }
    bpPpgValues.addAll(values)
}
```

**Step 2: Analyze PPG Signal**
```kotlin
private fun estimateBPFromPPG(ppgValues: List<Int>): Pair<Int, Int> {
    // Find peaks and valleys in PPG signal
    val peaks = mutableListOf<Int>()
    val valleys = mutableListOf<Int>()

    for (i in 1 until ppgValues.size - 1) {
        if (ppgValues[i] > ppgValues[i-1] && ppgValues[i] > ppgValues[i+1]) {
            peaks.add(ppgValues[i])
        } else if (ppgValues[i] < ppgValues[i-1] && ppgValues[i] < ppgValues[i+1]) {
            valleys.add(ppgValues[i])
        }
    }
```

**Step 3: Calculate Signal Features**
```kotlin
    val avgPeak = peaks.average()
    val avgValley = valleys.average()
    val amplitude = avgPeak - avgValley  // Pulse amplitude
    val peakToPeakVariation = peaks.maxOrNull()?.minus(peaks.minOrNull() ?: 0) ?: 0
```

**Step 4: Estimate BP Values**
```kotlin
    // Base values (typical resting BP)
    var systolic = 115
    var diastolic = 75

    // Higher amplitude → stronger pulse pressure → higher systolic
    val normalizedAmp = amplitude / 1000.0
    systolic += (normalizedAmp * 15).toInt().coerceIn(-10, 25)
    diastolic += (normalizedAmp * 8).toInt().coerceIn(-5, 15)

    // More variation → arterial stiffness → higher BP
    val variationFactor = peakToPeakVariation / 500.0
    systolic += (variationFactor * 10).toInt().coerceIn(-5, 15)

    // Apply physiologic limits
    systolic = systolic.coerceIn(90, 180)
    diastolic = diastolic.coerceIn(60, 110)

    // Ensure proper pulse pressure (30-60 mmHg difference)
    if (systolic - diastolic < 30) {
        systolic = diastolic + 35
    } else if (systolic - diastolic > 60) {
        diastolic = systolic - 50
    }

    return systolic to diastolic
}
```

#### Fallback HR-Based Estimation

If PPG data collection fails, we estimate BP from heart rate:

```kotlin
private fun estimateBPFromHeartRateData() {
    val avgHr = bpHrValues.average()
    val hrVariation = calculateStandardDeviation(bpHrValues)

    // Base BP from average HR (higher HR → higher BP)
    var systolic = 110 + ((avgHr - 70) * 0.5).toInt()
    var diastolic = 70 + ((avgHr - 70) * 0.3).toInt()

    // Higher HR variation → more elastic arteries → lower BP
    if (hrVariation > 5) {
        systolic -= 5
        diastolic -= 3
    }
}
```

#### Accuracy Considerations

| Factor | Impact |
|--------|--------|
| Calibration | No user calibration performed—estimates are generic |
| Confidence | Confidence score based on sample count (50-85%) |
| Validation | Should NOT be used for medical diagnosis |
| Alternative | Consider using a calibrated BP cuff for accurate readings |

---

## Device Info & Battery Retrieval

### Battery Level

**Command**:
```kotlin
LmAPI.GET_BATTERY(0x00.toByte())
```

**Response** (IResponseListener):
```kotlin
override fun battery(b: Byte, level: Byte) {
    val isCharging = b.toInt() == 1
    val batteryLevel = level.toInt() and 0xFF  // 0-100%
    sendHealthData("battery", mapOf(
        "isCharging" to isCharging,
        "level" to batteryLevel
    ))
}

override fun battery_push(b: Byte, level: Byte) {
    // Ring automatically pushes battery updates
    // Same handling as battery()
}
```

**Auto-Retrieval**: Battery is automatically requested after successful connection:
```kotlin
override fun lmBleConnectionSucceeded(code: Int) {
    if (code == 7) {
        mainHandler.postDelayed({
            LmAPI.GET_BATTERY(0x00.toByte())
        }, 500)
    }
}
```

### Firmware Version

**Command**:
```kotlin
LmAPI.GET_VERSION(0x00.toByte())  // Hardware version
LmAPI.GET_VERSION(0x01.toByte())  // Software/Firmware version
```

**Response**:
```kotlin
override fun VERSION(type: Byte, version: String?) {
    // type: 0x00 = hardware, 0x01 = software
    sendHealthData("version", mapOf(
        "versionType" to type.toInt(),
        "version" to version
    ))
}
```

**Auto-Retrieval**: Version is automatically requested after connection:
```kotlin
mainHandler.postDelayed({ LmAPI.GET_VERSION(0x00.toByte()) }, 1000)
mainHandler.postDelayed({ LmAPI.GET_VERSION(0x01.toByte()) }, 1200)
```

### Steps

**Command**:
```kotlin
LmAPI.STEP_COUNTING()
```

**Response**:
```kotlin
override fun stepCount(bytes: ByteArray?) {
    val steps = ConvertUtils.BytesToInt(bytes)
    sendHealthData("steps", mapOf("steps" to steps))
}
```

### Time Sync

**Command**:
```kotlin
LmAPI.SYNC_TIME()
```

**Response**:
```kotlin
override fun syncTime(datum: Byte, time: ByteArray?) {
    sendHealthData("syncTime", mapOf("status" to datum.toInt()))
}
```

**Auto-Sync**: Time is automatically synced after connection:
```kotlin
mainHandler.postDelayed({ LmAPI.SYNC_TIME() }, 1500)
```

---

## Ring Naming & BSSID

### Current Behavior

The ring broadcasts a **random device name** during BLE scanning (e.g., "Ring ABC123", "Loop Ring", etc.). This is the Bluetooth device name stored in the ring's firmware.

### Can the Name Be Changed?

**SDK Methods Available**:
```kotlin
// IResponseListener interface includes:
override fun setBlueToolName(data: Byte) {}
override fun readBlueToolName(len: Byte, name: String?) {}
```

These methods are part of the SDK's `IResponseListener` interface, but:

1. **`setBlueToolName(Byte)`**: Only accepts a single byte parameter, not a string name. This suggests it may be for a different purpose (possibly enabling/disabling Bluetooth or setting a feature flag, not renaming).

2. **`readBlueToolName(len, name)`**: This is a **callback**, not a command. It receives the name but cannot set it.

**Conclusion**: The current SDK (ChipletRing1.0.44) **does not expose a method to change the ring's broadcast name**.

### Workaround: App-Level Aliases

Since the ring name cannot be changed at the firmware level, we implement **app-level aliasing**:

```dart
// Save a user-friendly name locally
Future<void> saveConnectedDevice(String macAddress, String deviceName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('saved_ring_mac_address', macAddress);
  await prefs.setString('saved_ring_device_name', deviceName);  // Custom alias
}
```

**UI Display Logic**:
```dart
// Show custom name if available, otherwise show broadcast name
Text(device.alias ?? device.broadcastName ?? 'Unknown Ring')
```

### MAC Address Stability

The ring's **MAC address is stable** (does not change). This is used as the unique identifier for:
- Reconnection
- Pairing storage
- History data association

```dart
// Store MAC for auto-reconnect
final savedMac = await getSavedMacAddress();
if (savedMac != null) {
  await RingPlugin.connect(savedMac);
}
```

---

## SDK Interface Reference

### LmAPI Commands

| Command | Parameters | Description |
|---------|------------|-------------|
| `init(Application)` | `app` | Initialize SDK |
| `addWLSCmdListener(Activity, IResponseListener)` | `activity`, `listener` | Register for device events |
| `removeWLSCmdListener(Activity)` | `activity` | Unregister |
| `GET_HEART_ROTA(start, freq, listener)` | `0x01/0x00`, `0x30`, `IHeartListener` | Start/stop HR measurement |
| `GET_HEART_Q2(start, listener)` | `0x01/0x00`, `IQ2Listener` | Start/stop SpO2 |
| `READ_TEMP(listener)` | `ITempListener` | Read temperature once |
| `GET_BATTERY(type)` | `0x00` | Get battery level |
| `GET_VERSION(type)` | `0x00` (HW), `0x01` (SW) | Get firmware version |
| `SYNC_TIME()` | - | Sync ring time with phone |
| `STEP_COUNTING()` | - | Get step count |
| `READ_HISTORY(type, listener)` | `0x01`, `IHistoryListener` | Read sleep/activity history |
| `STOP_BLOOD_PRESSURE_M()` | - | Stop BP measurement |

### BLEUtils Methods

| Method | Description |
|--------|-------------|
| `startLeScan(Activity, LeScanCallback)` | Start BLE scanning |
| `stopLeScan(Activity, LeScanCallback)` | Stop scanning |
| `connectLockByBLE(Activity, BluetoothDevice)` | Connect to ring |
| `disconnectBLE(Activity)` | Disconnect |
| `removeBond(BluetoothDevice)` | Remove pairing bond |
| `setGetToken(Boolean)` | Set authentication token state |

### Data Listeners

| Listener | Callbacks | Data Provided |
|----------|-----------|---------------|
| `IHeartListener` | `progress()`, `resultData()`, `waveformData()`, `rriData()`, `error()`, `success()` | HR, HRV, Stress, PPG waveform, R-R intervals |
| `IQ2Listener` | `progress()`, `resultData()`, `waveformData()`, `error()`, `success()` | SpO2, HR, Temperature |
| `ITempListener` | `resultData()`, `testing()`, `error()` | Temperature (*10) |
| `IHistoryListener` | `progress()`, `success()`, `error()` | Sleep stages, HR, HRV, Steps |
| `IBloodPressureListener` | `progress()`, `error()`, `waveformData()`, `bpResultData()` | PPG for BP estimation |
| `IResponseListener` | `lmBleConnecting()`, `lmBleConnectionSucceeded()`, `lmBleConnectionFailed()`, `battery()`, `VERSION()`, etc. | Connection state, device info |

---

## Troubleshooting

### Connection Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Connect Fail (null)" | Null MAC address | Ensure MAC is saved and passed correctly |
| Connection timeout | BLE interference | Move closer, ensure ring is charged |
| Stuck on "Connecting" | Previous bond issue | `BLEUtils.removeBond()` before connect |
| Connection drops | Out of range | Implement reconnection logic |

### Data Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| No HR data | Listener not registered | Ensure `GET_HEART_ROTA(0x00, 0x30, listener)` is called during init |
| No temperature | Missing HR listener | SDK requires HR listener for temp measurement |
| BP always shows 118/78 | Not enough PPG data | Ensure finger is properly positioned on sensor |
| Sleep data missing | History not synced | Call `readHistory()` after connection |

### Temperature Format Confusion

The SDK returns temperature in different formats depending on the source:

| Source | Format | Example |
|--------|--------|---------|
| `ITempListener.resultData()` | ×10 | `365` = 36.5°C |
| `IHeartListener.resultData()` temp | ×100 | `3638` = 36.38°C |
| `IQ2Listener.resultData()` temp | ×100 | `3638` = 36.38°C |

**Conversion**:
```dart
// From ITempListener (already ×10)
final celsius = temp / 10.0;

// From HR/SpO2 callbacks (×100, normalize to ×10)
final normalizedTemp = temp > 1000 ? temp / 10 : temp;
final celsius = normalizedTemp / 10.0;
```
