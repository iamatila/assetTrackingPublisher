import 'dart:io';

Future<void> main() async {
  try {
    // Check if .env file exists
    final envFile = File('.env');
    if (!await envFile.exists()) {
      stderr.writeln('Error: .env file not found. Please create one based on .env.example');
      exit(1);
    }

    // Read .env file manually
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
    
    final googleMapsApiKey = envMap['GOOGLE_MAPS_API_KEY'];
    final ablyKey = envMap['ABLY_KEY'];
    
    // Validate API keys
    if (googleMapsApiKey == null || googleMapsApiKey.isEmpty || googleMapsApiKey == 'your_google_maps_api_key_here') {
      stderr.writeln('Warning: GOOGLE_MAPS_API_KEY is not properly configured in .env file');
    }
    
    if (ablyKey == null || ablyKey.isEmpty || ablyKey == 'your_ably_api_key_here') {
      stderr.writeln('Warning: ABLY_KEY is not properly configured in .env file');
    }
    
    // Update AndroidManifest.xml
    await _updateAndroidManifest(googleMapsApiKey ?? 'YOUR_GOOGLE_MAPS_API_KEY');
    
    stdout.writeln('✓ Successfully updated API keys configuration');
    
  } catch (e) {
    stderr.writeln('Error updating API keys: $e');
    exit(1);
  }
}

Future<void> _updateAndroidManifest(String googleMapsApiKey) async {
  final manifestPath = 'android/app/src/main/AndroidManifest.xml';
  final manifestFile = File(manifestPath);
  
  if (!await manifestFile.exists()) {
    throw Exception('AndroidManifest.xml not found at $manifestPath');
  }
  
  final manifestContent = await manifestFile.readAsString();
  
  // Replace placeholder with actual key
  final updatedContent = manifestContent.replaceAll(
    'YOUR_GOOGLE_MAPS_API_KEY', 
    googleMapsApiKey
  );
  
  // Only write if content changed
  if (updatedContent != manifestContent) {
    await manifestFile.writeAsString(updatedContent);
    stdout.writeln('✓ Updated Google Maps API key in AndroidManifest.xml');
  } else {
    stdout.writeln('ℹ AndroidManifest.xml already up to date');
  }
}