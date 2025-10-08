import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class ErrorHandlerService {
  static ErrorHandlerService? _instance;
  static ErrorHandlerService get instance => _instance ??= ErrorHandlerService._();
  ErrorHandlerService._();

  final StreamController<AppError> _errorController = StreamController<AppError>.broadcast();
  Stream<AppError> get errorStream => _errorController.stream;

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration initialDelay = Duration(seconds: 1);
  static const double backoffMultiplier = 2.0;

  /// Handle and report errors
  void handleError(dynamic error, {
    String? context,
    ErrorSeverity severity = ErrorSeverity.medium,
    Map<String, dynamic>? metadata,
  }) {
    final appError = AppError(
      message: _extractErrorMessage(error),
      originalError: error,
      context: context,
      severity: severity,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _errorController.add(appError);
    
    // Log error for debugging
    debugPrint('Error [${severity.name}]: ${appError.message}');
    if (context != null) {
      debugPrint('Context: $context');
    }
  }

  /// Execute function with retry logic and exponential backoff
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = maxRetries,
    Duration initialDelay = ErrorHandlerService.initialDelay,
    double backoffMultiplier = ErrorHandlerService.backoffMultiplier,
    bool Function(dynamic error)? shouldRetry,
    String? context,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await operation();
      } catch (error) {
        attempt++;
        
        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(error)) {
          handleError(error, context: context, severity: ErrorSeverity.high);
          rethrow;
        }

        // If this was the last attempt, don't retry
        if (attempt >= maxAttempts) {
          handleError(error, 
            context: context, 
            severity: ErrorSeverity.high,
            metadata: {'attempts': attempt}
          );
          rethrow;
        }

        // Log retry attempt
        handleError(error, 
          context: '$context (attempt $attempt/$maxAttempts)', 
          severity: ErrorSeverity.low,
          metadata: {'attempt': attempt, 'nextRetryIn': delay.inSeconds}
        );

        // Wait before retrying
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }

    throw Exception('Max retry attempts exceeded');
  }

  /// Check network connectivity
  Future<bool> hasNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get user-friendly error message with suggestions
  ErrorInfo getErrorInfo(dynamic error) {
    if (error is SocketException) {
      return ErrorInfo(
        title: 'Network Connection Error',
        message: 'Unable to connect to the internet. Please check your connection.',
        suggestions: [
          'Check your WiFi or mobile data connection',
          'Try moving to an area with better signal',
          'Restart your network connection',
          'Contact your network provider if the problem persists'
        ],
        canRetry: true,
      );
    }

    if (error is TimeoutException) {
      return ErrorInfo(
        title: 'Request Timeout',
        message: 'The request took too long to complete.',
        suggestions: [
          'Check your internet connection speed',
          'Try again in a few moments',
          'Move to an area with better signal'
        ],
        canRetry: true,
      );
    }

    if (error is FormatException) {
      return ErrorInfo(
        title: 'Data Format Error',
        message: 'Received invalid data from the server.',
        suggestions: [
          'Try refreshing the app',
          'Check if the app needs an update',
          'Contact support if the problem continues'
        ],
        canRetry: true,
      );
    }

    if (error.toString().contains('permission')) {
      return ErrorInfo(
        title: 'Permission Error',
        message: 'The app needs permission to access this feature.',
        suggestions: [
          'Go to Settings > Apps > Asset Tracker > Permissions',
          'Enable the required permissions',
          'Restart the app after enabling permissions'
        ],
        canRetry: false,
      );
    }

    if (error.toString().contains('API key') || error.toString().contains('unauthorized')) {
      return ErrorInfo(
        title: 'Configuration Error',
        message: 'There\'s an issue with the app configuration.',
        suggestions: [
          'Check your API key configuration',
          'Ensure all required services are enabled',
          'Contact the app administrator'
        ],
        canRetry: false,
      );
    }

    // Generic error
    return ErrorInfo(
      title: 'Unexpected Error',
      message: 'Something went wrong. Please try again.',
      suggestions: [
        'Try the action again',
        'Restart the app if the problem continues',
        'Contact support if the issue persists'
      ],
      canRetry: true,
    );
  }

  /// Extract readable error message from various error types
  String _extractErrorMessage(dynamic error) {
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    if (error is Error) {
      return error.toString();
    }
    return error.toString();
  }

  /// Create fallback location when GPS is unavailable
  Future<Map<String, double>?> getFallbackLocation() async {
    try {
      // Try to get last known location from cache/preferences
      // In a real app, you might store this in SharedPreferences
      return {
        'latitude': 40.7128, // Default to NYC
        'longitude': -74.0060,
        'accuracy': 1000.0, // Low accuracy indicator
      };
    } catch (e) {
      return null;
    }
  }

  /// Check if service is available with fallback options
  Future<ServiceStatus> checkServiceAvailability(String serviceName) async {
    try {
      switch (serviceName.toLowerCase()) {
        case 'location':
          return await _checkLocationService();
        case 'network':
          return await _checkNetworkService();
        case 'maps':
          return await _checkMapsService();
        default:
          return ServiceStatus.unknown;
      }
    } catch (e) {
      handleError(e, context: 'Service availability check: $serviceName');
      return ServiceStatus.error;
    }
  }

  Future<ServiceStatus> _checkLocationService() async {
    try {
      // This would normally check GPS/location services
      // For now, return available
      return ServiceStatus.available;
    } catch (e) {
      return ServiceStatus.unavailable;
    }
  }

  Future<ServiceStatus> _checkNetworkService() async {
    final hasConnection = await hasNetworkConnection();
    return hasConnection ? ServiceStatus.available : ServiceStatus.unavailable;
  }

  Future<ServiceStatus> _checkMapsService() async {
    try {
      // Check if Google Maps API is accessible
      final result = await InternetAddress.lookup('maps.googleapis.com');
      return result.isNotEmpty ? ServiceStatus.available : ServiceStatus.unavailable;
    } catch (e) {
      return ServiceStatus.unavailable;
    }
  }

  /// Get recovery suggestions based on error type and context
  List<RecoveryAction> getRecoveryActions(dynamic error, String? context) {
    final actions = <RecoveryAction>[];
    
    if (error is SocketException || error.toString().contains('network')) {
      actions.addAll([
        RecoveryAction(
          title: 'Check Connection',
          description: 'Verify your internet connection',
          action: () async => await hasNetworkConnection(),
        ),
        RecoveryAction(
          title: 'Switch Network',
          description: 'Try switching between WiFi and mobile data',
          action: () async => true, // User action required
        ),
      ]);
    }

    if (context?.contains('location') == true) {
      actions.addAll([
        RecoveryAction(
          title: 'Use Last Known Location',
          description: 'Continue with previously known position',
          action: () async => await getFallbackLocation() != null,
        ),
        RecoveryAction(
          title: 'Manual Location Entry',
          description: 'Enter location manually',
          action: () async => true, // User action required
        ),
      ]);
    }

    if (context?.contains('maps') == true) {
      actions.addAll([
        RecoveryAction(
          title: 'Use Offline Mode',
          description: 'Continue with basic location tracking',
          action: () async => true,
        ),
        RecoveryAction(
          title: 'Retry Connection',
          description: 'Attempt to reconnect to maps service',
          action: () async => await _checkMapsService() == ServiceStatus.available,
        ),
      ]);
    }

    // Always add generic retry action
    actions.add(
      RecoveryAction(
        title: 'Retry',
        description: 'Try the operation again',
        action: () async => true,
      ),
    );

    return actions;
  }

  /// Execute recovery action with error handling
  Future<bool> executeRecoveryAction(RecoveryAction action) async {
    try {
      return await executeWithRetry(
        action.action,
        maxAttempts: 2,
        context: 'Recovery: ${action.title}',
      );
    } catch (e) {
      handleError(e, context: 'Recovery action failed: ${action.title}');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _errorController.close();
  }
}

// Error models
class AppError {
  final String message;
  final dynamic originalError;
  final String? context;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  AppError({
    required this.message,
    required this.originalError,
    this.context,
    required this.severity,
    required this.timestamp,
    this.metadata,
  });
}

class ErrorInfo {
  final String title;
  final String message;
  final List<String> suggestions;
  final bool canRetry;

  ErrorInfo({
    required this.title,
    required this.message,
    required this.suggestions,
    required this.canRetry,
  });
}

enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

// Specific error types
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  
  @override
  String toString() => 'NetworkException: $message';
}

class ConfigurationException implements Exception {
  final String message;
  ConfigurationException(this.message);
  
  @override
  String toString() => 'ConfigurationException: $message';
}

class ServiceUnavailableException implements Exception {
  final String message;
  ServiceUnavailableException(this.message);
  
  @override
  String toString() => 'ServiceUnavailableException: $message';
}

// Service status enum
enum ServiceStatus {
  available,
  unavailable,
  degraded,
  unknown,
  error,
}

// Recovery action model
class RecoveryAction {
  final String title;
  final String description;
  final Future<bool> Function() action;

  RecoveryAction({
    required this.title,
    required this.description,
    required this.action,
  });
}