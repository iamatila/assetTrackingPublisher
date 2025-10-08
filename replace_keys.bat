@echo off
echo Running key replacement script...
dart scripts/replace_keys.dart
if %errorlevel% == 0 (
    echo Keys successfully replaced in AndroidManifest.xml
) else (
    echo Error occurred while replacing keys
)
pause