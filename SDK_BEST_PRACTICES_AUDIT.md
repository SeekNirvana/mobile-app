# SDK Best Practices Audit Report

## Executive Summary

After reviewing the Yongxin (勇芯) SDK documentation and your current implementation, I've identified several **critical inconsistencies** with the recommended best practices. The main issues are around **command timing**, **composite command usage**, and **connection flow**.

**Overall Rating: ⚠️ NEEDS IMPROVEMENT**

---

## Key Findings from Documentation

### 1. **Command Timing Requirements (CRITICAL)**

**Document Requirement:**
```
使用蓝牙指令，应该是顺序调用，每个指令应该间隔300ms左右，
因为硬件特性，不支持同时调用多个指令，容易解析错误

蓝牙连接成功后，建议间隔3s以后再发送指令，防止设备没有准备好，指令超时
```

**Translation:**
- Commands must be called sequentially with **300ms intervals**
- **DO NOT** call multiple commands simultaneously
- After BLE connection, wait **3 seconds** before sending commands
- Long-running commands (like history sync) should complete before sending next command

### 2. **Composite Commands (强烈推荐 - STRONGLY RECOMMENDED)**

**Document says:**
```
复合指令，是一个指令，包含之前的多个一代指令，
优点是与蓝牙通信简单，一个指令可以获取多个信息
```

The **composite command (`appEventConnectRing`)** is the **recommended approach**. It:
- Syncs time + timezone
- Gets firmware/hardware versions
- Gets battery level
- Gets charging state
- Gets step count
- Gets collection interval
- Performs self-inspection
- Returns HID support flags
- Returns feature support flags (HR curve, SpO2 curve, etc.)
- **Automatically syncs history data**

### 3. **Regular Commands (NOT RECOMMENDED)**

**Document says:**
```
常规指令流程图（仅供参考，不推荐，容易出Bug，难以管控）
```

Regular individual commands are **discouraged** because:
- Easy to cause bugs
- Difficult to manage
- Higher risk of command conflicts

---

## Current Implementation Analysis

### 🔴 CRITICAL ISSUES

#### 1. **No Command Spacing (VIOLATES 300ms rule)**

**Your Android code (`RingPlugin.kt` lines 742-766):**
```kotlin
// Auto-requesting multiple commands immediately after connection
mainHandler.postDelayed({ LmAPI.GET_BATTERY(0x00.toByte()) }, 500)
mainHandler.postDelayed({ LmAPI.GET_VERSION(0x00.toByte()) }, 1000)
mainHandler.postDelayed({ LmAPI.GET_VERSION(0x01.toByte()) }, 1200)
mainHandler.postDelayed({ LmAPI.SYNC_TIME() }, 1500)
mainHandler.postDelayed({ LmAPI.STEP_COUNTING() }, 2000)
mainHandler.postDelayed({ LmAPI.READ_HISTORY(0x00.toByte(), historyListener) }, 4000)
```

**Problem:** 
- Only 200ms between VERSION commands (needs 300ms)
- Only 300ms between VERSION and SYNC_TIME (needs 300ms minimum)
- No checking if previous command completed

**Fix:** Ensure **minimum 300ms** between ALL commands, or better yet, use **composite command**.

#### 2. **Not Using Composite Command (MISSES KEY FEATURE)**

**Your current flow uses individual commands:**
- `GET_BATTERY`
- `GET_VERSION` (twice)
- `SYNC_TIME`
- `STEP_COUNTING`
- `READ_HISTORY`

**Document recommended flow (composite command):**
```swift
BCLRingManager.shared.appEventConnectRing(
    date: Date(),
    timeZone: BCLRingTimeZone.getCurrentSystemTimeZone(),
    filterTime: filterTime,
    callbacks: callbacks
) { res in
    // Gets ALL info in ONE response:
    // - firmwareVersion
    // - hardwareVersion
    // - batteryLevel
    // - chargingState
    // - collectInterval
    // - stepCount
    // - selfInspection info
    // - HID support flags
    // - Feature support flags
    // - PLUS automatically syncs history
}
```

**Problems with your approach:**
1. Missing **feature capability detection** (isBloodPressureSupported, isVibrationSupported, etc.)
2. Missing **self-inspection** data
3. Missing **HID support** flags
4. More commands = more failure points
5. History sync is separate, not integrated

#### 3. **No 3-Second Delay After Connection (VIOLATES connection rule)**

**Document requirement:**
```
蓝牙连接成功后，建议间隔3s以后再发送指令
```

**Your code:** First command starts at 500ms after connection

**Fix:** Add 3-second delay before first command after connection

---

### 🟡 MEDIUM ISSUES

#### 4. **Android Blood Pressure Uses Estimation (SHOULD USE NATIVE)**

