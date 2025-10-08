import 'package:flutter/material.dart';
import '../services/error_handler_service.dart';

class ErrorDisplayWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final List<String>? suggestions;
  final bool isRetrying;

  const ErrorDisplayWidget({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.suggestions,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (suggestions != null && suggestions!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Suggestions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...suggestions!.map((suggestion) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(suggestion)),
                      ],
                    ),
                  )),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: isRetrying ? null : onRetry,
                    icon: isRetrying 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                    label: Text(isRetrying ? 'Retrying...' : 'Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SmartErrorDisplayWidget extends StatefulWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final String? context;

  const SmartErrorDisplayWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.context,
  });

  @override
  State<SmartErrorDisplayWidget> createState() => _SmartErrorDisplayWidgetState();
}

class _SmartErrorDisplayWidgetState extends State<SmartErrorDisplayWidget> {
  bool _isRetrying = false;
  final ErrorHandlerService _errorHandler = ErrorHandlerService.instance;

  @override
  Widget build(BuildContext context) {
    final errorInfo = _errorHandler.getErrorInfo(widget.error);
    
    return ErrorDisplayWidget(
      title: errorInfo.title,
      message: errorInfo.message,
      suggestions: errorInfo.suggestions,
      isRetrying: _isRetrying,
      onRetry: errorInfo.canRetry && widget.onRetry != null ? _handleRetry : null,
    );
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    
    setState(() {
      _isRetrying = true;
    });

    try {
      widget.onRetry?.call();
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }
}

class ApiKeyErrorWidget extends StatelessWidget {
  final String apiKeyType;
  final String error;
  final VoidCallback? onRetry;

  const ApiKeyErrorWidget({
    super.key,
    required this.apiKeyType,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = _getSuggestions(apiKeyType, error);
    
    return ErrorDisplayWidget(
      title: '$apiKeyType API Key Error',
      message: error,
      onRetry: onRetry,
      suggestions: suggestions,
    );
  }

  List<String> _getSuggestions(String apiKeyType, String error) {
    if (apiKeyType.toLowerCase().contains('google')) {
      return [
        'Check that your .env file contains a valid GOOGLE_MAPS_API_KEY',
        'Ensure the Google Maps API is enabled in Google Cloud Console',
        'Verify the API key has the correct permissions (Maps SDK for Android, Geocoding API)',
        'Check that billing is enabled for your Google Cloud project',
        'Run the setup script: dart run scripts/simple_replace_keys.dart',
      ];
    } else if (apiKeyType.toLowerCase().contains('ably')) {
      return [
        'Check that your .env file contains a valid ABLY_KEY',
        'Ensure the Ably key format is correct: appId.keyId:keySecret',
        'Verify your Ably account is active and the key is not expired',
        'Check the Ably dashboard for any usage limits or restrictions',
      ];
    }
    
    return [
      'Check your .env file configuration',
      'Ensure all required API keys are properly set',
      'Restart the application after updating API keys',
    ];
  }
}