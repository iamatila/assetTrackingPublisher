import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PerformanceService {
  static PerformanceService? _instance;
  static PerformanceService get instance => _instance ??= PerformanceService._();
  PerformanceService._();

  // Performance metrics
  final Map<String, List<double>> _frameRates = {};
  final Map<String, List<int>> _memoryUsage = {};
  final Map<String, List<double>> _operationTimes = {};
  
  Timer? _monitoringTimer;
  bool _isMonitoring = false;
  
  // Thresholds
  static const double targetFrameRate = 60.0;
  static const double minAcceptableFrameRate = 30.0;
  static const int maxMemoryUsageMB = 100;
  static const double maxOperationTimeMs = 1000.0;

  /// Start performance monitoring
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _collectMetrics();
    });
    
    debugPrint('Performance monitoring started');
  }

  /// Stop performance monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    debugPrint('Performance monitoring stopped');
  }

  /// Measure operation performance
  Future<T> measureOperation<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await operation();
      stopwatch.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds.toDouble();
      _recordOperationTime(operationName, durationMs);
      
      if (durationMs > maxOperationTimeMs) {
        debugPrint('⚠️ Slow operation detected: $operationName took ${durationMs}ms');
      }
      
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Operation failed: $operationName (${stopwatch.elapsedMilliseconds}ms)');
      rethrow;
    }
  }

  /// Measure synchronous operation performance
  T measureSync<T>(
    String operationName,
    T Function() operation,
  ) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = operation();
      stopwatch.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds.toDouble();
      _recordOperationTime(operationName, durationMs);
      
      if (durationMs > maxOperationTimeMs) {
        debugPrint('⚠️ Slow sync operation: $operationName took ${durationMs}ms');
      }
      
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Sync operation failed: $operationName (${stopwatch.elapsedMilliseconds}ms)');
      rethrow;
    }
  }

  /// Get current frame rate estimate
  double getCurrentFrameRate() {
    // This is a simplified estimation
    // In a real app, you might use more sophisticated frame rate detection
    return targetFrameRate; // Placeholder
  }

  /// Get current memory usage in MB
  Future<int> getCurrentMemoryUsage() async {
    try {
      // Get memory info from platform
      if (Platform.isAndroid) {
        return await _getAndroidMemoryUsage();
      } else if (Platform.isIOS) {
        return await _getIOSMemoryUsage();
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting memory usage: $e');
      return 0;
    }
  }

  /// Check if performance is acceptable
  PerformanceStatus getPerformanceStatus() {
    final frameRate = getCurrentFrameRate();
    final recentOperations = _getRecentOperationTimes();
    
    // Check frame rate
    if (frameRate < minAcceptableFrameRate) {
      return PerformanceStatus.poor;
    }
    
    // Check operation times
    final slowOperations = recentOperations.where((time) => time > maxOperationTimeMs).length;
    if (slowOperations > recentOperations.length * 0.3) { // More than 30% slow
      return PerformanceStatus.degraded;
    }
    
    if (frameRate >= targetFrameRate && slowOperations == 0) {
      return PerformanceStatus.excellent;
    }
    
    return PerformanceStatus.good;
  }

  /// Get performance recommendations
  List<String> getPerformanceRecommendations() {
    final recommendations = <String>[];
    final status = getPerformanceStatus();
    
    switch (status) {
      case PerformanceStatus.poor:
        recommendations.addAll([
          'Reduce map update frequency',
          'Disable non-essential animations',
          'Clear location trail more frequently',
          'Consider using lower map quality',
        ]);
        break;
      case PerformanceStatus.degraded:
        recommendations.addAll([
          'Optimize location update intervals',
          'Reduce marker complexity',
          'Consider battery optimization mode',
        ]);
        break;
      case PerformanceStatus.good:
        recommendations.add('Performance is acceptable');
        break;
      case PerformanceStatus.excellent:
        recommendations.add('Performance is excellent');
        break;
    }
    
    return recommendations;
  }

  /// Get performance metrics summary
  PerformanceMetrics getMetrics() {
    final frameRates = _frameRates.values.expand((list) => list).toList();
    final memoryUsages = _memoryUsage.values.expand((list) => list).toList();
    final operationTimes = _operationTimes.values.expand((list) => list).toList();
    
    return PerformanceMetrics(
      averageFrameRate: frameRates.isNotEmpty 
        ? frameRates.reduce((a, b) => a + b) / frameRates.length 
        : 0.0,
      averageMemoryUsage: memoryUsages.isNotEmpty 
        ? (memoryUsages.reduce((a, b) => a + b) / memoryUsages.length).round()
        : 0,
      averageOperationTime: operationTimes.isNotEmpty 
        ? operationTimes.reduce((a, b) => a + b) / operationTimes.length 
        : 0.0,
      maxOperationTime: operationTimes.isNotEmpty 
        ? operationTimes.reduce((a, b) => a > b ? a : b) 
        : 0.0,
      status: getPerformanceStatus(),
    );
  }

  /// Optimize for battery usage
  void enableBatteryOptimization() {
    debugPrint('🔋 Battery optimization enabled');
    // Reduce update frequencies, disable animations, etc.
  }

  /// Disable battery optimization for better performance
  void disableBatteryOptimization() {
    debugPrint('⚡ Battery optimization disabled');
    // Restore normal update frequencies and animations
  }

  /// Clear old performance data
  void clearMetrics() {
    _frameRates.clear();
    _memoryUsage.clear();
    _operationTimes.clear();
    debugPrint('Performance metrics cleared');
  }

  // Private methods
  void _collectMetrics() {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Collect frame rate
    final frameRate = getCurrentFrameRate();
    _frameRates.putIfAbsent('general', () => []).add(frameRate);
    
    // Collect memory usage
    getCurrentMemoryUsage().then((memory) {
      _memoryUsage.putIfAbsent('general', () => []).add(memory);
    });
    
    // Keep only recent data (last 60 seconds)
    _cleanupOldMetrics();
  }

  void _recordOperationTime(String operationName, double timeMs) {
    _operationTimes.putIfAbsent(operationName, () => []).add(timeMs);
    
    // Keep only recent operations (last 100 per operation)
    final operations = _operationTimes[operationName]!;
    if (operations.length > 100) {
      operations.removeRange(0, operations.length - 100);
    }
  }

  void _cleanupOldMetrics() {
    // Keep only last 60 data points for frame rates and memory
    for (final key in _frameRates.keys) {
      final list = _frameRates[key]!;
      if (list.length > 60) {
        list.removeRange(0, list.length - 60);
      }
    }
    
    for (final key in _memoryUsage.keys) {
      final list = _memoryUsage[key]!;
      if (list.length > 60) {
        list.removeRange(0, list.length - 60);
      }
    }
  }

  List<double> _getRecentOperationTimes() {
    final recentTimes = <double>[];
    for (final operations in _operationTimes.values) {
      if (operations.isNotEmpty) {
        // Get last 10 operations
        final recent = operations.length > 10 
          ? operations.sublist(operations.length - 10)
          : operations;
        recentTimes.addAll(recent);
      }
    }
    return recentTimes;
  }

  Future<int> _getAndroidMemoryUsage() async {
    try {
      // This would use platform channels to get actual memory usage
      // For now, return a placeholder
      return 50; // MB
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getIOSMemoryUsage() async {
    try {
      // This would use platform channels to get actual memory usage
      // For now, return a placeholder
      return 45; // MB
    } catch (e) {
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    clearMetrics();
  }
}

// Performance models
enum PerformanceStatus {
  excellent,
  good,
  degraded,
  poor,
}

class PerformanceMetrics {
  final double averageFrameRate;
  final int averageMemoryUsage; // MB
  final double averageOperationTime; // ms
  final double maxOperationTime; // ms
  final PerformanceStatus status;

  PerformanceMetrics({
    required this.averageFrameRate,
    required this.averageMemoryUsage,
    required this.averageOperationTime,
    required this.maxOperationTime,
    required this.status,
  });

  @override
  String toString() {
    return 'Performance: ${status.name} | '
           'FPS: ${averageFrameRate.toStringAsFixed(1)} | '
           'Memory: ${averageMemoryUsage}MB | '
           'Avg Op: ${averageOperationTime.toStringAsFixed(1)}ms';
  }
}

// Performance optimization utilities
class PerformanceOptimizer {
  static const int defaultLocationUpdateInterval = 5000; // 5 seconds
  static const int batteryOptimizedInterval = 15000; // 15 seconds
  static const int highPerformanceInterval = 2000; // 2 seconds

  /// Get optimal location update interval based on performance and battery
  static int getOptimalLocationInterval({
    required PerformanceStatus performance,
    required bool batteryOptimized,
    required bool isMoving,
  }) {
    if (batteryOptimized) {
      return isMoving ? batteryOptimizedInterval : batteryOptimizedInterval * 2;
    }

    switch (performance) {
      case PerformanceStatus.excellent:
        return isMoving ? highPerformanceInterval : defaultLocationUpdateInterval;
      case PerformanceStatus.good:
        return defaultLocationUpdateInterval;
      case PerformanceStatus.degraded:
        return isMoving ? defaultLocationUpdateInterval : defaultLocationUpdateInterval * 2;
      case PerformanceStatus.poor:
        return batteryOptimizedInterval;
    }
  }

  /// Get optimal map update frequency
  static int getOptimalMapUpdateFrequency(PerformanceStatus performance) {
    switch (performance) {
      case PerformanceStatus.excellent:
        return 60; // 60 FPS
      case PerformanceStatus.good:
        return 30; // 30 FPS
      case PerformanceStatus.degraded:
        return 15; // 15 FPS
      case PerformanceStatus.poor:
        return 10; // 10 FPS
    }
  }

  /// Should use animations based on performance
  static bool shouldUseAnimations(PerformanceStatus performance) {
    return performance == PerformanceStatus.excellent || 
           performance == PerformanceStatus.good;
  }

  /// Get optimal trail length based on performance
  static int getOptimalTrailLength(PerformanceStatus performance) {
    switch (performance) {
      case PerformanceStatus.excellent:
        return 100;
      case PerformanceStatus.good:
        return 50;
      case PerformanceStatus.degraded:
        return 25;
      case PerformanceStatus.poor:
        return 10;
    }
  }
}