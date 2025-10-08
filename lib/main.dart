import 'package:flutter/material.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/location_service.dart';
import 'services/map_service.dart';
import 'widgets/error_display_widget.dart';
import 'dart:math' as math;
import 'services/error_handler_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asset Tracking Publisher',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AssetTrackingPublisher(),
    );
  }
}

class AssetTrackingPublisher extends StatefulWidget {
  const AssetTrackingPublisher({super.key});

  @override
  State<AssetTrackingPublisher> createState() => _AssetTrackingPublisherState();
}

class _AssetTrackingPublisherState extends State<AssetTrackingPublisher> {
  static const String channelName = 'asset-tracking:locations';

  ably.Realtime? _ablyRealtime;
  ably.RealtimeChannel? _channel;
  bool _isPublishing = false;
  Position? _currentPosition;
  String _status = 'Not started';
  String _destination = '';
  LatLng? _destinationCoords;

  // Google Maps related
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final LocationService _locationService = LocationService.instance;
  final MapService _mapService = MapService.instance;
  final ErrorHandlerService _errorHandler = ErrorHandlerService.instance;

  @override
  void initState() {
    super.initState();
    _loadEnvVars();
  }

  Future<void> _loadEnvVars() async {
    try {
      await dotenv.load(fileName: ".env");
      await _validateApiKeys();
      _initializeAbly();
    } catch (e) {
      setState(() {
        _status = 'Error loading configuration: $e';
      });
    }
  }

  Future<void> _validateApiKeys() async {
    setState(() {
      _status = 'Validating API keys...';
    });

    // Basic validation without HTTP requests for now
    final ablyKey = dotenv.env['ABLY_KEY'];
    final googleMapsKey = dotenv.env['GOOGLE_MAPS_API_KEY'];

    if (ablyKey == null ||
        ablyKey.isEmpty ||
        ablyKey == 'your_ably_api_key_here') {
      setState(() {
        _status = 'Ably API Key Error: Missing or not configured';
      });
      return;
    }

    if (!ablyKey.contains('.') || !ablyKey.contains(':')) {
      setState(() {
        _status = 'Ably API Key Error: Invalid format';
      });
      return;
    }

    if (googleMapsKey == null ||
        googleMapsKey.isEmpty ||
        googleMapsKey == 'your_google_maps_api_key_here') {
      setState(() {
        _status = 'Google Maps API Key Error: Missing or not configured';
      });
      return;
    }

    setState(() {
      _status = 'API keys validated successfully';
    });
  }

  Future<void> _initializeAbly() async {
    try {
      final ablyApiKey = dotenv.env['ABLY_KEY'] ?? 'your_ably_api_key_here';
      final clientOptions = ably.ClientOptions(key: ablyApiKey);
      _ablyRealtime = ably.Realtime(options: clientOptions);
      _channel = _ablyRealtime!.channels.get(channelName);

      setState(() {
        _status = 'Ably initialized';
      });
    } catch (e) {
      setState(() {
        _status = 'Error initializing Ably: $e';
      });
    }
  }

  Future<void> _startPublishing() async {
    if (_ablyRealtime == null || _channel == null) {
      setState(() {
        _status = 'Ably not initialized';
      });
      return;
    }

    try {
      // Use LocationService for enhanced GPS tracking
      final hasPermission = await _locationService.requestPermissions();
      if (!hasPermission) {
        setState(() {
          _status = 'Location permissions denied';
        });
        return;
      }

      final isServiceEnabled = await _locationService
          .isLocationServiceEnabled();
      if (!isServiceEnabled) {
        setState(() {
          _status = 'Location services are disabled';
        });
        return;
      }

      setState(() {
        _isPublishing = true;
        _publishingStartTime = DateTime.now().millisecondsSinceEpoch;
        _status = 'Started publishing location updates';
      });

      // Start listening to position updates using LocationService
      _locationService
          .getPositionStream(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          )
          .listen(
            (Position position) {
              setState(() {
                _currentPosition = position;
                _status =
                    'Publishing location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
              });

              // Update map markers and camera
              _updateMarkers();
              _updateMapCamera();

              // Update route if destination is set
              if (_destinationCoords != null) {
                _updateRoute();
                _checkAndPublishArrival(position);
              }

              // Publish location to Ably
              _publishLocation(position);
            },
            onError: (error) {
              setState(() {
                _status = 'Location error: $error';
              });
            },
          );
    } catch (e) {
      setState(() {
        _status = 'Error starting location tracking: $e';
      });
    }
  }

