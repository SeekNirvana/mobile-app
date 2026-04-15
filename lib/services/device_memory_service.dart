import 'dart:io';

/// Service to check device memory availability for model loading
class DeviceMemoryService {
  /// Minimum free memory required to safely load a model (in MB)
  /// 
  /// This is a conservative estimate that accounts for:
  /// - Local model files plus runtime overhead for on-device inference
  /// - Working memory during inference
  /// - System overhead and other apps
  static const int minimumFreeMemoryMB = 3500; // 3.5GB minimum

  /// Check if device has enough memory to load models
  /// 
  /// Returns a tuple: (hasEnoughMemory, freeMemoryMB, message)
  static Future<(bool, int, String)> checkMemoryAvailability() async {
    try {
      if (!Platform.isAndroid) {
        // On non-Android platforms, assume sufficient memory
        return (true, 8192, 'Non-Android platform, skipping memory check.');
      }

      final memInfo = await _readMemInfo();
      final memAvailableMB = memInfo['MemAvailable'] ?? 0;
      final memFreeMB = memInfo['MemFree'] ?? 0;
      final memTotalMB = memInfo['MemTotal'] ?? 0;

      // Use MemAvailable as it's more accurate (includes reclaimable cache)
      final usableMemoryMB = memAvailableMB;

      if (usableMemoryMB < minimumFreeMemoryMB) {
        final message = 'Insufficient memory: ${usableMemoryMB}MB available, '
            '${minimumFreeMemoryMB}MB required.\n'
            'Total: ${memTotalMB}MB, Free: ${memFreeMB}MB\n'
            'Please close other apps and try again.';
        return (false, usableMemoryMB, message);
      }

      return (true, usableMemoryMB, 
          '${usableMemoryMB}MB available (${minimumFreeMemoryMB}MB required)');
    } catch (e) {
      // If we can't check memory, allow the operation but log the error
      return (true, 0, 'Could not check memory: $e');
    }
  }

  /// Read /proc/meminfo and parse memory values in MB
  static Future<Map<String, int>> _readMemInfo() async {
    final memInfo = <String, int>{};
    
    try {
      final file = File('/proc/meminfo');
      if (!await file.exists()) {
        return memInfo;
      }

      final lines = await file.readAsLines();
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final valueStr = parts[1].trim();
          // Parse value in kB and convert to MB
          final valueKb = int.tryParse(valueStr.split(' ').first) ?? 0;
          memInfo[key] = valueKb ~/ 1024; // Convert kB to MB
        }
      }
    } catch (e) {
      // Ignore errors reading meminfo
    }

    return memInfo;
  }

  /// Get a human-readable memory status for debugging
  static Future<String> getMemoryStatus() async {
    final (hasEnough, freeMB, message) = await checkMemoryAvailability();
    final status = hasEnough ? '✓ Sufficient' : '✗ Insufficient';
    return '$status: $message';
  }
}
