import 'package:flutter/material.dart';
import '../services/error_handler_service.dart';

class ErrorRecoveryWidget extends StatefulWidget {
  final dynamic error;
  final String? context;
  final VoidCallback? onRecovered;
  final VoidCallback? onDismiss;

  const ErrorRecoveryWidget({
    super.key,
    required this.error,
    this.context,
    this.onRecovered,
    this.onDismiss,
  });

  @override
  State<ErrorRecoveryWidget> createState() => _ErrorRecoveryWidgetState();
}

class _ErrorRecoveryWidgetState extends State<ErrorRecoveryWidget> {
  final ErrorHandlerService _errorHandler = ErrorHandlerService.instance;
  List<RecoveryAction> _recoveryActions = [];
  bool _isRecovering = false;
  String? _recoveryStatus;

  @override
  void initState() {
    super.initState();
    _loadRecoveryActions();
  }

  void _loadRecoveryActions() {
    _recoveryActions = _errorHandler.getRecoveryActions(widget.error, widget.context);
  }

  @override
  Widget build(BuildContext context) {
    final errorInfo = _errorHandler.getErrorInfo(widget.error);
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorInfo.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Error message
            Text(
              errorInfo.message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            
            const SizedBox(height: 16),
            
            // Recovery status
            if (_recoveryStatus != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isRecovering 
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    if (_isRecovering)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _recoveryStatus!,
                        style: TextStyle(
                          color: _isRecovering ? Colors.blue : Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Recovery actions
            if (_recoveryActions.isNotEmpty) ...[
              Text(
                'Recovery Options:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              ..._recoveryActions.map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildRecoveryActionTile(action),
              )),
            ],
            
            // Suggestions
            if (errorInfo.suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  'Troubleshooting Tips',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: errorInfo.suggestions.map((suggestion) => 
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.lightbulb_outline, size: 16),
                    title: Text(
                      suggestion,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryActionTile(RecoveryAction action) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          _getActionIcon(action.title),
          color: Theme.of(context).primaryColor,
          size: 20,
        ),
        title: Text(
          action.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          action.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: _isRecovering 
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _isRecovering ? null : () => _executeRecoveryAction(action),
      ),
    );
  }

  IconData _getActionIcon(String title) {
    switch (title.toLowerCase()) {
      case 'retry':
        return Icons.refresh;
      case 'check connection':
        return Icons.wifi;
      case 'switch network':
        return Icons.network_wifi;
      case 'use last known location':
        return Icons.my_location;
      case 'manual location entry':
        return Icons.edit_location;
      case 'use offline mode':
        return Icons.offline_bolt;
      case 'retry connection':
        return Icons.cloud_sync;
      default:
        return Icons.build;
    }
  }

  Future<void> _executeRecoveryAction(RecoveryAction action) async {
    setState(() {
      _isRecovering = true;
      _recoveryStatus = 'Executing ${action.title}...';
    });

    try {
      final success = await _errorHandler.executeRecoveryAction(action);
      
      setState(() {
        _isRecovering = false;
        _recoveryStatus = success 
          ? '${action.title} completed successfully'
          : '${action.title} failed';
      });

      if (success) {
        // Wait a moment to show success message
        await Future.delayed(const Duration(seconds: 1));
        widget.onRecovered?.call();
      }
    } catch (e) {
      setState(() {
        _isRecovering = false;
        _recoveryStatus = 'Error during ${action.title}: ${e.toString()}';
      });
    }
  }
}

class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorWidget({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Internet Connection',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceUnavailableWidget extends StatelessWidget {
  final String serviceName;
  final VoidCallback? onRetry;

  const ServiceUnavailableWidget({
    super.key,
    required this.serviceName,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber,
              size: 64,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 16),
            Text(
              '$serviceName Unavailable',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.orange[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The $serviceName service is currently unavailable. Some features may be limited.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue Anyway'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}