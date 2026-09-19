import 'package:flutter/material.dart';

class TaskTransitionLoader extends StatelessWidget {
  final String message;
  final Color? backgroundColor;
  final Color? loaderColor;

  const TaskTransitionLoader({
    super.key,
    required this.message,
    this.backgroundColor,
    this.loaderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.black.withOpacity(0.7),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Container(
            padding: EdgeInsets.all(24),
            margin: EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated loader
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      loaderColor ?? Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                // Message text
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                // Subtitle
                Text(
                  'Please wait...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper class to show/hide the loader overlay
class TaskTransitionLoaderController {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  /// Show the loader overlay
  static void show({
    required BuildContext context,
    required String message,
    Color? backgroundColor,
    Color? loaderColor,
  }) {
    // Prevent multiple loaders from showing
    if (_isShowing) return;

    // Hide any existing loader first
    hide();

    _overlayEntry = OverlayEntry(
      builder: (context) => TaskTransitionLoader(
        message: message,
        backgroundColor: backgroundColor,
        loaderColor: loaderColor,
      ),
    );

    _isShowing = true;
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Hide the loader overlay
  static void hide() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    _isShowing = false;
  }

  /// Check if loader is currently showing
  static bool get isShowing => _isShowing;
}
