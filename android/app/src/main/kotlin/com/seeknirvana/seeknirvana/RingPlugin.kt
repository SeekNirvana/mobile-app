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
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { healthEventSink = sink }
            override fun onCancel(args: Any?) { healthEventSink = null }
        })

        // NOTE: SDK listener is registered in onAttachedToActivity after LmAPI.init()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        context = null
    }

    // ─── ActivityAware ────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        // Initialize SDK with the Application context, then register our listener
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
                    // 1. Check already connected devices (resilience against app restarts)
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

                    // 2. Start scanning for advertising devices
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
                        
                        // Stop scanning first
                        BLEUtils.stopLeScan(activity, leScanCallback)
                        sendConnectionState("connecting")
                        
                        // Check if already connected?
                        // SDK's BLEUtils.connectLockByBLE handles connection.
                        
                        // Remove any existing bond (critical for SDK connection)
                        // Only remove bond if NOT already connected? 
                        // Actually, if we are rescheduling a connect, let's just proceed.
                        // But if it IS connected to OS, removeBond might fail or be weird.
                        // Let's stick to the flow that worked: removeBond -> connect.
                        
                        BLEUtils.removeBond(remote)
                        Log.i(TAG, "Bond removed, initiating SDK connection...")
                        
                        // Small delay after removing bond before connecting
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
                // Keep the delayed call as it might be needed for some FW versions
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
            Log.d(TAG, "Heart Rate Data: HR=$heart, HRV=$heartRota")
            sendHealthData("heartRate", mapOf(
                "heartRate" to heart, "hrv" to heartRota, "stress" to yaLi, "temperature" to temp
            ))
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
            Log.d(TAG, "Heart Rate Listener Success")
            sendHealthData("heartRateComplete", emptyMap<String, Any>())
        }
    }

    // ─── SpO2 Listener ────────────────────────────────────────

    private val spo2Listener = object : IQ2Listener {
        override fun progress(progress: Int) {
            sendHealthData("spo2Progress", mapOf("progress" to progress))
        }
        override fun resultData(heart: Int, q2: Int, temp: Int) {
            Log.d(TAG, "SpO2 Data: HR=$heart, SpO2=$q2")
            sendHealthData("spo2", mapOf("heartRate" to heart, "spo2" to q2, "temperature" to temp))
        }
        override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
            if (waveData != null) sendHealthData("spo2Waveform", mapOf("data" to waveData))
        }
        override fun error(code: Int) {
            Log.e(TAG, "SpO2 Listener Error: $code")
            sendHealthData("spo2Error", mapOf("code" to code))
        }
        override fun success() {
            Log.d(TAG, "SpO2 Listener Success")
            sendHealthData("spo2Complete", emptyMap<String, Any>())
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
            sendHealthData("historyProgress", mapOf("progress" to progress))
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
            mainHandler.postDelayed({ LmAPI.GET_BATTERY(0x00.toByte()) }, 500)
            mainHandler.postDelayed({ LmAPI.GET_VERSION(0x00.toByte()) }, 1000)
            mainHandler.postDelayed({ LmAPI.SYNC_TIME() }, 1500)
        }
    }

    override fun lmBleConnectionFailed(code: Int) {
        Log.e(TAG, "lmBleConnectionFailed code=$code")
        BLEUtils.setGetToken(false)
        sendConnectionState("disconnected")
        sendHealthData("connectionError", mapOf("code" to code))
    }

    override fun VERSION(type: Byte, version: String?) {
        Log.d(TAG, "Received Version Callback: $version (type=$type)")
        if (version != null) sendHealthData("version", mapOf("type" to type.toInt(), "version" to version))
    }

    override fun syncTime(datum: Byte, time: ByteArray?) {
        sendHealthData("syncTime", mapOf("status" to datum.toInt()))
    }

    override fun stepCount(bytes: ByteArray?) {
        if (bytes != null) sendHealthData("steps", mapOf("steps" to ConvertUtils.BytesToInt(bytes)))
    }

    override fun clearStepCount(data: Byte) {}

    override fun battery(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Callback: $level% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to level.toInt()))
    }

    override fun battery_push(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Push: $level% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to level.toInt()))
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
        if (bytes != null) sendHealthData("ecg", mapOf("data" to bytes.map { it.toInt() }))
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
        mainHandler.post { healthEventSink?.success(mapOf("type" to type) + data) }
    }
}
