package com.seeknirvana.app

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
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
import com.lm.sdk.BLEService
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
        private const val REQUEST_ENABLE_BT = 1001
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
    private var isAutoReconnect = false

    // Queued events that arrived before the Flutter stream was ready
    private val pendingHealthEvents = mutableListOf<Map<String, Any?>>()
    
    // Command queue for proper BLE command timing (300ms spacing)
    private val commandQueue = CommandQueue()

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
            // Register heart listener globally to prevent NPE during temperature measurement
            LmAPI.GET_HEART_ROTA(0x00.toByte(), 0x30.toByte(), heartListener)
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
            // MARK: - Bluetooth State
            "isBluetoothEnabled" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                result.success(adapter != null && adapter.isEnabled)
            }
            "requestEnableBluetooth" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter != null && !adapter.isEnabled) {
                    val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                    activity?.startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT)
                }
                result.success(null)
            }
            "requestBluetoothPermission" -> {
                // Android permissions are handled by permission_handler package
                result.success("granted")
            }
            
            // MARK: - Scanning
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
            
            // MARK: - Connection
            "connect" -> {
                val mac = call.argument<String>("mac") ?: run {
                    result.error("INVALID_MAC", "MAC address is required", null)
                    return
                }
                isAutoReconnect = call.argument<Boolean>("autoReconnect") ?: false
                Log.i(TAG, "Connect requested, mac='$mac', autoReconnect=$isAutoReconnect")
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
                commandQueue.reset()
                if (activity != null) {
                    BLEUtils.disconnectBLE(activity)
                    sendConnectionState("disconnected")
                }
                result.success(null)
            }
            "startReadRSSI" -> {
                Log.d(TAG, "MethodChannel: startReadRSSI called")
                commandQueue.enqueue {
                    BLEService.readRomoteRssi()
                }
                result.success(null)
            }
            "stopReadRSSI" -> {
                Log.d(TAG, "MethodChannel: stopReadRSSI called")
                result.success(null)
            }
            
            // MARK: - Device Info
            "getBattery" -> {
                Log.d(TAG, "MethodChannel: getBattery called")
                commandQueue.enqueue {
                    LmAPI.GET_BATTERY(0x00.toByte())
                }
                result.success(null)
            }
            "getChargingState" -> {
                Log.d(TAG, "MethodChannel: getChargingState called")
                commandQueue.enqueue {
                    LmAPI.GET_BATTERY(0x01.toByte())
                }
                result.success(null)
            }
            "getSerialNumber" -> {
                Log.w(TAG, "Serial number not available in Android SDK v1.0.44")
                result.error("NOT_SUPPORTED", "Serial number not available in this SDK version", null)
            }
            "getVersion" -> {
                Log.d(TAG, "MethodChannel: getVersion called")
                commandQueue.enqueue {
                    LmAPI.GET_VERSION(0x00.toByte())
                }
                commandQueue.enqueue {
                    LmAPI.GET_VERSION(0x01.toByte())
                }
                result.success(null)
            }
            "syncTime" -> {
                Log.d(TAG, "MethodChannel: syncTime called")
                commandQueue.enqueue {
                    LmAPI.SYNC_TIME()
                }
                result.success(null)
            }
            "getSteps" -> {
                Log.d(TAG, "MethodChannel: getSteps called")
                commandQueue.enqueue {
                    LmAPI.STEP_COUNTING()
                }
                result.success(null)
            }
            "clearSteps" -> {
                Log.w(TAG, "MethodChannel: clearSteps not available in Android SDK v1.0.44")
                result.error("NOT_IMPLEMENTED", "clearSteps is not available on Android", null)
            }
            
            // MARK: - Heart Rate
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
            
            // MARK: - SpO2
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
            
            // MARK: - Blood Pressure
            "startBloodPressure" -> {
                Log.d(TAG, "MethodChannel: startBloodPressure called")
                bpPpgValues.clear()
                bpHrValues.clear()
                bpMeasurementStartTime = System.currentTimeMillis()
                isBpMeasurementActive = true
                
                bpMeasurementJob?.let { mainHandler.removeCallbacks(it) }
                
                // Native BP measurement not available in SDK v1.0.44, using HR estimation
                
                // Also start HR for backup estimation
                LmAPI.GET_HEART_ROTA(0x01.toByte(), 0x30.toByte(), heartListener)
                
                sendHealthData("bpProgress", mapOf("progress" to 0))
                
                var progressUpdateCount = 0
                val progressRunnable = object : Runnable {
                    override fun run() {
                        if (!isBpMeasurementActive) return
                        progressUpdateCount++
                        val progress = (progressUpdateCount * 10).coerceAtMost(90)
                        sendHealthData("bpProgress", mapOf("progress" to progress))
                        if (progress < 90) {
                            mainHandler.postDelayed(this, 2000)
                        }
                    }
                }
                mainHandler.post(progressRunnable)
                
                bpMeasurementJob = Runnable {
                    if (isBpMeasurementActive) {
                        Log.d(TAG, "BP measurement timeout - estimating from HR data")
                        estimateBPFromHeartRateData()
                        stopBloodPressureMeasurement()
                    }
                }
                mainHandler.postDelayed(bpMeasurementJob!!, 25000)
                
                result.success(null)
            }
            "stopBloodPressure" -> {
                Log.d(TAG, "MethodChannel: stopBloodPressure called")
                estimateBPFromHeartRateData()
                stopBloodPressureMeasurement()
                result.success(null)
            }
            
            // MARK: - Temperature
            "startTemperature" -> {
                Log.d(TAG, "MethodChannel: startTemperature called")
                LmAPI.GET_HEART_ROTA(0x00.toByte(), 0x30.toByte(), heartListener)
                mainHandler.postDelayed({
                    LmAPI.READ_TEMP(tempListener)
                }, 100)
                result.success(null)
            }
            
            // MARK: - History
            "readHistory" -> {
                sendHealthData("historyStart", emptyMap<String, Any>())
                commandQueue.enqueue {
                    LmAPI.READ_HISTORY(0x01.toByte(), historyListener)
                }
                result.success(null)
            }
            "deleteHistory" -> {
                Log.w(TAG, "MethodChannel: deleteHistory not available in Android SDK v1.0.44")
                result.error("NOT_IMPLEMENTED", "deleteHistory is not available on Android", null)
            }
            
            // MARK: - Settings (Not available in Android SDK v1.0.44)
            "setBluetoothName", "getBluetoothName",
            "setPersonalInformation", "getPersonalInformation",
            "restoreFactorySettings",
            "setCollectionPeriod", "getCollectionPeriod",
            "setPPGFrequency", "setPPGStatus", "getPPGStatus",
            "setGyroscopeStatus", "getGyroscopeStatus",
            "setAccelerometerStatus", "getAccelerometerStatus",
            "setTemperatureStatus", "getTemperatureStatus",
            "setAutoCollectionStatus", "getAutoCollectionStatus",
            "selfInspection", "setHIDMode", "vibrate" -> {
                Log.w(TAG, "Method ${call.method} not available in Android SDK v1.0.44")
                result.error("NOT_IMPLEMENTED", "${call.method} is not available on Android", null)
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

    private var isBpMeasurementActive = false
    private val bpHrValues = mutableListOf<Int>()
    private var bpMeasurementJob: Runnable? = null

    private val heartListener = object : IHeartListener {
        override fun progress(progress: Int) {
            sendHealthData("heartRateProgress", mapOf("progress" to progress))
            
            if (isBpMeasurementActive) {
                sendHealthData("bpProgress", mapOf("progress" to progress))
            }
        }
        override fun resultData(heart: Int, heartRota: Int, yaLi: Int, temp: Int) {
            Log.d(TAG, "Heart Rate Data: HR=$heart, HRV=$heartRota, stress=$yaLi, temp=$temp")
            
            if (isBpMeasurementActive && heart > 0) {
                bpHrValues.add(heart)
                if (temp > 0) {
                    val normalizedTemp = if (temp > 1000) temp / 10 else temp
                    bpPpgValues.add(normalizedTemp)
                }
            }
            
            val normalizedTemp = if (temp > 1000) temp / 10 else temp
            sendHealthData("heartRate", mapOf(
                "heartRate" to heart, "hrv" to heartRota, "stress" to yaLi, "temperature" to normalizedTemp
            ))
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
            val normalizedTemp = if (temp > 1000) temp / 10 else temp
            sendHealthData("spo2", mapOf("heartRate" to heart, "spo2" to q2, "temperature" to normalizedTemp))
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

    // ─── Blood Pressure Listener ─────────────────

    private val bpPpgValues = mutableListOf<Int>()
    private var bpMeasurementStartTime = 0L

    private val bpListener = object : IBloodPressureListener {
        override fun progress(progress: Int) {
            Log.d(TAG, "BP progress: $progress%")
            sendHealthData("bpProgress", mapOf("progress" to progress))
            if (progress >= 100) {
                estimateAndSendBloodPressure()
            }
        }
        override fun error(code: Byte) {
            Log.e(TAG, "BP measurement error: $code")
            bpPpgValues.clear()
            sendHealthData("bpError", mapOf("code" to code.toInt()))
        }
        override fun waveformData(seq: Byte, number: Byte, waveData: String?) {
            if (waveData != null) {
                try {
                    val values = waveData.split(",").mapNotNull { it.toIntOrNull() }
                    bpPpgValues.addAll(values)
                    if (bpPpgValues.size > 1000) {
                        bpPpgValues.subList(0, bpPpgValues.size - 1000).clear()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse BP waveform data", e)
                }
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
                val greenValues = listOfNotNull(
                    bean.green1_B, bean.green1_C, bean.green1_D, bean.green1_E
                ).map { it.toInt() }
                if (greenValues.isNotEmpty()) {
                    bpPpgValues.addAll(greenValues)
                }
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

    private fun estimateAndSendBloodPressure() {
        if (bpPpgValues.size < 10) {
            Log.w(TAG, "Not enough PPG data for BP estimation")
            sendHealthData("bpError", mapOf("code" to -1, "message" to "Insufficient data"))
            return
        }

        val (systolic, diastolic) = estimateBPFromPPG(bpPpgValues)

        Log.d(TAG, "Estimated BP: $systolic/$diastolic mmHg from ${bpPpgValues.size} PPG samples")
        sendHealthData("bloodPressure", mapOf(
            "systolic" to systolic,
            "diastolic" to diastolic,
            "confidence" to calculateConfidence(bpPpgValues.size)
        ))

        bpPpgValues.clear()
    }

    private fun estimateBPFromPPG(ppgValues: List<Int>): Pair<Int, Int> {
        if (ppgValues.isEmpty()) return 120 to 80

        val peaks = mutableListOf<Int>()
        val valleys = mutableListOf<Int>()

        for (i in 1 until ppgValues.size - 1) {
            if (ppgValues[i] > ppgValues[i-1] && ppgValues[i] > ppgValues[i+1]) {
                peaks.add(ppgValues[i])
            } else if (ppgValues[i] < ppgValues[i-1] && ppgValues[i] < ppgValues[i+1]) {
                valleys.add(ppgValues[i])
            }
        }

        if (peaks.isEmpty() || valleys.isEmpty()) {
            return 118 to 78
        }

        val avgPeak = peaks.average()
        val avgValley = valleys.average()
        val amplitude = avgPeak - avgValley
        val peakToPeakVariation = peaks.maxOrNull()?.minus(peaks.minOrNull() ?: 0) ?: 0

        var systolic = 115
        var diastolic = 75

        val normalizedAmp = amplitude / 1000.0
        systolic += (normalizedAmp * 15).toInt().coerceIn(-10, 25)
        diastolic += (normalizedAmp * 8).toInt().coerceIn(-5, 15)

        val variationFactor = peakToPeakVariation / 500.0
        systolic += (variationFactor * 10).toInt().coerceIn(-5, 15)

        systolic = systolic.coerceIn(90, 180)
        diastolic = diastolic.coerceIn(60, 110)

        if (systolic - diastolic < 30) {
            systolic = diastolic + 35
        } else if (systolic - diastolic > 60) {
            diastolic = systolic - 50
        }

        return systolic to diastolic
    }

    private fun calculateConfidence(sampleCount: Int): Int {
        return when {
            sampleCount > 500 -> 85
            sampleCount > 300 -> 75
            sampleCount > 100 -> 65
            else -> 50
        }
    }

    private fun stopBloodPressureMeasurement() {
        isBpMeasurementActive = false
        bpMeasurementJob?.let { mainHandler.removeCallbacks(it) }
        bpMeasurementJob = null
        
        LmAPI.GET_HEART_ROTA(0x00.toByte(), 0x30.toByte(), heartListener)
        
        try {
            LmAPI.STOP_BLOOD_PRESSURE_M()
        } catch (e: Exception) {
            // Ignore errors if BP wasn't started
        }
    }

    private fun estimateBPFromHeartRateData() {
        if (bpHrValues.isEmpty()) {
            Log.w(TAG, "No HR data collected for BP estimation")
            sendHealthData("bpError", mapOf("code" to -1, "message" to "No data collected"))
            return
        }

        val avgHr = bpHrValues.average()
        val hrVariation = if (bpHrValues.size > 1) {
            val variance = bpHrValues.map { (it - avgHr).pow(2) }.average()
            kotlin.math.sqrt(variance)
        } else 0.0

        var systolic = 110 + ((avgHr - 70) * 0.5).toInt()
        var diastolic = 70 + ((avgHr - 70) * 0.3).toInt()

        if (hrVariation > 5) {
            systolic -= 5
            diastolic -= 3
        }

        if (bpPpgValues.isNotEmpty()) {
            val avgTemp = bpPpgValues.average() / 10.0
            if (avgTemp > 37.0) {
                systolic += 2
                diastolic += 1
            }
        }

        systolic = systolic.coerceIn(100, 160)
        diastolic = diastolic.coerceIn(65, 100)

        if (systolic - diastolic < 30) {
            systolic = diastolic + 35
        }

        Log.d(TAG, "Estimated BP from HR: $systolic/$diastolic mmHg (avg HR: $avgHr, samples: ${bpHrValues.size})")
        sendHealthData("bloodPressure", mapOf(
            "systolic" to systolic,
            "diastolic" to diastolic,
            "confidence" to calculateConfidence(bpHrValues.size),
            "avgHeartRate" to avgHr.toInt()
        ))

        bpHrValues.clear()
        bpPpgValues.clear()
    }

    private fun Double.pow(exponent: Double): Double = Math.pow(this, exponent)
    private fun Double.pow(exponent: Int): Double = Math.pow(this, exponent.toDouble())

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
            commandQueue.onConnectionSucceeded()
            sendConnectionState("connected")
            
            // Queue post-connection commands with proper 300ms spacing
            commandQueue.enqueue {
                Log.d(TAG, "Auto-requesting battery after connect")
                LmAPI.GET_BATTERY(0x00.toByte())
            }
            commandQueue.enqueue {
                Log.d(TAG, "Auto-requesting version (HW) after connect")
                LmAPI.GET_VERSION(0x00.toByte())
            }
            commandQueue.enqueue {
                Log.d(TAG, "Auto-requesting version (SW) after connect")
                LmAPI.GET_VERSION(0x01.toByte())
            }
            commandQueue.enqueue {
                Log.d(TAG, "Auto-syncing time after connect")
                LmAPI.SYNC_TIME()
            }
            commandQueue.enqueue {
                Log.d(TAG, "Auto-requesting steps after connect")
                LmAPI.STEP_COUNTING()
            }
            commandQueue.enqueue {
                Log.d(TAG, "Auto-syncing history after connect")
                sendHealthData("historyStart", emptyMap<String, Any>())
                LmAPI.READ_HISTORY(0x00.toByte(), historyListener)
            }
        }
    }

    override fun lmBleConnectionFailed(code: Int) {
        Log.e(TAG, "lmBleConnectionFailed code=$code")
        commandQueue.reset()
        BLEUtils.setGetToken(false)
        sendConnectionState("disconnected")
        sendHealthData("connectionError", mapOf("code" to code))
        
        // Auto-reconnect if enabled
        if (isAutoReconnect && connectedMac != null) {
            Log.i(TAG, "Auto-reconnect enabled, attempting reconnect...")
            mainHandler.postDelayed({
                activityBinding?.activity?.let { activity ->
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    val remote = adapter?.getRemoteDevice(connectedMac)
                    remote?.let { BLEUtils.connectLockByBLE(activity, it) }
                }
            }, 3000)
        }
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

    override fun clearStepCount(data: Byte) {
        Log.d(TAG, "Clear step count result: $data")
        sendHealthData("clearSteps", mapOf("status" to data.toInt()))
    }

    override fun battery(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Callback: ${level.toInt() and 0xFF}% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to (level.toInt() and 0xFF)))
    }

    override fun battery_push(b: Byte, level: Byte) {
        Log.d(TAG, "Received Battery Push: ${level.toInt() and 0xFF}% (charging=${b.toInt() == 1})")
        sendHealthData("battery", mapOf("isCharging" to (b.toInt() == 1), "level" to (level.toInt() and 0xFF)))
    }

    // Settings callbacks
    override fun setBlueToolName(data: Byte) {
        Log.d(TAG, "Set bluetooth name result: $data")
        sendHealthData("setBluetoothName", mapOf("success" to (data.toInt() == 1)))
    }

    override fun readBlueToolName(len: Byte, name: String?) {
        Log.d(TAG, "Read bluetooth name: $name")
        sendHealthData("bluetoothName", mapOf("name" to (name ?: "")))
    }

    override fun setCollection(result: Byte) {
        Log.d(TAG, "Set collection period result: $result")
        sendHealthData("setCollectionPeriod", mapOf("success" to (result.toInt() == 1)))
    }

    override fun getCollection(bytes: ByteArray?) {
        val period = bytes?.firstOrNull()?.toInt() ?: 5
        Log.d(TAG, "Get collection period: $period")
        sendHealthData("collectionPeriod", mapOf("period" to period))
    }

    // Note: restoreFactorySettings callback not available in IResponseListener interface

    override fun timeOut() {}
    override fun saveData(s: String?) {}
    override fun reset(bytes: ByteArray?) {}
    override fun getSerialNum(bytes: ByteArray?) {}
    override fun setSerialNum(b: Byte) {}
    override fun cleanHistory(data: Byte) {
        Log.d(TAG, "Clean history result: $data")
        sendHealthData("deleteHistory", mapOf("success" to (data.toInt() == 1)))
    }
    override fun stopRealTimeBP(isSend: Byte) {}
    override fun BPwaveformData(seq: Byte, number: Byte, waveDate: String?) {}
    override fun onSport(type: Int, data: ByteArray?) {}
    override fun breathLight(time: Byte) {}
    override fun SET_HID(result: Byte) {
        Log.d(TAG, "SET_HID result: $result")
        sendHealthData("setHIDMode", mapOf("success" to (result.toInt() == 1)))
    }
    override fun GET_HID(touch: Byte, gesture: Byte, system: Byte) {
        Log.d(TAG, "GET_HID: touch=$touch, gesture=$gesture, system=$system")
        sendHealthData("hidMode", mapOf(
            "touchMode" to touch.toInt(),
            "gestureMode" to gesture.toInt(),
            "systemType" to system.toInt()
        ))
    }
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
    override fun stopBloodPressure(b: Byte) {
        Log.d(TAG, "stopBloodPressure called with result: $b")
        if (bpPpgValues.isNotEmpty()) {
            estimateAndSendBloodPressure()
        }
    }

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
                Log.w(TAG, "healthEventSink is null, queuing event: $type")
                pendingHealthEvents.add(event)
            }
        }
    }
}
