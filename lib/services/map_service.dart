import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math';

class MapService {
  static MapService? _instance;
  static MapService get instance => _instance ??= MapService._();
  MapService._();

  static const String _geocodingBaseUrl = 'https://maps.googleapis.com/maps/api/geocode/json';
  static const String _directionsBaseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Geocode an address to coordinates
  Future<LatLng?> geocodeAddress(String address) async {
    if (address.isEmpty || _apiKey.isEmpty) return null;

    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = '$_geocodingBaseUrl?address=$encodedAddress&key=$_apiKey';
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        }
      }
      
      return null;
    } catch (e) {
      throw MapServiceException('Geocoding failed: $e');
    }
  }

  /// Reverse geocode coordinates to address
  Future<String?> reverseGeocode(LatLng coordinates) async {
    if (_apiKey.isEmpty) return null;

    try {
      final url = '$_geocodingBaseUrl?latlng=${coordinates.latitude},${coordinates.longitude}&key=$_apiKey';
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
      
      return null;
    } catch (e) {
      throw MapServiceException('Reverse geocoding failed: $e');
    }
  }

  /// Calculate route between two points
  Future<RouteResult> calculateRoute(LatLng start, LatLng end, {
    String travelMode = 'driving',
    bool avoidTolls = false,
    bool avoidHighways = false,
  }) async {
    if (_apiKey.isEmpty) {
      throw MapServiceException('Google Maps API key not configured');
    }

    try {
      final startStr = '${start.latitude},${start.longitude}';
      final endStr = '${end.latitude},${end.longitude}';
      
      var url = '$_directionsBaseUrl?origin=$startStr&destination=$endStr&mode=$travelMode&key=$_apiKey';
      
      if (avoidTolls) url += '&avoid=tolls';
      if (avoidHighways) url += '&avoid=highways';
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          return _parseRouteResponse(data['routes'][0]);
        } else {
          throw MapServiceException('No route found: ${data['status']}');
        }
      } else {
        throw MapServiceException('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw MapServiceException('Route calculation failed: $e');
    }
  }

  /// Get route information (distance and duration)
  Future<RouteInfo> getRouteInfo(LatLng start, LatLng end) async {
    try {
      final route = await calculateRoute(start, end);
      return RouteInfo(
        distance: route.distance,
        duration: route.duration,
        distanceText: route.distanceText,
        durationText: route.durationText,
      );
    } catch (e) {
      // Fallback to straight-line distance
      final distance = calculateStraightLineDistance(start, end);
      return RouteInfo(
        distance: distance.round(),
        duration: (distance / 50 * 60).round(), // Rough estimate: 50 km/h average
        distanceText: '${(distance / 1000).toStringAsFixed(1)} km',
        durationText: '${(distance / 50 * 60).round()} min',
      );
    }
  }

  /// Parse route response from Google Directions API
  RouteResult _parseRouteResponse(Map<String, dynamic> route) {
    final leg = route['legs'][0];
    final polylinePoints = _decodePolyline(route['overview_polyline']['points']);
    
    final steps = <RouteStep>[];
    for (final step in leg['steps']) {
      steps.add(RouteStep(
        instruction: _stripHtmlTags(step['html_instructions']),
        distance: step['distance']['value'],
        duration: step['duration']['value'],
        distanceText: step['distance']['text'],
        durationText: step['duration']['text'],
        startLocation: LatLng(
          step['start_location']['lat'],
          step['start_location']['lng'],
        ),
        endLocation: LatLng(
          step['end_location']['lat'],
          step['end_location']['lng'],
        ),
      ));
    }

    return RouteResult(
      polyline: polylinePoints,
      distance: leg['distance']['value'],
      duration: leg['duration']['value'],
      distanceText: leg['distance']['text'],
      durationText: leg['duration']['text'],
      steps: steps,
      bounds: _calculateBounds(polylinePoints),
    );
  }

  /// Decode Google polyline encoding
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  /// Calculate bounds for a list of points
  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(0, 0),
        northeast: const LatLng(0, 0),
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// Calculate straight-line distance between two points
  double calculateStraightLineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final lat1Rad = start.latitude * pi / 180;
    final lat2Rad = end.latitude * pi / 180;
    final deltaLatRad = (end.latitude - start.latitude) * pi / 180;
    final deltaLngRad = (end.longitude - start.longitude) * pi / 180;

    final a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Strip HTML tags from text
  String _stripHtmlTags(String htmlText) {
    return htmlText.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}

// Data models
class RouteResult {
  final List<LatLng> polyline;
  final int distance; // in meters
  final int duration; // in seconds
  final String distanceText;
  final String durationText;
  final List<RouteStep> steps;
  final LatLngBounds bounds;

  RouteResult({
    required this.polyline,
    required this.distance,
    required this.duration,
    required this.distanceText,
    required this.durationText,
    required this.steps,
    required this.bounds,
  });
}

class RouteStep {
  final String instruction;
  final int distance;
  final int duration;
  final String distanceText;
  final String durationText;
  final LatLng startLocation;
  final LatLng endLocation;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.distanceText,
    required this.durationText,
    required this.startLocation,
    required this.endLocation,
  });
}

class RouteInfo {
  final int distance;
  final int duration;
  final String distanceText;
  final String durationText;

  RouteInfo({
    required this.distance,
    required this.duration,
    required this.distanceText,
    required this.durationText,
  });
}

class MapServiceException implements Exception {
  final String message;
  MapServiceException(this.message);
  
  @override
  String toString() => 'MapServiceException: $message';
}