**Your code:** Uses HR-based estimation algorithm
**Document:** SDK provides native BP measurement

**Issue:** You're not using `IBloodPressureListener` properly or the SDK method for BP.

#### 5. **Temperature Format Inconsistency**

**Document formats:**
- Android: Returns `*10` format
- iOS: Returns `*100` format

**Your code:** Handles both but needs verification

#### 6. **Missing Feature Detection**

**Document shows these capability checks:**
```swift
response.isHIDSupported
response.isBloodPressureMeasurementSupported
response.isVibrationAlarmSupported
response.isEcgFunctionSupported
response.isFileSystemSupported
response.isGoMoreSleepAlgorithmSupported
```

**Your code:** No capability detection - tries to use features that may not exist

---

### 🟢 MINOR ISSUES

#### 7. **History Sync During Active Measurement Risk**

**Document says:**
```
获取历史记录期间，不允许主动测量，会报繁忙
```

**Your code:** No guard to prevent starting measurement during history sync

#### 8. **No Command Queue Management**

**Document requirement:** Sequential commands with spacing

**Your code:** Commands can be triggered from UI at any time (concurrent risk)

---

## Side-by-Side Comparison

| Best Practice | Document Says | Your Implementation | Status |
|--------------|---------------|---------------------|--------|
| **Command Spacing** | 300ms between commands | ~200ms, inconsistent | 🔴 FAIL |
| **Post-Connection Delay** | Wait 3s after connect | First command at 500ms | 🔴 FAIL |
| **Connection Flow** | Use composite command | Individual commands | 🔴 FAIL |
| **Feature Detection** | Check capability flags | No detection | 🔴 FAIL |
| **History During Measurement** | Block/queue requests | No protection | 🟡 WARN |
| **Auto-Reconnect** | Reference demo implementation | Custom implementation | 🟡 REVIEW |
| **Temperature Normalization** | Handle platform differences | Handled in Dart | 🟢 PASS |
| **Event Streaming** | Use callbacks/listeners | EventChannel streams | 🟢 PASS |

---

## Recommended Changes

### Phase 1: Critical Fixes (Immediate)

#### 1.1 Implement Composite Command Pattern

**For iOS (Swift):**
```swift
// REPLACE individual commands in connect() with:
private func connectWithComposite(macAddress: String, result: FlutterResult) {
    sendConnectionState("connecting")
    
    // Find device from discovered devices
    guard let device = discoveredDevices.first(where: { $0.uuidString == macAddress }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", ...))
        return
    }
    
    // First establish BLE connection
    BCLRingManager.shared.startConnect(device: device, isAutoReconnect: true) { [weak self] connectResult in
        switch connectResult {
        case .success(let connectedDevice):
            self?.connectedDevice = connectedDevice
            
            // Wait 3 seconds before sending commands (per documentation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self?.executeCompositeCommand(result: result)
            }
            
        case .failure(let error):
            self?.sendConnectionState("disconnected")
            result(FlutterError(code: "CONNECT_ERROR", ...))
        }
    }
}

private func executeCompositeCommand(result: FlutterResult) {
    let callbacks = BCLDataSyncCallbacks(
        onProgress: { [weak self] total, current, progress, model in
            self?.sendHealthData(type: "historyData", data: [...])
        },
        onStatusChanged: { [weak self] status in
            // Handle sync status
        },
        onCompleted: { [weak self] models in
            self?.sendHealthData(type: "historyComplete", data: [:])
        },
        onError: { [weak self] error in
            self?.sendHealthData(type: "historyError", data: ["message": error.localizedDescription])
        }
    )
    
    BCLRingManager.shared.appEventConnectRing(
        date: Date(),
        timeZone: BCLRingTimeZone.getCurrentSystemTimeZone(),
        filterTime: nil, // or specify if needed
        callbacks: callbacks
    ) { [weak self] res in
        switch res {
        case .success(let response):
            // Send all device info to Flutter
            self?.sendHealthData(type: "version", data: [
                "versionType": 0,
                "version": response.firmwareVersion
            ])
            self?.sendHealthData(type: "version", data: [
                "versionType": 1,
                "version": response.hardwareVersion
            ])
            self?.sendHealthData(type: "battery", data: [
                "level": response.batteryLevel,
                "isCharging": response.chargingState == .charging
            ])
            self?.sendHealthData(type: "steps", data: [
                "steps": response.stepCount
            ])
            
            // Store capability flags for later use
            self?.capabilities = [
                "bpSupported": response.isBloodPressureMeasurementSupported,
                "vibrationSupported": response.isVibrationAlarmSupported,
                "hidSupported": response.isHIDSupported,
                // ... etc
            ]
            
            self?.sendConnectionState("connected")
            result(nil)
            
        case .failure(let error):
            result(FlutterError(code: "COMPOSITE_ERROR", ...))
        }
    }
}
```

