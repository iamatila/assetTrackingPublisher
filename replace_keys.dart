import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  final googleMapsApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? 'YOUR_GOOGLE_MAPS_API_KEY';
  
  // Read AndroidManifest.xml
  final manifestPath = 'android/app/src/main/AndroidManifest.xml';
  final manifestContent = await File(manifestPath).readAsString();
  
  // Replace placeholder with actual key
  final updatedContent = manifestContent.replaceAll(
    'YOUR_GOOGLE_MAPS_API_KEY', 
    googleMapsApiKey
  );
  
  // Write back to file
  await File(manifestPath).writeAsString(updatedContent);
  
  print('Successfully updated Google Maps API key in AndroidManifest.xml');
}