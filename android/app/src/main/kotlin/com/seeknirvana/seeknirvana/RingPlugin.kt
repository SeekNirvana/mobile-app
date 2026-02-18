package com.seeknirvana.seeknirvana

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.lm.sdk.LmAPI
import com.lm.sdk.inter.IResponseListener
import com.lm.sdk.inter.IHeartListener
import com.lm.sdk.inter.IQ2Listener
import com.lm.sdk.inter.IHistoryListener
import com.lm.sdk.inter.ITempListener
import com.lm.sdk.inter.IBloodPressureListener
import com.lm.sdk.mode.GreenAndIrBean
import com.lm.sdk.mode.SystemControlBean
import com.lm.sdk.mode.HistoryDataBean
import com.lm.sdk.utils.BLEUtils
import com.lm.sdk.LogicalApi
import com.lm.sdk.utils.ConvertUtils

class RingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, IResponseListener {

    companion object {
        private const val TAG = "RingPlugin"
        private const val METHOD_CHANNEL = "com.seeknirvana.app/ring"
        private const val SCAN_CHANNEL = "com.seeknirvana.app/ring/scan"
        private const val CONNECTION_CHANNEL = "com.seeknirvana.app/ring/connection"
        private const val HEALTH_CHANNEL = "com.seeknirvana.app/ring/health"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var connectionEventChannel: EventChannel
    private lateinit var healthEventChannel: EventChannel

    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var scanEventSink: EventChannel.EventSink? = null
    private var connectionEventSink: EventChannel.EventSink? = null
    private var healthEventSink: EventChannel.EventSink? = null

    private val scannedDevices = mutableListOf<Map<String, Any?>>()
    private var connectedMac: String? = null

    // Queued events that arrived before the Flutter stream was ready
    private val pendingHealthEvents = mutableListOf<Map<String, Any?>>()

    // ─── FlutterPlugin ────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        scanEventChannel = EventChannel(binding.binaryMessenger, SCAN_CHANNEL)
        scanEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { scanEventSink = sink }
            override fun onCancel(args: Any?) { scanEventSink = null }
        })

        connectionEventChannel = EventChannel(binding.binaryMessenger, CONNECTION_CHANNEL)
        connectionEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { connectionEventSink = sink }
            override fun onCancel(args: Any?) { connectionEventSink = null }
        })

        healthEventChannel = EventChannel(binding.binaryMessenger, HEALTH_CHANNEL)
        healthEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                healthEventSink = sink
                // Flush any pending events that arrived before Flutter subscribed
                if (sink != null && pendingHealthEvents.isNotEmpty()) {
                    Log.d(TAG, "Flushing ${pendingHealthEvents.size} pending health events")
                    for (event in pendingHealthEvents) {
                        sink.success(event)
                    }
                    pendingHealthEvents.clear()
                }
            }
            override fun onCancel(args: Any?) { healthEventSink = null }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        context = null
    }

    // ─── ActivityAware ────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        try {
            LmAPI.init(binding.activity.application)
            LmAPI.addWLSCmdListener(binding.activity, this)
            Log.i(TAG, "SDK initialized and listener registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize SDK", e)
        }
    }
    override fun onDetachedFromActivityForConfigChanges() { activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivity() {
        try {
            activityBinding?.activity?.let { LmAPI.removeWLSCmdListener(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing listener", e)
        }
        activityBinding = null
    }

    // ─── MethodChannel handler ────────────────────────────────

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        when (call.method) {
            "startScan" -> {
                scannedDevices.clear()
                if (activity != null) {
                    val btManager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
                    val connected = btManager?.getConnectedDevices(android.bluetooth.BluetoothProfile.GATT)
                    connected?.forEach { device ->
                        Log.i(TAG, "Found already connected device: ${device.name} (${device.address})")
                        if (device.name?.contains("Ring", ignoreCase = true) == true || device.name == "Loop Ring") {
                            val deviceMap = mapOf<String, Any?>(
                                "name" to (device.name ?: "Unknown"),
                                "macAddress" to device.address,
                                "rssi" to 0,
                                "battery" to null,
                                "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
                            )
                            scannedDevices.add(deviceMap)
                        }
                    }
                    if (scannedDevices.isNotEmpty()) {
                        scanEventSink?.success(scannedDevices.toList())
                    }
                    BLEUtils.startLeScan(activity, leScanCallback)
                    sendConnectionState("scanning")
                }
                result.success(null)
            }
            "stopScan" -> {
                if (activity != null) { BLEUtils.stopLeScan(activity, leScanCallback) }
                result.success(null)
            }
            "connect" -> {
                val mac = call.argument<String>("mac") ?: run {
                    result.error("INVALID_MAC", "MAC address is required", null)
                    return
                }
                Log.i(TAG, "Connect requested, mac='$mac', length=${mac.length}")
                connectedMac = mac
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter != null && activity != null) {
                    try {
                        val remote = adapter.getRemoteDevice(mac)
                        Log.i(TAG, "Connecting to $mac, bondState=${remote.bondState}")
                        BLEUtils.stopLeScan(activity, leScanCallback)
                        sendConnectionState("connecting")
                        BLEUtils.removeBond(remote)
                        Log.i(TAG, "Bond removed, initiating SDK connection...")
                        mainHandler.postDelayed({
                            Log.i(TAG, "Calling connectLockByBLE for $mac")
                            BLEUtils.connectLockByBLE(activity, remote)
                        }, 500)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting remote device for mac='$mac'", e)
                        sendConnectionState("disconnected")
                        sendHealthData("connectionError", mapOf("message" to (e.message ?: "Unknown error")))
                    }
                } else {
                    Log.e(TAG, "Cannot connect: adapter=$adapter, activity=$activity")
                }
                result.success(null)
            }
            "disconnect" -> {
                if (activity != null) {
                    BLEUtils.disconnectBLE(activity)
                    sendConnectionState("disconnected")
                }
                result.success(null)
            }
            "getBattery" -> {
                Log.d(TAG, "MethodChannel: getBattery called")
                LmAPI.GET_BATTERY(0x00.toByte())
                result.success(null)
            }
            "getVersion" -> {
                Log.d(TAG, "MethodChannel: getVersion called")
                LmAPI.GET_VERSION(0x00.toByte())
                mainHandler.postDelayed({ LmAPI.GET_VERSION(0x01.toByte()) }, 200)
                result.success(null)
            }
            "syncTime" -> {
                Log.d(TAG, "MethodChannel: syncTime called")
                LmAPI.SYNC_TIME()
                result.success(null)
            }
            "getSteps" -> {
                Log.d(TAG, "MethodChannel: getSteps called")
                LmAPI.STEP_COUNTING()
                result.success(null)
            }
            "startHeartRate" -> {
                Log.d(TAG, "MethodChannel: startHeartRate called")
                LmAPI.GET_HEART_ROTA(0x01.toByte(), 0x30.toByte(), heartListener)
                result.success(null)
            }
            "stopHeartRate" -> {
                Log.d(TAG, "MethodChannel: stopHeartRate called")
                LmAPI.GET_HEART_ROTA(0x00.toByte(), 0x30.toByte(), heartListener)
                result.success(null)
            }
            "startSpO2" -> {
                Log.d(TAG, "MethodChannel: startSpO2 called")
                LmAPI.GET_HEART_Q2(0x01.toByte(), spo2Listener)
                result.success(null)
            }
            "stopSpO2" -> {
                Log.d(TAG, "MethodChannel: stopSpO2 called")
                LmAPI.GET_HEART_Q2(0x00.toByte(), spo2Listener)
                result.success(null)
            }
            "startBloodPressure" -> {
                Log.d(TAG, "MethodChannel: startBloodPressure called")
                // GET_BLOOD_PRESSURE_M(mode, gender, age, height_cm, weight_kg, calibration, listener)
                LmAPI.GET_BLOOD_PRESSURE_M(
                    0x01.toByte(), 0x01.toByte(), 30.toByte(),
                    170.toByte(), 70.toByte(), 0x00.toByte(), bpListener
                )
                result.success(null)
            }
            "stopBloodPressure" -> {
                Log.d(TAG, "MethodChannel: stopBloodPressure called")
                LmAPI.STOP_BLOOD_PRESSURE_M()
                result.success(null)
            }
            "startTemperature" -> {
                Log.d(TAG, "MethodChannel: startTemperature called")
                LmAPI.READ_TEMP(tempListener)
                result.success(null)
            }
            "readHistory" -> {
                LmAPI.READ_HISTORY(0x01.toByte(), historyListener)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ─── BLE Scan ─────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private val leScanCallback = BluetoothAdapter.LeScanCallback { device, rssi, scanRecord ->
        if (device == null) return@LeScanCallback
        Log.i(TAG, "Saw device: ${device.name} (${device.address}) RSSI=$rssi")

        if (device.name.isNullOrEmpty()) return@LeScanCallback
        
        try {
            val bleDeviceInfo = LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, scanRecord)
            if (bleDeviceInfo == null) {
                 Log.v(TAG, "Device ${device.name} filtered out by SDK")
                return@LeScanCallback
            }

            if (scannedDevices.any { it["macAddress"] == device.address }) return@LeScanCallback

            val deviceMap = mapOf<String, Any?>(
                "name" to (device.name ?: "Unknown"),
                "macAddress" to device.address,
                "rssi" to rssi,
                "battery" to null,
                "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
            )
            scannedDevices.add(deviceMap)
            mainHandler.post { scanEventSink?.success(scannedDevices.toList()) }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing scanned device", e)
        }
    }

    // ─── Heart Rate Listener ──────────────────────────────────

    private val heartListener = object : IHeartListener {
        override fun progress(progress: Int) {
            sendHealthData("heartRateProgress", mapOf("progress" to progress))
        }
        override fun resultData(heart: Int, heartRota: Int, yaLi: Int, temp: Int) {
            Log.d(TAG, "Heart Rate Data: HR=$heart, HRV=$heartRota, stress=$yaLi, temp=$temp")
            // Temperature from HR callback is *100 (e.g., 3638 = 36.38°C)
            // Normalize to *10 format for consistency (3638 -> 364)
            val normalizedTemp = if (temp > 1000) temp / 10 else temp
            sendHealthData("heartRate", mapOf(
                "heartRate" to heart, "hrv" to heartRota, "stress" to yaLi, "temperature" to normalizedTemp
            ))
            // Forward temperature separately for the temperature card
            if (temp > 0) {
                sendHealthData("temperature", mapOf("temperature" to normalizedTemp))
            }
        }
        override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
            if (waveData != null) sendHealthData("heartWaveform", mapOf("data" to waveData))
        }
        override fun rriData(seq: Byte, number: Byte, data: String?) {
            if (data != null) sendHealthData("rri", mapOf("data" to data))
        }
        override fun error(code: Int) {
            Log.e(TAG, "Heart Rate Listener Error: $code")
            sendHealthData("heartRateError", mapOf("code" to code))
        }
        override fun success() {
            Log.d(TAG, "Heart Rate Listener Success (measurement complete)")
            sendHealthData("heartRateComplete", emptyMap<String, Any>())
        }
    }

    // ─── SpO2 Listener ────────────────────────────────────────

    private val spo2Listener = object : IQ2Listener {
        override fun progress(progress: Int) {
            sendHealthData("spo2Progress", mapOf("progress" to progress))
        }
        override fun resultData(heart: Int, q2: Int, temp: Int) {
            Log.d(TAG, "SpO2 Data: HR=$heart, SpO2=$q2, temp=$temp")
            // Temperature from SpO2 callback is *100, normalize to *10
            val normalizedTemp = if (temp > 1000) temp / 10 else temp
            sendHealthData("spo2", mapOf("heartRate" to heart, "spo2" to q2, "temperature" to normalizedTemp))
            // Forward normalized temperature
            if (temp > 0) {
                sendHealthData("temperature", mapOf("temperature" to normalizedTemp))
            }
        }
        override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
            if (waveData != null) sendHealthData("spo2Waveform", mapOf("data" to waveData))
        }
        override fun error(code: Int) {
            Log.e(TAG, "SpO2 Listener Error: $code")
            sendHealthData("spo2Error", mapOf("code" to code))
        }
        override fun success() {
            Log.d(TAG, "SpO2 Listener Success (measurement complete)")
            sendHealthData("spo2Complete", emptyMap<String, Any>())
        }
    }

    // ─── Temperature Listener ─────────────────────────────────

    private val tempListener = object : ITempListener {
        override fun resultData(temp: Int) {
            Log.d(TAG, "Temperature result: $temp (raw value, divide by 10 for °C)")
            // The SDK returns temperature * 10 (e.g., 365 = 36.5°C)
            sendHealthData("temperature", mapOf("temperature" to temp))
        }
        override fun testing(temp: Int) {
            Log.d(TAG, "Temperature testing: $temp")
            sendHealthData("temperatureTesting", mapOf("temperature" to temp))
        }
        override fun error(code: Int) {
            Log.e(TAG, "Temperature Error: $code")
            sendHealthData("temperatureError", mapOf("code" to code))
        }
    }

    // ─── Blood Pressure Listener (PPG-based) ─────────────────

    private val bpListener = object : IBloodPressureListener {
        override fun progress(progress: Int) {
            Log.d(TAG, "BP progress: $progress%")
            sendHealthData("bpProgress", mapOf("progress" to progress))
        }
        override fun error(code: Byte) {
            Log.e(TAG, "BP measurement error: $code")
            sendHealthData("bpError", mapOf("code" to code.toInt()))
        }
        override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
            if (waveData != null) {
                // PPG waveform data — forward to Flutter for display
                sendHealthData("bpWaveform", mapOf(
                    "seq" to seq.toInt(),
                    "count" to number.toInt(),
                    "data" to waveData
                ))
            }
        }
        override fun bpResultData(bean: GreenAndIrBean?) {
            if (bean != null) {
                Log.d(TAG, "BP result data: $bean")
                // Extract green LED data for PPG waveform display
                sendHealthData("bpResult", mapOf(
                    "green1_B" to bean.green1_B,
                    "green1_C" to bean.green1_C,
                    "green1_D" to bean.green1_D,
                    "green1_E" to bean.green1_E,
                    "ir1_B" to bean.ir1_B,
                    "ir1_C" to bean.ir1_C,
                    "ir1_D" to bean.ir1_D,
                    "ir1_E" to bean.ir1_E
                ))
            }
        }
    }

    // ─── History Listener ─────────────────────────────────────

    private val historyListener = object : IHistoryListener {
        override fun error(code: Int) {
            sendHealthData("historyError", mapOf("code" to code))
        }
        override fun success() {
            sendHealthData("historyComplete", emptyMap<String, Any>())
        }
        override fun progress(progress: Double, historyDataBean: HistoryDataBean?) {
            val bean = historyDataBean ?: return
            val record = mapOf(
                "progress" to progress,
                "time" to bean.time,
                "heartRate" to bean.heartRate,
                "bloodOxygen" to bean.bloodOxygen,
                "hrv" to bean.heartRateVariability,
                "stress" to bean.stressIndex,
                "temperature" to bean.temperature,
                "steps" to bean.stepCount,
                "sleepType" to bean.sleepType,
                "exerciseIntensity" to bean.exerciseIntensity
            )
            Log.d(TAG, "History record: time=${bean.time}, sleep=${bean.sleepType}, HR=${bean.heartRate}")
            sendHealthData("historyData", record)
        }
    }

    // ─── IResponseListener (connection + device) ─────────────

    override fun lmBleConnecting(code: Int) {
        Log.i(TAG, "lmBleConnecting code=$code")
        sendConnectionState("connecting")
    }

    override fun lmBleConnectionSucceeded(code: Int) {
        Log.i(TAG, "lmBleConnectionSucceeded code=$code")
        if (code == 7) {
            BLEUtils.setGetToken(true)
            sendConnectionState("connected")
            // Request device info after connection — stagger to avoid command overlap
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-requesting battery after connect")
                LmAPI.GET_BATTERY(0x00.toByte())
            }, 500)
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-requesting version after connect")
                LmAPI.GET_VERSION(0x00.toByte())
            }, 1000)
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-requesting version type 1 after connect")
                LmAPI.GET_VERSION(0x01.toByte())
            }, 1200)
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-syncing time after connect")
                LmAPI.SYNC_TIME()
            }, 1500)
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-requesting steps after connect")
                LmAPI.STEP_COUNTING()
            }, 2000)
            mainHandler.postDelayed({
                Log.d(TAG, "Auto-syncing history after connect")
                LmAPI.READ_HISTORY(0x00.toByte(), historyListener)
            }, 4000)
        }
    }

    override fun lmBleConnectionFailed(code: Int) {
        Log.e(TAG, "lmBleConnectionFailed code=$code")
        BLEUtils.setGetToken(false)
        sendConnectionState("disconnected")
        sendHealthData("connectionError", mapOf("code" to code))
    }

    override fun VERSION(type: Byte, version: String?) {
        Log.d(TAG, "Received Version Callback: '$version' (type=$type)")
        if (version != null) sendHealthData("version", mapOf("versionType" to type.toInt(), "version" to version))
    }

    override fun syncTime(datum: Byte, time: ByteArray?) {
        sendHealthData("syncTime", mapOf("status" to datum.toInt()))
    }

    override fun stepCount(bytes: ByteArray?) {
        if (bytes != null) {
            val steps = ConvertUtils.BytesToInt(bytes)
            Log.d(TAG, "Step count received: $steps")
            sendHealthData("steps", mapOf("steps" to steps))
        }
    }

    override fun clearStepCount(data: Byte) {}

    override fun battery(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Callback: ${level.toInt() and 0xFF}% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to (level.toInt() and 0xFF)))
    }

    override fun battery_push(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Push: ${level.toInt() and 0xFF}% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to (level.toInt() and 0xFF)))
    }

    override fun timeOut() {}
    override fun saveData(s: String?) {}
    override fun reset(bytes: ByteArray?) {}
    override fun setCollection(result: Byte) {}
    override fun getCollection(bytes: ByteArray?) {}
    override fun getSerialNum(bytes: ByteArray?) {}
    override fun setSerialNum(b: Byte) {}
    override fun cleanHistory(data: Byte) {}
    override fun setBlueToolName(data: Byte) {}
    override fun readBlueToolName(len: Byte, name: String?) {}
    override fun stopRealTimeBP(isSend: Byte) {}
    override fun BPwaveformData(seq: Byte, number: Byte, waveDate: String?) {}
    override fun onSport(type: Int, data: ByteArray?) {}
    override fun breathLight(time: Byte) {}
    override fun SET_HID(result: Byte) {}
    override fun GET_HID(touch: Byte, gesture: Byte, system: Byte) {}
    override fun GET_HID_CODE(bytes: ByteArray?) {}
    override fun GET_CONTROL_AUDIO_ADPCM(b: Byte) {}
    override fun SET_AUDIO_ADPCM_AUDIO(b: Byte) {}
    override fun setAudio(totalLength: Short, index: Int, audioData: ByteArray?) {}
    override fun stopHeart(data: Byte) {}
    override fun stopQ2(data: Byte) {}

    override fun GET_ECG(bytes: ByteArray?) {
        // ECG not supported by this ring hardware
    }

    override fun appBind(bean: SystemControlBean?) {}
    override fun appConnect(bean: SystemControlBean?) {}
    override fun appRefresh(bean: SystemControlBean?) {}
    override fun SystemControl(bean: SystemControlBean?) {}
    override fun CONTROL_AUDIO(bytes: ByteArray?) {}
    override fun TOUCH_AUDIO_FINISH_XUN_FEI() {}
    override fun motionCalibration(b: Byte) {}
    override fun stopBloodPressure(b: Byte) {}

    // ─── Helpers ──────────────────────────────────────────────

    private fun sendConnectionState(state: String) {
        mainHandler.post { connectionEventSink?.success(state) }
    }

    private fun sendHealthData(type: String, data: Map<String, Any?>) {
        val event = mapOf("type" to type) + data
        mainHandler.post {
            val sink = healthEventSink
            if (sink != null) {
                sink.success(event)
            } else {
                // Queue events that arrive before Flutter subscribes to the stream
                Log.w(TAG, "healthEventSink is null, queuing event: $type")
                pendingHealthEvents.add(event)
            }
        }
    }
}
