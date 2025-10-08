import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();
  LocationService._();

  StreamController<Position>? _positionController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastKnownPosition;
  bool _isTracking = false;

  /// Get the current position stream
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
    Duration? timeLimit,
  }) {
    _positionController ??= StreamController<Position>.broadcast();
    
    if (!_isTracking) {
      _startLocationTracking(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: timeLimit,
      );
    }
    
    return _positionController!.stream;
  }

  /// Get the current position once
  Future<Position> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final hasPermission = await _checkAndRequestPermissions();
    if (!hasPermission) {
      throw LocationPermissionException('Location permissions denied');
    }

    final isServiceEnabled = await isLocationServiceEnabled();
    if (!isServiceEnabled) {
      throw LocationServiceException('Location services are disabled');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: const Duration(seconds: 15),
      );
      _lastKnownPosition = position;
      return position;
    } catch (e) {
      if (_lastKnownPosition != null) {
        return _lastKnownPosition!;
      }
      throw LocationException('Failed to get current position: $e');
    }
  }

  /// Request location permissions
  Future<bool> requestPermissions() async {
    return await _checkAndRequestPermissions();
  }

  /// Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Get the last known position
  Position? get lastKnownPosition => _lastKnownPosition;

  /// Check if currently tracking location
  bool get isTracking => _isTracking;

  /// Stop location tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
  }

  /// Start location tracking
  Future<void> _startLocationTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
    Duration? timeLimit,
  }) async {
    final hasPermission = await _checkAndRequestPermissions();
    if (!hasPermission) {
      _positionController?.addError(
        LocationPermissionException('Location permissions denied')
      );
      return;
    }

    final isServiceEnabled = await isLocationServiceEnabled();
    if (!isServiceEnabled) {
      _positionController?.addError(
        LocationServiceException('Location services are disabled')
      );
      return;
    }

    _isTracking = true;

    final locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _lastKnownPosition = position;
        _positionController?.add(position);
      },
      onError: (error) {
        _positionController?.addError(
          LocationException('Location tracking error: $error')
        );
      },
    );
  }

  /// Check and request location permissions
  Future<bool> _checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return permission == LocationPermission.whileInUse || 
           permission == LocationPermission.always;
  }

  /// Calculate distance between two positions
  double calculateDistance(Position start, Position end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Calculate bearing between two positions
  double calculateBearing(Position start, Position end) {
    return Geolocator.bearingBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Dispose resources
  void dispose() {
    stopTracking();
    _positionController?.close();
    _positionController = null;
  }
}

// Custom exceptions for better error handling
class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  
  @override
  String toString() => 'LocationException: $message';
}

class LocationPermissionException extends LocationException {
  LocationPermissionException(String message) : super(message);
}

class LocationServiceException extends LocationException {
  LocationServiceException(String message) : super(message);
}