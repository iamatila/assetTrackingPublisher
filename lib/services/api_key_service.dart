import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiKeyService {
  static const String _googleMapsApiUrl = 'https://maps.googleapis.com/maps/api/geocode/json';
  
  /// Validates the Google Maps API key by making a test request
  static Future<ApiKeyValidationResult> validateGoogleMapsApiKey() async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_google_maps_api_key_here') {
        return ApiKeyValidationResult(
          isValid: false,
          error: 'Google Maps API key is missing or not configured. Please check your .env file.',
        );
      }

      // Test the API key with a simple geocoding request
      final testUrl = '$_googleMapsApiUrl?address=test&key=$apiKey';
      final response = await http.get(Uri.parse(testUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];
        
        if (status == 'OK' || status == 'ZERO_RESULTS') {
          return ApiKeyValidationResult(isValid: true);
        } else if (status == 'REQUEST_DENIED') {
          return ApiKeyValidationResult(
            isValid: false,
            error: 'Google Maps API key is invalid or restricted. Status: $status',
          );
        } else {
          return ApiKeyValidationResult(
            isValid: false,
            error: 'Google Maps API returned unexpected status: $status',
          );
        }
      } else {
        return ApiKeyValidationResult(
          isValid: false,
          error: 'Failed to validate API key. HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return ApiKeyValidationResult(
        isValid: false,
        error: 'Error validating Google Maps API key: $e',
      );
    }
  }

  /// Validates the Ably API key format
  static ApiKeyValidationResult validateAblyApiKey() {
    try {
      final apiKey = dotenv.env['ABLY_KEY'];
      
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_ably_api_key_here') {
        return ApiKeyValidationResult(
          isValid: false,
          error: 'Ably API key is missing or not configured. Please check your .env file.',
        );
      }

      // Basic Ably key format validation (should contain a dot and colon)
      if (!apiKey.contains('.') || !apiKey.contains(':')) {
        return ApiKeyValidationResult(
          isValid: false,
          error: 'Ably API key format is invalid. Expected format: appId.keyId:keySecret',
        );
      }

      return ApiKeyValidationResult(isValid: true);
    } catch (e) {
      return ApiKeyValidationResult(
        isValid: false,
        error: 'Error validating Ably API key: $e',
      );
    }
  }

  /// Validates all required API keys
  static Future<Map<String, ApiKeyValidationResult>> validateAllApiKeys() async {
    final results = <String, ApiKeyValidationResult>{};
    
    // Validate Ably key (synchronous)
    results['ably'] = validateAblyApiKey();
    
    // Validate Google Maps key (asynchronous)
    results['googleMaps'] = await validateGoogleMapsApiKey();
    
    return results;
  }
}

class ApiKeyValidationResult {
  final bool isValid;
  final String? error;

  ApiKeyValidationResult({
    required this.isValid,
    this.error,
  });

  @override
  String toString() {
    return isValid ? 'Valid' : 'Invalid: $error';
  }
}