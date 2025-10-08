import 'package:flutter/material.dart';
import '../services/error_handler_service.dart';
import 'error_recovery_widget.dart';

class AppErrorBoundary extends StatefulWidget {
  final Widget child;
  final String? context;

  const AppErrorBoundary({
    super.key,
    required this.child,
    this.context,
  });

  @override
  State<AppErrorBoundary> createState() => _AppErrorBoundaryState();
}

class _AppErrorBoundaryState extends State<AppErrorBoundary> {
  final ErrorHandlerService _errorHandler = ErrorHandlerService.instance;
  dynamic _lastError;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    
    // Listen to error stream
    _errorHandler.errorStream.listen((appError) {
      if (appError.severity == ErrorSeverity.critical) {
        setState(() {
          _lastError = appError.originalError;
          _hasError = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError && _lastError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error Recovery'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
        body: ErrorRecoveryWidget(
          error: _lastError,
          context: widget.context,
          onRecovered: _clearError,
          onDismiss: _clearError,
        ),
      );
    }

    return widget.child;
  }

  void _clearError() {
    setState(() {
      _hasError = false;
      _lastError = null;
    });
  }
}

class ConnectionStatusWidget extends StatefulWidget {
  final Widget child;

  const ConnectionStatusWidget({
    super.key,
    required this.child,
  });

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  final ErrorHandlerService _errorHandler = ErrorHandlerService.instance;
  bool _isOnline = true;
  bool _isCheckingConnection = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isCheckingConnection = true;
    });

    try {
      final hasConnection = await _errorHandler.hasNetworkConnection();
      setState(() {
        _isOnline = hasConnection;
        _isCheckingConnection = false;
      });
    } catch (e) {
      setState(() {
        _isOnline = false;
        _isCheckingConnection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        
        // Connection status banner
        if (!_isOnline && !_isCheckingConnection)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No internet connection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _checkConnection,
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // Checking connection overlay
        if (_isCheckingConnection)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Checking connection...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ServiceStatusIndicator extends StatefulWidget {
  final String serviceName;
  final Future<ServiceStatus> Function() statusChecker;

  const ServiceStatusIndicator({
    super.key,
    required this.serviceName,
    required this.statusChecker,
  });

  @override
  State<ServiceStatusIndicator> createState() => _ServiceStatusIndicatorState();
}

class _ServiceStatusIndicatorState extends State<ServiceStatusIndicator> {
  ServiceStatus _status = ServiceStatus.unknown;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final status = await widget.statusChecker();
      setState(() {
        _status = status;
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _status = ServiceStatus.error;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor().withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isChecking)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else
            Icon(
              _getStatusIcon(),
              size: 12,
              color: _getStatusColor(),
            ),
          const SizedBox(width: 4),
          Text(
            widget.serviceName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: _getStatusColor(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_status) {
      case ServiceStatus.available:
        return Colors.green;
      case ServiceStatus.degraded:
        return Colors.orange;
      case ServiceStatus.unavailable:
      case ServiceStatus.error:
        return Colors.red;
      case ServiceStatus.unknown:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case ServiceStatus.available:
        return Icons.check_circle;
      case ServiceStatus.degraded:
        return Icons.warning;
      case ServiceStatus.unavailable:
      case ServiceStatus.error:
        return Icons.error;
      case ServiceStatus.unknown:
        return Icons.help;
    }
  }
}