import 'package:flutter/material.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// A widget that catches Flutter framework errors in its child widget subtree
/// and displays a friendly error message instead of crashing the app.
class ErrorBoundaryWidget extends StatefulWidget {
  final Widget child;
  final Widget? fallbackWidget;

  const ErrorBoundaryWidget({
    Key? key,
    required this.child,
    this.fallbackWidget,
  }) : super(key: key);

  @override
  State<ErrorBoundaryWidget> createState() => _ErrorBoundaryWidgetState();
}

class _ErrorBoundaryWidgetState extends State<ErrorBoundaryWidget> {
  bool _hasError = false;
  FlutterErrorDetails? _errorDetails;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Return the fallback widget or default error widget
      return widget.fallbackWidget ?? _buildDefaultErrorWidget();
    }

    return ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
      // Log the error
      AppLogger.error(
        'ErrorBoundaryWidget caught an error: ${errorDetails.exception}',
        stackTrace: errorDetails.stack,
      );

      // Update state to show the error UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorDetails = errorDetails;
          });
        }
      });

      // Return an empty container as a placeholder until the setState takes effect
      return Container();
    };
  }

  Widget _buildDefaultErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 48.0,
            ),
            const SizedBox(height: 16.0),
            Text(
              'Something went wrong',
              style: AppTextStyles.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              'We encountered an error while displaying this screen. Please try again.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorDetails = null;
                });
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
