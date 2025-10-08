import 'dart:io';
import 'dart:convert';

// Simple test script to validate API key functionality
Future<void> main() async {
  print('Testing API key validation...');
  
  // Test environment file reading
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('❌ .env file not found');
    return;
  }
  
  final envContent = await envFile.readAsString();
  final envMap = <String, String>{};
  
  for (final line in envContent.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('#') && trimmed.contains('=')) {
      final parts = trimmed.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        envMap[key] = value;
      }
    }
  }
  
  // Test Ably key validation
  final ablyKey = envMap['ABLY_KEY'];
  if (ablyKey != null && ablyKey.isNotEmpty && ablyKey != 'your_ably_api_key_here') {
    if (ablyKey.contains('.') && ablyKey.contains(':')) {
      print('✓ Ably API key format is valid');
    } else {
      print('❌ Ably API key format is invalid');
    }
  } else {
    print('❌ Ably API key is missing or not configured');
  }
  
  // Test Google Maps key validation
  final googleMapsKey = envMap['GOOGLE_MAPS_API_KEY'];
  if (googleMapsKey != null && googleMapsKey.isNotEmpty && googleMapsKey != 'your_google_maps_api_key_here') {
    print('✓ Google Maps API key is configured');
    
    // Test if we can make a simple HTTP request (basic validation)
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=test&key=$googleMapsKey'));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        final status = data['status'];
        
        if (status == 'OK' || status == 'ZERO_RESULTS') {
          print('✓ Google Maps API key is valid and working');
        } else if (status == 'REQUEST_DENIED') {
          print('❌ Google Maps API key is invalid or restricted');
        } else {
          print('⚠️ Google Maps API returned status: $status');
        }
      } else {
        print('❌ Failed to validate Google Maps API key (HTTP ${response.statusCode})');
      }
      
      client.close();
    } catch (e) {
      print('⚠️ Could not test Google Maps API key: $e');
    }
  } else {
    print('❌ Google Maps API key is missing or not configured');
  }
  
  print('\nAPI key validation test completed.');
}