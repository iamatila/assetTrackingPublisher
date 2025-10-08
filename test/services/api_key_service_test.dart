import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../lib/services/api_key_service.dart';

void main() {
  group('ApiKeyService', () {
    setUp(() async {
      // Load test environment variables
      await dotenv.load(fileName: ".env.example");
    });

    test('should detect missing Google Maps API key', () async {
      // Test with default placeholder value
      final result = await ApiKeyService.validateGoogleMapsApiKey();
      
      expect(result.isValid, false);
      expect(result.error, contains('missing or not configured'));
    });

    test('should detect missing Ably API key', () {
      // Test with default placeholder value
      final result = ApiKeyService.validateAblyApiKey();
      
      expect(result.isValid, false);
      expect(result.error, contains('missing or not configured'));
    });

    test('should validate Ably key format', () {
      // Mock a properly formatted Ably key
      dotenv.env['ABLY_KEY'] = 'appId.keyId:keySecret';
      
      final result = ApiKeyService.validateAblyApiKey();
      
      expect(result.isValid, true);
      expect(result.error, isNull);
    });

    test('should detect invalid Ably key format', () {
      // Mock an improperly formatted Ably key
      dotenv.env['ABLY_KEY'] = 'invalid-key-format';
      
      final result = ApiKeyService.validateAblyApiKey();
      
      expect(result.isValid, false);
      expect(result.error, contains('format is invalid'));
    });

    test('should validate all API keys', () async {
      // Mock properly formatted keys
      dotenv.env['ABLY_KEY'] = 'appId.keyId:keySecret';
      dotenv.env['GOOGLE_MAPS_API_KEY'] = 'AIzaSyTest123'; // This will fail validation but pass format check
      
      final results = await ApiKeyService.validateAllApiKeys();
      
      expect(results.containsKey('ably'), true);
      expect(results.containsKey('googleMaps'), true);
      expect(results['ably']!.isValid, true);
      // Google Maps will be invalid due to test key, but that's expected
    });
  });
}