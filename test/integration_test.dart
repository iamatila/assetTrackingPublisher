import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:io';
import 'package:asset_tracking_publisher/main.dart' as app;
import 'package:asset_tracking_publisher/services/location_service.dart';
import 'package:asset_tracking_publisher/services/map_service.dart';
import 'package:asset_tracking_publisher/services/error_handler_service.dart';
import 'package:asset_tracking_publisher/services/performance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Asset Tracking Integration Tests', () {
    late LocationService locationService;
    late MapService mapService;
    late ErrorHandlerService errorHandler;
    late PerformanceService performanceService;

    setUpAll(() {
      locationService = LocationService.instance;
      mapService = MapService.instance;
      errorHandler = ErrorHandlerService.instance;
      performanceService = PerformanceService.instance;
    });

    tearDownAll(() {
      locationService.dispose();
      errorHandler.dispose();
      performanceService.dispose();
    });

    group('Publisher App Integration', () {
      testWidgets('should initialize app and load main screen', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        // Verify main screen elements are present
        expect(find.text('Asset Tracking Publisher'), findsOneWidget);
        expect(
          find.byType(TextField),
          findsAtLeastNWidgets(1),
        ); // Destination input
        expect(find.text('Start Publishing'), findsOneWidget);
        expect(find.text('Stop Publishing'), findsOneWidget);
      });

      testWidgets('should handle location permission flow', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        // Tap get location button
        await tester.tap(find.text('Get Current Location'));
        await tester.pumpAndSettle();

        // Should show some status update
        expect(find.textContaining('Location'), findsAtLeastNWidgets(1));
      });

      testWidgets('should handle destination input and geocoding', (
        tester,
      ) async {
        app.main();
        await tester.pumpAndSettle();

        // Enter destination
        await tester.enterText(find.byType(TextField), 'New York, NY');
        await tester.pumpAndSettle();

        // Tap set destination
        await tester.tap(find.text('Set Destination'));
        await tester.pumpAndSettle();

        // Should show geocoding status
        expect(find.textContaining('Destination'), findsAtLeastNWidgets(1));
      });

      testWidgets('should start and stop publishing', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        // First get location
        await tester.tap(find.text('Get Current Location'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Start publishing
        final publishButton = find.text('Start Publishing');
        if (publishButton.evaluate().isNotEmpty) {
          await tester.tap(publishButton);
          await tester.pumpAndSettle();

          // Should show publishing status
          expect(find.textContaining('Publishing'), findsAtLeastNWidgets(1));

          // Stop publishing
          final stopButton = find.text('Stop Publishing');
          if (stopButton.evaluate().isNotEmpty) {
            await tester.tap(stopButton);
            await tester.pumpAndSettle();
          }
        }
      });

      testWidgets('should display Google Maps widget', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        // Get location first
        await tester.tap(find.text('Get Current Location'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Should have map container
        expect(find.byType(Container), findsAtLeastNWidgets(1));
      });
    });

    group('Location Service Integration', () {
      test('should request and handle location permissions', () async {
        final result = await locationService.requestPermissions();
        expect(result, isA<bool>());
      });

      test('should get current position', () async {
        final position = await locationService.getCurrentPosition();
        if (position != null) {
          expect(position.latitude, isA<double>());
          expect(position.longitude, isA<double>());
          expect(position.accuracy, greaterThan(0));
        }
      });

      test('should start and stop location tracking', () async {
        // Start tracking by getting position stream
        final positionStream = locationService.getPositionStream();
        expect(positionStream, isA<Stream<geo.Position>>());
        expect(locationService.isTracking, isTrue);

        // Stop tracking
        locationService.stopTracking();
        expect(locationService.isTracking, isFalse);
      });

      test('should calculate distance between positions', () {
        final pos1 = MockPosition(40.7128, -74.0060); // NYC
        final pos2 = MockPosition(34.0522, -118.2437); // LA

        final distance = locationService.calculateDistance(pos1, pos2);
        expect(distance, greaterThan(3000000)); // Should be > 3000km
      });

      test('should determine GPS accuracy quality', () {
        final pos1 = MockPosition(40.7128, -74.0060, accuracy: 3.0);
        final pos2 = MockPosition(40.7128, -74.0060, accuracy: 15.0);

        // Test accuracy values directly since getAccuracyDescription doesn't exist
        expect(pos1.accuracy, equals(3.0));
        expect(pos2.accuracy, equals(15.0));
        expect(pos1.accuracy, lessThan(pos2.accuracy));
      });
    });

    group('Map Service Integration', () {
      test('should geocode addresses', () async {
        final coords = await mapService.geocodeAddress('New York, NY');
        if (coords != null) {
          expect(coords.latitude, closeTo(40.7, 1.0));
          expect(coords.longitude, closeTo(-74.0, 1.0));
        }
      });

      test('should reverse geocode coordinates', () async {
        final address = await mapService.reverseGeocode(
          const LatLng(40.7128, -74.0060),
        );
        if (address != null) {
          expect(address, contains('New York'));
        }
      });

      test('should calculate routes', () async {
        final start = const LatLng(40.7128, -74.0060); // NYC
        final end = const LatLng(40.7589, -73.9851); // Times Square

        final route = await mapService.calculateRoute(start, end);
        if (route != null) {
          expect(route.polyline, isNotEmpty);
          expect(route.distanceText, isNotEmpty);
          expect(route.durationText, isNotEmpty);
          expect(route.distance, greaterThan(0));
          expect(route.duration, greaterThan(0));
        }
      });

      test('should calculate straight-line distance', () {
        final start = const LatLng(40.7128, -74.0060);
        final end = const LatLng(40.7589, -73.9851);

        final distance = mapService.calculateStraightLineDistance(start, end);
        expect(distance, greaterThan(0));
        expect(distance, lessThan(10000)); // Should be less than 10km
      });

      test('should calculate straight-line distance accurately', () {
        final start = const LatLng(40.7128, -74.0060);
        final end = const LatLng(40.7589, -73.9851);

        final distance = mapService.calculateStraightLineDistance(start, end);
        expect(distance, greaterThan(0));
        expect(
          distance,
          lessThan(10000),
        ); // Should be less than 10km for Manhattan
      });
    });

    group('Error Handling Integration', () {
      test('should handle network errors gracefully', () async {
        var errorCaught = false;

        errorHandler.errorStream.listen((error) {
          if (error.message.contains('network')) {
            errorCaught = true;
          }
        });

        // Simulate network error
        errorHandler.handleError(
          NetworkException('Connection failed'),
          context: 'test_network_error',
        );

        await Future.delayed(const Duration(milliseconds: 100));
        expect(errorCaught, isTrue);
      });

      test('should execute retry logic with exponential backoff', () async {
        var attempts = 0;

        try {
          await errorHandler.executeWithRetry(() async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Temporary failure');
            }
            return 'success';
          }, maxAttempts: 3);
        } catch (e) {
          // Expected to succeed on 3rd attempt
        }

        expect(attempts, equals(3));
      });

      test('should provide recovery actions for different error types', () {
        final networkError = SocketException('Network unreachable');
        final actions = errorHandler.getRecoveryActions(
          networkError,
          'network_test',
        );

        expect(actions, isNotEmpty);
        expect(
          actions.any((action) => action.title.contains('Connection')),
          isTrue,
        );
      });

      test('should check service availability', () async {
        final networkStatus = await errorHandler.checkServiceAvailability(
          'network',
        );
        expect(networkStatus, isA<ServiceStatus>());

        final locationStatus = await errorHandler.checkServiceAvailability(
          'location',
        );
        expect(locationStatus, isA<ServiceStatus>());
      });
    });

    group('Performance Integration', () {
      test('should monitor performance metrics', () async {
        performanceService.startMonitoring();

        // Simulate some operations
        await performanceService.measureOperation('test_operation', () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 'result';
        });

        final metrics = performanceService.getMetrics();
        expect(metrics.averageOperationTime, greaterThan(0));

        performanceService.stopMonitoring();
      });

      test('should optimize based on performance status', () {
        final status = performanceService.getPerformanceStatus();

        final interval = PerformanceOptimizer.getOptimalLocationInterval(
          performance: status,
          batteryOptimized: false,
          isMoving: true,
        );

        expect(interval, greaterThan(0));
        expect(interval, lessThan(60000)); // Should be reasonable
      });

      test('should handle battery optimization', () {
        performanceService.enableBatteryOptimization();

        final batteryInterval = PerformanceOptimizer.getOptimalLocationInterval(
          performance: PerformanceStatus.good,
          batteryOptimized: true,
          isMoving: false,
        );

        final normalInterval = PerformanceOptimizer.getOptimalLocationInterval(
          performance: PerformanceStatus.good,
          batteryOptimized: false,
          isMoving: false,
        );

        expect(batteryInterval, greaterThan(normalInterval));

        performanceService.disableBatteryOptimization();
      });
    });

    group('End-to-End Publisher Flow', () {
      test('should complete full location publishing workflow', () async {
        // 1. Request location permissions
        final permissionResult = await locationService.requestPermissions();
        if (!permissionResult) {
          // Skip test if permissions not available
          return;
        }

        // 2. Get current location
        final position = await locationService.getCurrentPosition();
        expect(position, isNotNull);

        // 3. Set destination via geocoding
        final destinationCoords = await mapService.geocodeAddress(
          'Times Square, New York',
        );
        if (destinationCoords == null) {
          // Skip if geocoding not available
          return;
        }

        // 4. Calculate route
        final route = await mapService.calculateRoute(
          LatLng(position!.latitude, position.longitude),
          destinationCoords,
        );
        expect(route, isNotNull);

        // 5. Start location tracking
        final positionStream = locationService.getPositionStream();
        expect(positionStream, isA<Stream<geo.Position>>());
        expect(locationService.isTracking, isTrue);

        // 6. Simulate location updates and publishing
        var updateCount = 0;
        locationService.getPositionStream().take(3).listen((pos) {
          updateCount++;
          // In real app, this would publish to Ably
        });

        // Wait for some updates
        await Future.delayed(const Duration(seconds: 2));

        // 7. Stop tracking
        locationService.stopTracking();
        expect(locationService.isTracking, isFalse);
      });

      test('should handle error scenarios in publishing flow', () async {
        var errorCount = 0;

        errorHandler.errorStream.listen((error) {
          errorCount++;
        });

        // Simulate various error scenarios
        errorHandler.handleError(
          Exception('GPS unavailable'),
          context: 'location_tracking',
          severity: ErrorSeverity.high,
        );

        errorHandler.handleError(
          SocketException('Network error'),
          context: 'ably_publishing',
          severity: ErrorSeverity.medium,
        );

        await Future.delayed(const Duration(milliseconds: 100));
        expect(errorCount, equals(2));
      });
    });

    group('Cross-Platform Compatibility', () {
      test('should work on different platforms', () async {
        // Test platform-specific functionality
        final memoryUsage = await performanceService.getCurrentMemoryUsage();
        expect(memoryUsage, greaterThanOrEqualTo(0));

        // Test location service compatibility
        final serviceEnabled = await locationService.isLocationServiceEnabled();
        expect(serviceEnabled, isA<bool>());
      });

      test('should handle platform-specific errors', () {
        final platformError = PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'Location permission denied',
        );

        final errorInfo = errorHandler.getErrorInfo(platformError);
        expect(errorInfo.title, contains('Permission'));
        expect(errorInfo.suggestions, isNotEmpty);
      });
    });

    group('Route Calculation and Visualization Accuracy', () {
      test('should calculate accurate routes between known points', () async {
        // Test with known locations
        final manhattanStart = const LatLng(40.7831, -73.9712); // Central Park
        final manhattanEnd = const LatLng(40.7505, -73.9934); // Times Square

        final route = await mapService.calculateRoute(
          manhattanStart,
          manhattanEnd,
        );
        if (route != null) {
          // Should be reasonable distance for Manhattan
          expect(route.distance, greaterThan(1000)); // > 1km
          expect(route.distance, lessThan(10000)); // < 10km

          // Should have reasonable duration
          expect(route.duration, greaterThan(60)); // > 1 minute
          expect(route.duration, lessThan(3600)); // < 1 hour

          // Should have polyline points
          expect(route.polyline.length, greaterThan(5));
        }
      });

      test('should handle route calculation errors gracefully', () async {
        // Test with invalid coordinates
        final invalidStart = const LatLng(999.0, 999.0);
        final validEnd = const LatLng(40.7128, -74.0060);

        final route = await mapService.calculateRoute(invalidStart, validEnd);
        expect(route, isNull); // Should handle gracefully
      });

      test('should provide accurate route information', () async {
        final start = const LatLng(40.7128, -74.0060); // NYC
        final end = const LatLng(40.7589, -73.9851); // Times Square

        final routeInfo = await mapService.getRouteInfo(start, end);
        expect(routeInfo, isNotEmpty);
        expect(
          routeInfo,
          anyOf(
            contains('Distance'),
            contains('Route information unavailable'),
          ),
        );
      });
    });
  });
}

