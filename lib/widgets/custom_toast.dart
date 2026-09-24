import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

enum ToastType { info, success, error, warning }

class CustomToast {
  CustomToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void show(
    String message, {
    BuildContext? context,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
  }) {
    // 1. Resolve OverlayState properly
    OverlayState? overlayState;
    if (context != null) {
      overlayState = Overlay.maybeOf(context);
    }
    overlayState ??= Get.key.currentState?.overlay;
    if (overlayState == null && Get.context != null) {
      overlayState = Overlay.maybeOf(Get.context!);
    }

    // 2. If OverlayState cannot be found, fallback to GetX snackbar
    if (overlayState == null) {
      debugPrint("[CustomToast] Overlay not ready, falling back to Get.rawSnackbar");
      Get.rawSnackbar(
        message: message,
        backgroundColor: backgroundColor ?? _getDefaultBg(type),
        duration: duration,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        borderRadius: 12,
        icon: Icon(
          icon ?? _getDefaultIcon(type),
          color: Colors.white,
        ),
      );
      return;
    }

    _dismiss();

    final entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        customIcon: icon,
        backgroundColor: backgroundColor,
        textColor: textColor,
        duration: duration,
        onDismiss: _dismiss,
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _timer = Timer(duration + const Duration(milliseconds: 300), () {
      _dismiss();
    });
  }

  static void showSuccess(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
  }) {
    show(
      message,
      context: context,
      type: ToastType.success,
      duration: duration,
    );
  }

  static void showError(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
  }) {
    show(
      message,
      context: context,
      type: ToastType.error,
      duration: duration,
    );
  }

  static void showInfo(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
  }) {
    show(
      message,
      context: context,
      type: ToastType.info,
      duration: duration,
    );
  }

  static Color _getDefaultBg(ToastType type) {
    switch (type) {
      case ToastType.success:
        return const Color(0xFF1B873F);
      case ToastType.error:
        return const Color(0xFFD32F2F);
      case ToastType.warning:
        return const Color(0xFFE65100);
      case ToastType.info:
        return const Color(0xFF2B2D42);
    }
  }

  static IconData _getDefaultIcon(ToastType type) {
    switch (type) {
      case ToastType.success:
        return Icons.check_circle_outline_rounded;
      case ToastType.error:
        return Icons.error_outline_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_currentEntry != null) {
      if (_currentEntry!.mounted) {
        _currentEntry!.remove();
      }
      _currentEntry = null;
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final IconData? customIcon;
  final Color? backgroundColor;
  final Color? textColor;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    this.customIcon,
    this.backgroundColor,
    this.textColor,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    // Reverse animation before dismissal
    Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBackgroundColor() {
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    switch (widget.type) {
      case ToastType.success:
        return const Color(0xFF1B873F);
      case ToastType.error:
        return const Color(0xFFD32F2F);
      case ToastType.warning:
        return const Color(0xFFE65100);
      case ToastType.info:
        return const Color(0xFF2B2D42);
    }
  }

  IconData _getIcon() {
    if (widget.customIcon != null) return widget.customIcon!;
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle_outline_rounded;
      case ToastType.error:
        return Icons.error_outline_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _getBackgroundColor();
    final icon = _getIcon();

    return Positioned(
      bottom: 60.h,
      left: 24.w,
      right: 24.w,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: 340.w),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: Colors.white,
                      size: 20.sp,
                    ),
                    SizedBox(width: 10.w),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: widget.textColor ?? Colors.white,
                          decoration: TextDecoration.none,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
