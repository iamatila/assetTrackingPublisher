# API Key Setup Guide

This guide explains how to properly configure API keys for the Asset Tracking Publisher app.

## Required API Keys

### 1. Google Maps API Key

The app requires a Google Maps API key for map functionality and geocoding services.

**Steps to get a Google Maps API key:**

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the following APIs:
   - Maps SDK for Android
   - Geocoding API
   - Directions API (for route calculation)
4. Go to "Credentials" and create a new API key
5. Restrict the API key to your app's package name for security

**Required API permissions:**
- Maps SDK for Android
- Geocoding API
- Directions API

### 2. Ably API Key

The app uses Ably for real-time communication between publisher and subscriber.

**Steps to get an Ably API key:**

1. Sign up at [Ably.com](https://ably.com/)
2. Create a new app in your dashboard
3. Copy the API key from the "API Keys" tab
4. The key format should be: `appId.keyId:keySecret`

## Configuration Steps

### 1. Environment File Setup

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your actual API keys:
   ```
   ABLY_KEY=your_actual_ably_key_here
   GOOGLE_MAPS_API_KEY=your_actual_google_maps_key_here
   ```

### 2. Run Setup Script

Execute the setup script to configure the Android manifest:

```bash
# Make the script executable (Linux/Mac)
chmod +x scripts/setup_keys.sh

# Run the setup script
./scripts/setup_keys.sh
```

Or run the Dart script directly:
```bash
dart run scripts/replace_keys.dart
```

### 3. Verify Configuration

The app will automatically validate your API keys on startup. If there are any issues, you'll see error messages in the app status.

## Troubleshooting

### Common Issues

1. **"Google Maps API key is missing"**
   - Check that your `.env` file exists and contains the `GOOGLE_MAPS_API_KEY`
   - Ensure you've run the setup script

2. **"Google Maps API key is invalid or restricted"**
   - Verify the API key is correct
   - Check that the required APIs are enabled in Google Cloud Console
   - Ensure the API key isn't restricted to exclude your app

3. **"Ably API key format is invalid"**
   - Ably keys should contain a dot (.) and colon (:)
   - Format: `appId.keyId:keySecret`

4. **"Request denied" errors**
   - Check API quotas and billing in Google Cloud Console
   - Verify API key restrictions aren't too strict

### Testing API Keys

You can test your API key configuration by running the unit tests:

```bash
flutter test test/services/api_key_service_test.dart
```

## Security Best Practices

1. **Never commit API keys to version control**
   - The `.env` file is in `.gitignore`
   - Use environment variables in production

2. **Restrict API keys appropriately**
   - Limit Google Maps API key to your app's package name
   - Set usage quotas to prevent unexpected charges

3. **Rotate keys regularly**
   - Update API keys periodically
   - Monitor usage in respective dashboards

4. **Use different keys for development and production**
   - Keep separate API keys for different environments
   - Use more restrictive settings in production

## Production Deployment

For production deployment:

1. Set up environment variables on your deployment platform
2. Use the key replacement script in your build process
3. Ensure API keys have appropriate restrictions
4. Monitor API usage and set up billing alerts