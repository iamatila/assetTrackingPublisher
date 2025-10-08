# Asset Tracking Publisher

This is the Flutter application for publishing asset location data.

## Environment Variables

Create a `.env` file in the root of this project with the following variables:

```
ABLY_KEY=your_ably_api_key_here
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

## Setup

1. Create an Ably account and get your API key from the [Ably dashboard](https://ably.com/accounts)
2. Create a Google Cloud project and enable the Maps SDK for Android/iOS, then get your API key
3. Add your keys to the `.env` file

## Building the Application

Before building the application, you need to run a script to replace the API keys in the AndroidManifest.xml file:

```bash
cd asset_tracking_publisher
flutter pub get
dart scripts/replace_keys.dart
flutter run
```

Alternatively, you can manually update the `android/app/src/main/AndroidManifest.xml` file by replacing `YOUR_GOOGLE_MAPS_API_KEY` with your actual Google Maps API key.

## Features

- Real-time location tracking using GPS
- Publishing location data to Ably channels
- Destination input field for setting navigation targets
- Map preview of current location