**For Android (Kotlin):**
```kotlin
// Check if LmAPI has composite command
// If not available in v1.0.44, add 300ms delays between all commands

override fun lmBleConnectionSucceeded(code: Int) {
    if (code == 7) {
        BLEUtils.setGetToken(true)
        sendConnectionState("connected")
        
        // Wait 3 seconds per documentation
        mainHandler.postDelayed({
            requestDeviceInfoSequentially()
        }, 3000)
    }
}

private fun requestDeviceInfoSequentially() {
    // Command 1: Battery
    LmAPI.GET_BATTERY(0x00.toByte())
    
    // Command 2: Version (after 300ms)
    mainHandler.postDelayed({
        LmAPI.GET_VERSION(0x00.toByte())
    }, 300)
    
    // Command 3: Hardware Version (after 300ms more)
    mainHandler.postDelayed({
        LmAPI.GET_VERSION(0x01.toByte())
    }, 600)
    
    // Command 4: Sync Time (after 300ms more)
    mainHandler.postDelayed({
        LmAPI.SYNC_TIME()
    }, 900)
    
    // Command 5: Steps (after 300ms more)
    mainHandler.postDelayed({
        LmAPI.STEP_COUNTING()
    }, 1200)
    
    // Command 6: History (after 300ms more, and only when device ready)
    mainHandler.postDelayed({
        sendHealthData("historyStart", emptyMap<String, Any>())
        LmAPI.READ_HISTORY(0x00.toByte(), historyListener)
    }, 1500)
}
```

#### 1.2 Add Command Queue Management

```kotlin
class CommandQueue {
    private val handler = Handler(Looper.getMainLooper())
    private var lastCommandTime = 0L
    private val commandInterval = 300L // ms
    
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
}
```

#### 1.3 Add Measurement Guard

```dart
// In RingPlugin.dart
static bool _isHistorySyncing = false;

static Future<void> startHeartRate() async {
  if (_isHistorySyncing) {
    throw Exception('Cannot start measurement while history is syncing');
  }
  await _channel.invokeMethod('startHeartRate');
}

// Listen to history events
static void _setupHistoryListener() {
  rawHealthData.listen((data) {
    switch (data['type']) {
      case 'historyStart':
        _isHistorySyncing = true;
        break;
      case 'historyComplete':
      case 'historyError':
        _isHistorySyncing = false;
        break;
    }
  });
}
```

---

### Phase 2: Feature Improvements

#### 2.1 Add Capability Detection

```dart
// Add to RingPlugin.dart
static Map<String, bool> deviceCapabilities = {};

static bool get supportsBloodPressure => deviceCapabilities['bpSupported'] ?? false;
static bool get supportsVibration => deviceCapabilities['vibrationSupported'] ?? false;
static bool get supportsHID => deviceCapabilities['hidSupported'] ?? false;
```

#### 2.2 Fix Android Blood Pressure

Check if newer SDK version supports native BP and use it instead of estimation:

```kotlin
// Check for native BP support
if (isNativeBPAvailable()) {
    LmAPI.START_BLOOD_PRESSURE_M(bpListener)
} else {
    // Fall back to estimation
    estimateBPFromHeartRate()
}
```

---

## Testing Checklist

After implementing fixes, verify:

- [ ] App waits 3s after connection before sending commands
- [ ] All commands are spaced by 300ms minimum
- [ ] No concurrent commands are sent
- [ ] History sync completes before allowing measurements
- [ ] Device capabilities are correctly detected
- [ ] Blood pressure accuracy improved (Android)
- [ ] Connection is stable under various conditions
- [ ] Auto-reconnect works properly

---

## Questions for Manufacturer

1. Does Android SDK v1.0.44 support composite command like iOS?
2. Is there a newer Android SDK version with composite command support?
3. Does Android SDK support native blood pressure measurement?
4. What's the recommended auto-reconnect strategy?

---

## Conclusion

Your current implementation **works but is not optimal**. The main issues are:

1. **Command timing** - Too fast, risks hardware conflicts
2. **Not using composite commands** - Missing capability detection, more failure points
3. **No 3-second post-connection delay** - May cause timeouts

**Priority fixes:**
1. Add 300ms spacing between all commands
2. Add 3-second delay after connection
3. Use composite command on iOS (if available on Android, use it too)
4. Add capability detection

These changes will improve connection stability and reduce command failures.

---

*Audit completed: 2026-02-22*
*Documentation source: https://yongxin.gitbook.io/yongxin-docs/documentation*