  Future<void> _publishLocation(Position position) async {
    if (_channel == null) return;

    try {
      // Calculate movement data
      final speed = position.speed;
      final heading = position.heading;
      final isMoving = speed > 0.5; // Moving if speed > 0.5 m/s
      final speedKmh = speed * 3.6; // Convert m/s to km/h

      // Calculate route information
      double? distanceToDestination;
      int? estimatedTimeToDestination;
      String? routeStatus;
      Map<String, dynamic>? routeInfo;

      if (_destinationCoords != null) {
        final currentLatLng = LatLng(position.latitude, position.longitude);

        // Calculate straight-line distance
        distanceToDestination = _mapService.calculateStraightLineDistance(
          currentLatLng,
          _destinationCoords!,
        );

        // Estimate time to destination
        if (speed > 0) {
          estimatedTimeToDestination = (distanceToDestination / speed).round();
        }

        // Determine route status
        if (distanceToDestination < 50) {
          routeStatus = 'arrived';
          _handleArrival();
        } else if (distanceToDestination < 100) {
          routeStatus = 'very_close';
        } else if (distanceToDestination < 500) {
          routeStatus = 'approaching';
        } else {
          routeStatus = isMoving ? 'en_route' : 'stationary';
        }

        // Try to get detailed route information
        try {
          final route = await _mapService.calculateRoute(
            currentLatLng,
            _destinationCoords!,
          );
          routeInfo = {
            'distance': route.distanceText,
            'duration': route.durationText,
            'distanceValue': route.distance,
            'durationValue': route.duration,
            'polylinePoints': route.polyline.length,
            'hasRoute': true,
          };
        } catch (e) {
          routeInfo = {
            'hasRoute': false,
            'error': 'Route calculation unavailable',
          };
        }
      }

      // Create comprehensive message
      final message = {
        // Basic location data
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'accuracy': position.accuracy,
        'altitude': position.altitude,

        // Movement data
        'speed': speed, // m/s
        'speedKmh': speedKmh, // km/h for easier reading
        'heading': heading,
        'isMoving': isMoving,
        'movementStatus': isMoving ? 'moving' : 'stationary',

        // Destination information
        'destination': _destination.isNotEmpty ? _destination : null,
        'destinationCoords': _destinationCoords != null
            ? {
                'latitude': _destinationCoords!.latitude,
                'longitude': _destinationCoords!.longitude,
              }
            : null,

        // Route calculations
        'distanceToDestination': distanceToDestination, // meters
        'distanceToDestinationKm': distanceToDestination != null
            ? (distanceToDestination / 1000)
            : null, // km for easier reading
        'estimatedTimeToDestination': estimatedTimeToDestination, // seconds
        'routeStatus': routeStatus,
        'routeInfo': routeInfo,

        // Device and session info
        'publisherId': 'flutter_publisher',
        'deviceType': 'mobile',
        'platform': 'flutter',
        'sessionId': _generateSessionId(),

        // Quality indicators
        'gpsQuality': _getGpsQuality(position.accuracy),
        'batteryOptimized':
            !isMoving, // Indicate if we can optimize for battery
        // Additional metadata
        'publishingDuration': _isPublishing
            ? DateTime.now().millisecondsSinceEpoch - _publishingStartTime
            : 0,
      };

      await _channel!.publish(name: 'location-update', data: message);

      // Also publish route updates separately when route changes significantly
      if (routeInfo != null && routeInfo['hasRoute'] == true) {
        await _channel!.publish(
          name: 'route-update',
          data: {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'publisherId': 'flutter_publisher',
            'destination': _destination,
            'destinationCoords': _destinationCoords != null
                ? {
                    'latitude': _destinationCoords!.latitude,
                    'longitude': _destinationCoords!.longitude,
                  }
                : null,
            'routeInfo': routeInfo,
            'currentLocation': {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
          },
        );
      }
    } catch (e) {
      setState(() {
        _status = 'Error publishing location: $e';
      });
    }
  }

  // Helper variables for session tracking
  int _publishingStartTime = 0;
  String? _sessionId;

  String _generateSessionId() {
    _sessionId ??=
        'session_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    return _sessionId!;
  }

  String _getGpsQuality(double accuracy) {
    if (accuracy <= 5) return 'excellent';
    if (accuracy <= 10) return 'good';
    if (accuracy <= 20) return 'fair';
    if (accuracy <= 50) return 'poor';
    return 'very_poor';
  }

  bool _hasArrivedNotificationSent = false;

  void _handleArrival() {
    if (!_hasArrivedNotificationSent && _channel != null) {
      _hasArrivedNotificationSent = true;

      // Send arrival notification
      _channel!.publish(
        name: 'arrival-notification',
        data: {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'publisherId': 'flutter_publisher',
          'destination': _destination,
          'destinationCoords': _destinationCoords != null
              ? {
                  'latitude': _destinationCoords!.latitude,
                  'longitude': _destinationCoords!.longitude,
                }
              : null,
          'arrivalTime': DateTime.now().toIso8601String(),
          'sessionId': _generateSessionId(),
        },
      );

      setState(() {
        _status = '🎯 Arrived at destination: $_destination';
      });
    }
  }

  Future<void> _checkAndPublishArrival(Position position) async {
    if (_destinationCoords == null || _hasArrivedNotificationSent) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);
    final distance = _mapService.calculateStraightLineDistance(
      currentLatLng,
      _destinationCoords!,
    );

    // Consider arrived if within 50 meters
    if (distance <= 50) {
      _hasArrivedNotificationSent = true;

      await _channel?.publish(
        name: 'arrival-notification',
        data: {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'publisherId': 'flutter_publisher',
          'destination': _destination,
          'destinationCoords': {
            'latitude': _destinationCoords!.latitude,
            'longitude': _destinationCoords!.longitude,
          },
          'arrivalLocation': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
          'finalDistance': distance,
          'accuracy': position.accuracy,
          'arrivalTime': DateTime.now().toIso8601String(),
          'journeyDuration': _publishingStartTime > 0
              ? DateTime.now().millisecondsSinceEpoch - _publishingStartTime
              : null,
        },
      );

      setState(() {
        _status = 'Arrived at destination! 🎉';
      });
    }
  }

