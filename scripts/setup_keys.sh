#!/bin/bash

# Script to set up API keys for the Flutter app
echo "Setting up API keys for Asset Tracking Publisher..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "Please edit .env file with your actual API keys before running the app."
    exit 1
fi

# Run the Dart script to replace keys
echo "Updating AndroidManifest.xml with API keys..."
dart run scripts/simple_replace_keys.dart

echo "API key setup complete!"
echo ""
echo "Next steps:"
echo "1. Make sure your .env file contains valid API keys"
echo "2. Run 'flutter pub get' to install dependencies"
echo "3. Run 'flutter run' to start the app"