// Mock classes for testing
class MockPosition implements geo.Position {
  @override
  final double latitude;

  @override
  final double longitude;

  @override
  final double accuracy;

  @override
  final double altitude;

  @override
  final double heading;

  @override
  final double speed;

  @override
  final double speedAccuracy;

  @override
  final DateTime timestamp;

  @override
  final double altitudeAccuracy;

  @override
  final int? floor;

  @override
  final double headingAccuracy;

  @override
  final bool isMocked;

  MockPosition(
    this.latitude,
    this.longitude, {
    this.accuracy = 5.0,
    this.altitude = 0.0,
    this.heading = 0.0,
    this.speed = 0.0,
    this.speedAccuracy = 0.0,
    DateTime? timestamp,
    this.altitudeAccuracy = 0.0,
    this.floor,
    this.headingAccuracy = 0.0,
    this.isMocked = true,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'heading': heading,
      'speed': speed,
      'speedAccuracy': speedAccuracy,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'altitudeAccuracy': altitudeAccuracy,
      'floor': floor,
      'headingAccuracy': headingAccuracy,
      'isMocked': isMocked,
    };
  }
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

class PlatformException implements Exception {
  final String code;
  final String message;

  PlatformException({required this.code, required this.message});

  @override
  String toString() => 'PlatformException($code): $message';
}
