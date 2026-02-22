import Flutter
import UIKit
import CoreBluetooth
import BCLRingSDK

@objc public class RingPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate {
    private var scanEventSink: FlutterEventSink?
    private var connectionEventSink: FlutterEventSink?
    private var healthEventSink: FlutterEventSink?
    
    private var discoveredDevices: [BCLDeviceInfoModel] = []
    private var connectedDevice: BCLDeviceInfoModel?
    
    private var methodChannel: FlutterMethodChannel?
    private var scanEventChannel: FlutterEventChannel?
    private var connectionEventChannel: FlutterEventChannel?
    private var healthEventChannel: FlutterEventChannel?
    
    // Measurement state
    private var isHeartRateMeasuring = false
    private var isSpO2Measuring = false
    private var isBloodPressureMeasuring = false
    private var rssiTimer: Timer?
    
    // Device capabilities (from composite command)
    private var deviceCapabilities: [String: Any] = [:]
    private var isHistorySyncing = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RingPlugin()
        instance.setupChannels(registrar: registrar)
        instance.setupBluetoothStateObserver()
    }
    
    private func setupChannels(registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        
        methodChannel = FlutterMethodChannel(name: "com.seeknirvana.app/ring", binaryMessenger: messenger)
        methodChannel?.setMethodCallHandler(handle(_:result:))
        
        scanEventChannel = FlutterEventChannel(name: "com.seeknirvana.app/ring/scan", binaryMessenger: messenger)
        scanEventChannel?.setStreamHandler(ScanStreamHandler(plugin: self))
        
        connectionEventChannel = FlutterEventChannel(name: "com.seeknirvana.app/ring/connection", binaryMessenger: messenger)
        connectionEventChannel?.setStreamHandler(ConnectionStreamHandler(plugin: self))
        
        healthEventChannel = FlutterEventChannel(name: "com.seeknirvana.app/ring/health", binaryMessenger: messenger)
        healthEventChannel?.setStreamHandler(HealthStreamHandler(plugin: self))
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // MARK: - Bluetooth State
        case "isBluetoothEnabled":
            isBluetoothEnabled(result: result)
        case "requestEnableBluetooth":
            requestEnableBluetooth(result: result)
        case "requestBluetoothPermission":
            requestBluetoothPermission(result: result)
            
        // MARK: - Scanning
        case "startScan":
            startScan(result: result)
        case "stopScan":
            stopScan(result: result)
            
        // MARK: - Connection
        case "connect":
            if let args = call.arguments as? [String: Any],
               let mac = args["mac"] as? String {
                let autoReconnect = args["autoReconnect"] as? Bool ?? false
                connect(macAddress: mac, autoReconnect: autoReconnect, result: result)
            } else {
                result(FlutterError(code: "INVALID_MAC", message: "MAC address is required", details: nil))
            }
        case "disconnect":
            disconnect(result: result)
        case "startReadRSSI":
            startReadRSSI(result: result)
        case "stopReadRSSI":
            stopReadRSSI(result: result)
            
        // MARK: - Device Info
        case "getBattery":
            getBattery(result: result)
        case "getChargingState":
            getChargingState(result: result)
        case "getVersion":
            getVersion(result: result)
        case "syncTime":
            syncTime(result: result)
        case "getSteps":
            getSteps(result: result)
        case "clearSteps":
            clearSteps(result: result)
            
        // MARK: - Heart Rate
        case "startHeartRate":
            startHeartRate(result: result)
        case "stopHeartRate":
            stopHeartRate(result: result)
            
        // MARK: - SpO2
        case "startSpO2":
            startSpO2(result: result)
        case "stopSpO2":
            stopSpO2(result: result)
            
        // MARK: - Blood Pressure
        case "startBloodPressure":
            startBloodPressure(result: result)
        case "stopBloodPressure":
            stopBloodPressure(result: result)
            
        // MARK: - Temperature
        case "startTemperature":
            startTemperature(result: result)
            
        // MARK: - History
        case "readHistory":
            readHistory(result: result)
        case "deleteHistory":
            deleteHistory(result: result)
            
        // MARK: - Settings
        case "setBluetoothName":
            if let args = call.arguments as? [String: Any],
               let name = args["name"] as? String {
                setBluetoothName(name: name, result: result)
            } else {
                result(FlutterError(code: "INVALID_NAME", message: "Name is required", details: nil))
            }
        case "getBluetoothName":
            getBluetoothName(result: result)
        case "setPersonalInformation":
            setPersonalInformation(args: call.arguments as? [String: Any], result: result)
        case "getPersonalInformation":
            getPersonalInformation(result: result)
        case "restoreFactorySettings":
            restoreFactorySettings(result: result)
        case "setCollectionPeriod":
            if let args = call.arguments as? [String: Any],
               let period = args["period"] as? Int {
                setCollectionPeriod(period: period, result: result)
            } else {
                result(FlutterError(code: "INVALID_PERIOD", message: "Period is required", details: nil))
            }
        case "getCollectionPeriod":
            getCollectionPeriod(result: result)
            
        // MARK: - PPG Settings
        case "setPPGFrequency":
            setPPGFrequency(args: call.arguments as? [String: Any], result: result)
        case "setPPGStatus":
            if let args = call.arguments as? [String: Any],
               let status = args["status"] as? UInt8 {
                setPPGStatus(status: status, result: result)
            } else {
                result(FlutterError(code: "INVALID_STATUS", message: "Status is required", details: nil))
            }
        case "getPPGStatus":
            getPPGStatus(result: result)
            
        // MARK: - Sensor Settings
        case "setGyroscopeStatus":
            if let args = call.arguments as? [String: Any],
               let status = args["status"] as? UInt8 {
                setGyroscopeStatus(status: status, result: result)
            } else {
                result(FlutterError(code: "INVALID_STATUS", message: "Status is required", details: nil))
            }
        case "getGyroscopeStatus":
            getGyroscopeStatus(result: result)
        case "setAccelerometerStatus":
            if let args = call.arguments as? [String: Any],
               let status = args["status"] as? UInt8 {
                setAccelerometerStatus(status: status, result: result)
            } else {
                result(FlutterError(code: "INVALID_STATUS", message: "Status is required", details: nil))
            }
        case "getAccelerometerStatus":
            getAccelerometerStatus(result: result)
        case "setTemperatureStatus":
            if let args = call.arguments as? [String: Any],
               let status = args["status"] as? UInt8 {
                setTemperatureStatus(status: status, result: result)
            } else {
                result(FlutterError(code: "INVALID_STATUS", message: "Status is required", details: nil))
            }
        case "getTemperatureStatus":
            getTemperatureStatus(result: result)
        case "setAutoCollectionStatus":
            if let args = call.arguments as? [String: Any],
               let status = args["status"] as? UInt8 {
                setAutoCollectionStatus(status: status, result: result)
            } else {
                result(FlutterError(code: "INVALID_STATUS", message: "Status is required", details: nil))
            }
        case "getAutoCollectionStatus":
            getAutoCollectionStatus(result: result)
            
        // MARK: - Advanced Features
        case "selfInspection":
            selfInspection(result: result)
        case "setHIDMode":
            setHIDMode(args: call.arguments as? [String: Any], result: result)
        case "vibrate":
            if let args = call.arguments as? [String: Any],
               let seconds = args["seconds"] as? Int {
                vibrate(seconds: seconds, result: result)
            } else {
                vibrate(seconds: 1, result: result)
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Bluetooth State
    
    private func isBluetoothEnabled(result: FlutterResult) {
        // First check authorization - if not allowed, we can't determine Bluetooth state
        if #available(iOS 13.1, *) {
            let authStatus = CBManager.authorization
            if authStatus != .allowedAlways {
                // Permission not granted - we can't check Bluetooth state
                result(false)
                return
            }
        }
        
        // Now check the actual Bluetooth power state using CoreBluetooth directly
        let state = getCBManagerState()
        result(state == .poweredOn)
    }
    
    private func requestEnableBluetooth(result: FlutterResult) {
        // iOS doesn't allow programmatically enabling Bluetooth
        // Instead, open the Settings app where user can enable it
        if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        result(nil)
    }
    
    private func requestBluetoothPermission(result: @escaping FlutterResult) {
        if #available(iOS 13.1, *) {
            let authStatus = CBManager.authorization
            if authStatus == .notDetermined {
                // Store the result callback - it will be called when auth state changes
                self.permissionResult = result
                // Initialize CBCentralManager to trigger permission prompt
                // This must be retained as a property to keep it alive
                bluetoothManager = CBCentralManager(delegate: self, queue: nil)
                // Note: The result will be returned via centralManagerDidUpdateState
            } else {
                // Permission already determined, return current status
                let status = authStatusToString(authStatus)
                result(status)
            }
        } else {
            result("granted")
        }
    }
    
    private func authStatusToString(_ status: CBManagerAuthorization) -> String {
        switch status {
        case .allowedAlways:
            return "granted"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Check if we were waiting for permission result
        if #available(iOS 13.1, *) {
            if let result = permissionResult {
                let authStatus = CBManager.authorization
                // Only return if status is no longer notDetermined (user responded)
                // or if central manager is powered on (permission granted)
                if authStatus != .notDetermined || central.state == .poweredOn {
                    let status = authStatusToString(authStatus)
                    result(status)
                    permissionResult = nil
                }
            }
        }
    }
    
    private var currentBluetoothState: BCLCentralManagerBluetoothState = .unknown
    private var bluetoothManager: CBCentralManager?
    private var permissionResult: FlutterResult?
    
    private func setupBluetoothStateObserver() {
        BCLRingManager.shared.systemBluetoothStateBlock = { [weak self] state in
            self?.currentBluetoothState = state
        }
    }
    
    private func getCBManagerState() -> CBManagerState {
        if bluetoothManager == nil {
            bluetoothManager = CBCentralManager(delegate: self, queue: nil)
        }
        return bluetoothManager?.state ?? .unknown
    }
    
    // MARK: - Scanning
    
    private func startScan(result: FlutterResult) {
        discoveredDevices.removeAll()
        
        BCLRingManager.shared.startScan { [weak self] scanResult in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch scanResult {
                case .success(let devices):
                    self.discoveredDevices = devices
                    let deviceList = devices.map { device -> [String: Any] in
                        return [
                            "name": device.peripheralName ?? device.localName ?? "Unknown",
                            "macAddress": device.uuidString,
                            "rssi": device.rssi?.intValue ?? 0,
                            "battery": NSNull(),
                            "isBonded": false
                        ]
                    }
                    self.scanEventSink?(deviceList)
                case .failure(let error):
                    print("Scan error: \(error)")
                }
            }
        }
        
        sendConnectionState("scanning")
        result(nil)
    }
    
    private func stopScan(result: FlutterResult) {
        BCLRingManager.shared.stopScan()
        result(nil)
    }
    
    // MARK: - Connection
    
    private func connect(macAddress: String, autoReconnect: Bool, result: FlutterResult) {
        guard let device = self.discoveredDevices.first(where: { $0.uuidString == macAddress }) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found in scan results", details: nil))
            return
        }
        
        sendConnectionState("connecting")
        
        BCLRingManager.shared.startConnect(
            device: device,
            isAutoReconnect: autoReconnect,
            autoReconnectTimeLimit: 300,
            autoReconnectMaxAttempts: 3
        ) { [weak self] connectResult in
            DispatchQueue.main.async {
                switch connectResult {
                case .success(let connectedDevice):
                    self?.connectedDevice = connectedDevice
                    self?.sendConnectionState("connected")
                    
                    // Auto-request device info after connection
                    self?.getBattery(result: { _ in })
                    self?.getVersion(result: { _ in })
                    self?.syncTime(result: { _ in })
                    self?.getSteps(result: { _ in })
                    
                case .failure(let error):
                    self?.sendConnectionState("disconnected")
                    self?.sendHealthData(type: "connectionError", data: ["message": error.localizedDescription])
                }
            }
        }
        
        result(nil)
    }
    
    private func disconnect(result: FlutterResult) {
        stopReadRSSI(result: { _ in })
        BCLRingManager.shared.disconnect()
        connectedDevice = nil
        deviceCapabilities.removeAll()
        isHistorySyncing = false
        sendConnectionState("disconnected")
        result(nil)
    }
    
    // MARK: - RSSI
    
    private func startReadRSSI(result: @escaping FlutterResult) {
        BCLRingManager.shared.startReadRSSI(interval: 2.0) { [weak self] rssiResult in
            DispatchQueue.main.async {
                switch rssiResult {
                case .success(let rssi):
                    self?.sendHealthData(type: "rssi", data: ["rssi": rssi.intValue])
                case .failure(let error):
                    print("RSSI read error: \(error)")
                }
            }
        }
        result(nil)
    }
    
    private func stopReadRSSI(result: @escaping FlutterResult) {
        BCLRingManager.shared.stopReadRSSI()
        result(nil)
    }
    
    // MARK: - Device Info
    
    private func getBattery(result: @escaping FlutterResult) {
        BCLRingManager.shared.readBattery { [weak self] batteryResult in
            DispatchQueue.main.async {
                switch batteryResult {
                case .success(let response):
                    self?.sendHealthData(type: "battery", data: [
                        "level": Int(response.batteryLevel),
                        "isCharging": false
                    ])
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "BATTERY_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getChargingState(result: @escaping FlutterResult) {
        BCLRingManager.shared.readChargingState { [weak self] chargingResult in
            DispatchQueue.main.async {
                switch chargingResult {
                case .success(let response):
                    self?.sendHealthData(type: "chargingState", data: [
                        "isCharging": response.chargingState == .charging
                    ])
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "CHARGING_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getVersion(result: @escaping FlutterResult) {
        BCLRingManager.shared.readFirmware { [weak self] fwResult in
            DispatchQueue.main.async {
                switch fwResult {
                case .success(let response):
                    self?.sendHealthData(type: "version", data: [
                        "versionType": 0,
                        "version": response.firmwareVersion
                    ])
                case .failure(let error):
                    print("Firmware read error: \(error)")
                }
            }
        }
        
        BCLRingManager.shared.readHardware { [weak self] hwResult in
            DispatchQueue.main.async {
                switch hwResult {
                case .success(let response):
                    self?.sendHealthData(type: "version", data: [
                        "versionType": 1,
                        "version": response.hardwareVersion
                    ])
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "VERSION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func syncTime(result: @escaping FlutterResult) {
        BCLRingManager.shared.syncTime { syncResult in
            DispatchQueue.main.async {
                switch syncResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SYNC_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getSteps(result: @escaping FlutterResult) {
        BCLRingManager.shared.readStepCount { [weak self] stepResult in
            DispatchQueue.main.async {
                switch stepResult {
                case .success(let response):
                    self?.sendHealthData(type: "steps", data: ["steps": Int(response.stepCount)])
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "STEPS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func clearSteps(result: @escaping FlutterResult) {
        BCLRingManager.shared.clearStepCount { clearResult in
            DispatchQueue.main.async {
                switch clearResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "CLEAR_STEPS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Heart Rate
    
    private func startHeartRate(result: @escaping FlutterResult) {
        isHeartRateMeasuring = true
        
        let callbacks = BCLHeartRateCallbacks(
            onProgress: { [weak self] progress in
                self?.sendHealthData(type: "heartRateProgress", data: ["progress": progress])
            },
            onStatusChanged: { status in
                print("Heart rate status: \(status)")
            },
            onMeasureValue: { [weak self] heartRate, hrv, stress, temp in
                guard let self = self else { return }
                var data: [String: Any] = [:]
                if let hr = heartRate { data["heartRate"] = hr }
                if let variability = hrv { data["hrv"] = variability }
                if let stressIndex = stress { data["stress"] = stressIndex }
                if let temperature = temp { data["temperature"] = temperature }
                self.sendHealthData(type: "heartRate", data: data)
            },
            onWaveform: { [weak self] seq, number, waveData in
                let csvData = waveData.map { "\($0.0),\($0.1),\($0.2),\($0.3)" }.joined(separator: ";")
                self?.sendHealthData(type: "heartWaveform", data: ["data": csvData])
            },
            onRRInterval: { [weak self] seq, number, rriData in
                let csvData = rriData.map { String($0) }.joined(separator: ",")
                self?.sendHealthData(type: "rri", data: ["data": csvData])
            },
            onError: { [weak self] error in
                self?.sendHealthData(type: "heartRateError", data: ["message": error.localizedDescription])
            }
        )
        
        BCLHeartRateResponse.setCallbacks(callbacks, frameId: 0)
        
        BCLRingManager.shared.startHeartRate(
            collectTime: 30,
            collectFrequency: 0x30,
            waveformConfig: 1,
            progressConfig: 1,
            intervalConfig: 0,
            callbacks: callbacks
        ) { hrResult in
            DispatchQueue.main.async {
                switch hrResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "HR_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func stopHeartRate(result: @escaping FlutterResult) {
        isHeartRateMeasuring = false
        BCLRingManager.shared.stopHeartRate { stopResult in
            DispatchQueue.main.async {
                switch stopResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "HR_STOP_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - SpO2
    
    private func startSpO2(result: @escaping FlutterResult) {
        isSpO2Measuring = true
        
        BCLRingManager.shared.startBloodOxygen(
            collectTime: 30,
            collectFrequency: 0x30,
            waveformConfig: 1,
            progressConfig: 1
        ) { [weak self] spo2Result in
            DispatchQueue.main.async {
                switch spo2Result {
                case .success(let response):
                    self?.sendHealthData(type: "spo2", data: [
                        "spo2": response.bloodOxygen ?? 0,
                        "heartRate": response.heartRate ?? 0,
                        "temperature": response.temperature ?? 0
                    ])
                    self?.sendHealthData(type: "spo2Progress", data: ["progress": 100])
                    self?.sendHealthData(type: "spo2Complete", data: [:])
                    result(nil)
                case .failure(let error):
                    self?.sendHealthData(type: "spo2Error", data: ["message": error.localizedDescription])
                    result(FlutterError(code: "SPO2_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func stopSpO2(result: @escaping FlutterResult) {
        isSpO2Measuring = false
        BCLRingManager.shared.stopBloodOxygen { stopResult in
            DispatchQueue.main.async {
                switch stopResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SPO2_STOP_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Blood Pressure
    
    private func startBloodPressure(result: @escaping FlutterResult) {
        isBloodPressureMeasuring = true
        
        sendHealthData(type: "bpProgress", data: ["progress": 0])
        
        BCLRingManager.shared.startBloodPressure(
            collectTime: 25,
            waveformConfig: 1,
            progressConfig: 1
        ) { [weak self] bpResult in
            DispatchQueue.main.async {
                switch bpResult {
                case .success(let response):
                    self?.sendHealthData(type: "bpProgress", data: ["progress": 100])
                    self?.sendHealthData(type: "bloodPressure", data: [
                        "systolic": response.systolicPressure ?? 120,
                        "diastolic": response.diastolicPressure ?? 80,
                        "confidence": 75
                    ])
                    result(nil)
                case .failure(let error):
                    self?.sendHealthData(type: "bpError", data: ["message": error.localizedDescription])
                    result(FlutterError(code: "BP_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func stopBloodPressure(result: @escaping FlutterResult) {
        isBloodPressureMeasuring = false
        BCLRingManager.shared.stopBloodPressure { stopResult in
            DispatchQueue.main.async {
                switch stopResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "BP_STOP_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Temperature
    
    private func startTemperature(result: @escaping FlutterResult) {
        BCLRingManager.shared.readTemperature { [weak self] tempResult in
            DispatchQueue.main.async {
                switch tempResult {
                case .success(let response):
                    let temp = response.temperature
                    self?.sendHealthData(type: "temperature", data: ["temperature": temp])
                    result(nil)
                case .failure(let error):
                    self?.sendHealthData(type: "temperatureError", data: ["message": error.localizedDescription])
                    result(FlutterError(code: "TEMP_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - History
    
    private func readHistory(result: @escaping FlutterResult) {
        sendHealthData(type: "historyStart", data: [:])
        
        let callbacks = BCLDataSyncCallbacks(
            onProgress: { [weak self] progress, total, index, model in
                DispatchQueue.main.async {
                    self?.sendHealthData(type: "historyData", data: [
                        "progress": progress,
                        "time": model.time,
                        "heartRate": model.heartRate,
                        "bloodOxygen": model.bloodOxygen,
                        "hrv": model.heartRateVariability,
                        "stress": model.stressIndex,
                        "temperature": model.temperature,
                        "steps": model.stepCount,
                        "sleepType": model.sleepType,
                        "exerciseIntensity": model.exerciseIntensity
                    ])
                }
            },
            onError: { [weak self] error in
                self?.sendHealthData(type: "historyError", data: ["message": error.localizedDescription])
            }
        )
        
        BCLRingManager.shared.readUnUploadData(timestamp: 0, callbacks: callbacks) { historyResult in
            DispatchQueue.main.async {
                switch historyResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "HISTORY_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func deleteHistory(result: @escaping FlutterResult) {
        BCLRingManager.shared.deleteRingAllHistoryData { deleteResult in
            DispatchQueue.main.async {
                switch deleteResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "DELETE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Settings
    
    private func setBluetoothName(name: String, result: @escaping FlutterResult) {
        BCLRingManager.shared.setBluetoothName(name: name) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_NAME_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getBluetoothName(result: @escaping FlutterResult) {
        BCLRingManager.shared.getBluetoothName { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["name": response.name ?? ""])
                case .failure(let error):
                    result(FlutterError(code: "GET_NAME_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setPersonalInformation(args: [String: Any]?, result: @escaping FlutterResult) {
        let sex = args?["sex"] as? Int ?? 0
        let age = args?["age"] as? Int ?? 30
        let height = args?["height"] as? Int ?? 170
        let weight = args?["weight"] as? Int ?? 70
        
        BCLRingManager.shared.setPersonalInformation(sex: sex, age: age, height: height, weight: weight) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_PERSONAL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getPersonalInformation(result: @escaping FlutterResult) {
        BCLRingManager.shared.getPersonalInformation { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result([
                        "sex": response.sex,
                        "age": response.age,
                        "height": response.height,
                        "weight": response.weight
                    ])
                case .failure(let error):
                    result(FlutterError(code: "GET_PERSONAL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func restoreFactorySettings(result: @escaping FlutterResult) {
        BCLRingManager.shared.restoreFactorySettings { restoreResult in
            DispatchQueue.main.async {
                switch restoreResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "RESTORE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setCollectionPeriod(period: Int, result: @escaping FlutterResult) {
        BCLRingManager.shared.setCollectPeriod(period: period) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_PERIOD_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getCollectionPeriod(result: @escaping FlutterResult) {
        BCLRingManager.shared.getCollectPeriod { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["period": response.time])
                case .failure(let error):
                    result(FlutterError(code: "GET_PERIOD_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - PPG Settings
    
    private func setPPGFrequency(args: [String: Any]?, result: @escaping FlutterResult) {
        let hrFreq = args?["hrFrequency"] as? UInt8 ?? 0x30
        let spo2Freq = args?["spo2Frequency"] as? UInt8 ?? 0x30
        let rawFreq = args?["rawdataFrequency"] as? UInt8 ?? 0x30
        
        BCLRingManager.shared.setPPGFrequency(hrFrequency: hrFreq, spo2Frequency: spo2Freq, rawdataFrequency: rawFreq) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_PPG_FREQ_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setPPGStatus(status: UInt8, result: @escaping FlutterResult) {
        BCLRingManager.shared.setPPGStatus(status: status) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_PPG_STATUS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getPPGStatus(result: @escaping FlutterResult) {
        BCLRingManager.shared.readPPGStatus { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["status": response.status])
                case .failure(let error):
                    result(FlutterError(code: "GET_PPG_STATUS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Sensor Settings
    
    private func setGyroscopeStatus(status: UInt8, result: @escaping FlutterResult) {
        BCLRingManager.shared.setGyroscopeStatus(status: status) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_GYRO_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getGyroscopeStatus(result: @escaping FlutterResult) {
        BCLRingManager.shared.readGyroscopeStatus { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["status": response.status])
                case .failure(let error):
                    result(FlutterError(code: "GET_GYRO_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setAccelerometerStatus(status: UInt8, result: @escaping FlutterResult) {
        BCLRingManager.shared.setAccelerometerStatus(status: status) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_ACCEL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getAccelerometerStatus(result: @escaping FlutterResult) {
        BCLRingManager.shared.readAccelerometerStatus { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["status": response.status])
                case .failure(let error):
                    result(FlutterError(code: "GET_ACCEL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setTemperatureStatus(status: UInt8, result: @escaping FlutterResult) {
        BCLRingManager.shared.setTemperatureStatus(status: status) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_TEMP_STATUS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getTemperatureStatus(result: @escaping FlutterResult) {
        BCLRingManager.shared.readTemperatureStatus { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["status": response.status])
                case .failure(let error):
                    result(FlutterError(code: "GET_TEMP_STATUS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setAutoCollectionStatus(status: UInt8, result: @escaping FlutterResult) {
        BCLRingManager.shared.setAutoCollectionStatus(status: status) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_AUTO_COLL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getAutoCollectionStatus(result: @escaping FlutterResult) {
        BCLRingManager.shared.readAutoCollectionStatus { getResult in
            DispatchQueue.main.async {
                switch getResult {
                case .success(let response):
                    result(["status": response.status])
                case .failure(let error):
                    result(FlutterError(code: "GET_AUTO_COLL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Advanced Features
    
    private func selfInspection(result: @escaping FlutterResult) {
        BCLRingManager.shared.oneKeySelfInspection { inspectionResult in
            DispatchQueue.main.async {
                switch inspectionResult {
                case .success(let response):
                    result([
                        "hasError": response.hasError,
                        "errorDescription": response.errorDescription
                    ])
                case .failure(let error):
                    result(FlutterError(code: "INSPECTION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func setHIDMode(args: [String: Any]?, result: @escaping FlutterResult) {
        let touchMode = args?["touchMode"] as? Int ?? 0
        let gestureMode = args?["gestureMode"] as? Int ?? 0
        let systemType = args?["systemType"] as? Int ?? 0
        
        BCLRingManager.shared.setHIDMode(
            touchMode: touchMode,
            gestureMode: gestureMode,
            systemType: systemType,
            deviceModelName: UIDevice.current.model,
            screenHeightPixel: Int(UIScreen.main.bounds.height),
            screenWidthPixel: Int(UIScreen.main.bounds.width)
        ) { setResult in
            DispatchQueue.main.async {
                switch setResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "SET_HID_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func vibrate(seconds: Int, result: @escaping FlutterResult) {
        BCLRingManager.shared.linearMotorTimerVibration(seconds: seconds, type: .strongVibration) { vibrateResult in
            DispatchQueue.main.async {
                switch vibrateResult {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "VIBRATE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func sendConnectionState(_ state: String) {
        DispatchQueue.main.async {
            self.connectionEventSink?(state)
        }
    }
    
    private func sendHealthData(type: String, data: [String: Any]) {
        var event = data
        event["type"] = type
        DispatchQueue.main.async {
            self.healthEventSink?(event)
        }
    }
    
    // MARK: - Stream Handlers
    
    class ScanStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: RingPlugin?
        
        init(plugin: RingPlugin) {
            self.plugin = plugin
        }
        
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.scanEventSink = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.scanEventSink = nil
            return nil
        }
    }
    
    class ConnectionStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: RingPlugin?
        
        init(plugin: RingPlugin) {
            self.plugin = plugin
        }
        
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.connectionEventSink = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.connectionEventSink = nil
            return nil
        }
    }
    
    class HealthStreamHandler: NSObject, FlutterStreamHandler {
        weak var plugin: RingPlugin?
        
        init(plugin: RingPlugin) {
            self.plugin = plugin
        }
        
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.healthEventSink = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.healthEventSink = nil
            return nil
        }
    }
}