  Future<void> _stopPublishing() async {
    setState(() {
      _isPublishing = false;
      _status = 'Stopped publishing';
    });
  }

  Future<void> _sendStatusUpdate(String status) async {
    if (_channel == null || !_isPublishing) return;

    try {
      await _channel!.publish(
        name: 'status-update',
        data: {
          'status': status,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'publisherId': 'flutter_publisher',
          'destination': _destination.isNotEmpty ? _destination : null,
          'currentLocation': _currentPosition != null
              ? {
                  'latitude': _currentPosition!.latitude,
                  'longitude': _currentPosition!.longitude,
                }
              : null,
          'message': 'Status updated to: $status',
        },
      );

      setState(() {
        _status = 'Status sent: $status';
      });

      // Show confirmation snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status "$status" sent successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = 'Error sending status: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send status: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Tracking Publisher'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 16),
                    // Destination input field
                    const Text(
                      'Destination:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Enter destination address',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _geocodeDestination,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _destination = value;
                        });
                      },
                      onSubmitted: (_) => _geocodeDestination(),
                    ),
                    if (_destinationCoords != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green[600],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Destination set: ${_destination}',
                                style: TextStyle(
                                  color: Colors.green[800],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: _clearDestination,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_currentPosition != null) ...[
                      const Text(
                        'Current Location:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                      ),
                      Text(
                        'Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      ),
                      Text(
                        'Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(2)} meters',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isPublishing ? null : _startPublishing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Start Publishing'),
                  ),
                  ElevatedButton(
                    onPressed: _isPublishing ? _stopPublishing : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Stop Publishing'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_currentPosition != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      const Text(
                        'Live Map',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      // Google Maps widget with route info overlay
                      SizedBox(
                        height: 400, // Fixed height for better visibility
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _buildGoogleMap(),
                              ),
                            ),
                            // Route information overlay
                            if (_destinationCoords != null &&
                                _currentPosition != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                right: 8,
                                child: _buildRouteInfoPanel(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Status buttons
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Status Updates',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPublishing ? () => _sendStatusUpdate('Almost there') : null,
                              icon: const Icon(Icons.near_me, size: 18),
                              label: const Text('Almost there'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPublishing ? () => _sendStatusUpdate('Arrived') : null,
                              icon: const Icon(Icons.location_on, size: 18),
                              label: const Text('Arrived'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPublishing ? () => _sendStatusUpdate('Completed') : null,
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: const Text('Completed'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20), // Add some bottom padding
            ],
          ],
        ),
      ),
      floatingActionButton:
          _currentPosition != null && _destinationCoords != null
          ? FloatingActionButton(
              onPressed: _centerMapOnRoute,
              tooltip: 'Center map on route',
              child: const Icon(Icons.center_focus_strong),
            )
          : null,
    );
  }

  void _centerMapOnRoute() {
    if (_mapController == null ||
        _currentPosition == null ||
        _destinationCoords == null) {
      return;
    }

    final currentLatLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(currentLatLng.latitude, _destinationCoords!.latitude),
        math.min(currentLatLng.longitude, _destinationCoords!.longitude),
      ),
      northeast: LatLng(
        math.max(currentLatLng.latitude, _destinationCoords!.latitude),
        math.max(currentLatLng.longitude, _destinationCoords!.longitude),
      ),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100.0));
  }

  Widget _buildGoogleMap() {
    // Default location (New York City) if no current position
    final LatLng initialPosition = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(40.7128, -74.0060);

    return GoogleMap(
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        _updateMapCamera();
      },
      initialCameraPosition: CameraPosition(
        target: initialPosition,
        zoom: 15.0,
      ),
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      compassEnabled: true,
      trafficEnabled: false,
      buildingsEnabled: true,
      // Enable all gestures for better user interaction
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      tiltGesturesEnabled: true,
      rotateGesturesEnabled: true,
      onTap: (LatLng position) {
        // Optional: Handle map taps
      },
    );
  }

  Widget _buildRouteInfoPanel() {
    if (_currentPosition == null || _destinationCoords == null) {
      return const SizedBox.shrink();
    }

    final distance = _mapService.calculateStraightLineDistance(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _destinationCoords!,
    );

    final speed = _currentPosition!.speed;
    final isMoving = speed > 0.5; // Moving if speed > 0.5 m/s

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.navigation, color: Colors.blue[600], size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Route to $_destination',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoItem(
                Icons.straighten,
                'Distance',
                '${(distance / 1000).toStringAsFixed(2)} km',
              ),
              _buildInfoItem(
                Icons.speed,
                'Speed',
                isMoving
                    ? '${(speed * 3.6).toStringAsFixed(1)} km/h'
                    : 'Stationary',
              ),
            ],
          ),
          if (isMoving && speed > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey[600], size: 14),
                const SizedBox(width: 4),
                Text(
                  'ETA: ${_calculateETA(distance, speed)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _calculateETA(double distanceMeters, double speedMps) {
    if (speedMps <= 0) return 'N/A';

    final timeSeconds = distanceMeters / speedMps;
    final hours = (timeSeconds / 3600).floor();
    final minutes = ((timeSeconds % 3600) / 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '<1m';
    }
  }

  void _updateMapCamera() {
    if (_mapController == null || _currentPosition == null) return;

    final currentLatLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    if (_destinationCoords != null) {
      // If we have both current location and destination, fit both in view
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(currentLatLng.latitude, _destinationCoords!.latitude),
          math.min(currentLatLng.longitude, _destinationCoords!.longitude),
        ),
        northeast: LatLng(
          math.max(currentLatLng.latitude, _destinationCoords!.latitude),
          math.max(currentLatLng.longitude, _destinationCoords!.longitude),
        ),
      );

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );
    } else {
      // Just center on current location
      _mapController!.animateCamera(CameraUpdate.newLatLng(currentLatLng));
    }
  }

  void _updateMarkers() {
    _markers.clear();

    // Add current location marker
    if (_currentPosition != null) {
      final speed = _currentPosition!.speed;
      final isMoving = speed > 0.5;
      final accuracy = _currentPosition!.accuracy;

      String snippet =
          'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}, '
          'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}\n';

      if (isMoving) {
        snippet += 'Speed: ${(speed * 3.6).toStringAsFixed(1)} km/h\n';
      } else {
        snippet += 'Status: Stationary\n';
      }

      snippet += 'Accuracy: ${accuracy.toStringAsFixed(1)}m';

      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          infoWindow: InfoWindow(
            title: '📍 Current Location',
            snippet: snippet,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isMoving ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueBlue,
          ),
          rotation: _currentPosition!.heading,
        ),
      );
    }

    // Add destination marker
    if (_destinationCoords != null) {
      String snippet = _destination.isNotEmpty
          ? _destination
          : 'Target Location';

      if (_currentPosition != null) {
        final distance = _mapService.calculateStraightLineDistance(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          _destinationCoords!,
        );
        snippet += '\nDistance: ${(distance / 1000).toStringAsFixed(2)} km';

        // Add proximity indicator
        if (distance < 100) {
          snippet += '\n🎯 Very close!';
        } else if (distance < 500) {
          snippet += '\n📍 Getting closer!';
        }
      }

      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationCoords!,
          infoWindow: InfoWindow(title: '🏁 Destination', snippet: snippet),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
  }

  Future<void> _updateRoute() async {
    if (_currentPosition == null || _destinationCoords == null) {
      _polylines.clear();
      return;
    }

    try {
      final currentLatLng = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      final route = await _mapService.calculateRoute(
        currentLatLng,
        _destinationCoords!,
      );

      _polylines.clear();

      // Add shadow/outline for better visibility
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_shadow'),
          points: route.polyline,
          color: Colors.black.withOpacity(0.3),
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );

      // Add main route line
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: route.polyline,
          color: Colors.blue,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );

      setState(() {
        // Update UI with route info
        _status = 'Route: ${route.distanceText}, ${route.durationText}';
      });
    } catch (e) {
      // Fallback to straight line if route calculation fails
      _polylines.clear();

      final points = [
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        _destinationCoords!,
      ];

      // Add dashed straight line as fallback
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('straight_line'),
          points: points,
          color: Colors.orange,
          width: 3,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );

      setState(() {
        _status = 'Using straight-line route (route calculation unavailable)';
      });
    }
  }

  Future<void> _geocodeDestination() async {
    if (_destination.trim().isEmpty) return;

    setState(() {
      _status = 'Finding destination...';
    });

    try {
      final coordinates = await _mapService.geocodeAddress(_destination.trim());
      if (coordinates != null) {
        setState(() {
          _destinationCoords = coordinates;
          _hasArrivedNotificationSent =
              false; // Reset arrival status for new destination
          _status = 'Destination found: $_destination';
        });

        // Update markers and route
        _updateMarkers();
        _updateMapCamera();
        if (_currentPosition != null) {
          _updateRoute();
        }
      } else {
        setState(() {
          _status = 'Destination not found: ${_destination}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error finding destination: $e';
      });
    }
  }

  void _clearDestination() {
    setState(() {
      _destination = '';
      _destinationCoords = null;
      _hasArrivedNotificationSent = false; // Reset arrival status
      _polylines.clear();
      _status = _isPublishing ? 'Publishing location updates' : 'Ready';
    });
    _updateMarkers();
  }

  @override
  void dispose() {
    _locationService.dispose();
    _errorHandler.dispose();
    _ablyRealtime?.close();
    super.dispose();
  }
}
