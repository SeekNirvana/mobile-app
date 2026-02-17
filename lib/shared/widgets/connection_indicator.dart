import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';

class ConnectionIndicator extends StatefulWidget {
  final RingConnectionState state;
  final VoidCallback? onTap;

  const ConnectionIndicator({
    super.key,
    required this.state,
    this.onTap,
  });

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.state.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(ConnectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.isActive) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _dotColor {
    switch (widget.state) {
      case RingConnectionState.connected:
      case RingConnectionState.bound:
        return AppColors.connected;
      case RingConnectionState.scanning:
      case RingConnectionState.connecting:
        return AppColors.connecting;
      default:
        return AppColors.disconnected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _dotColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _dotColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor.withValues(
                      alpha: widget.state.isActive
                          ? 0.5 + 0.5 * _controller.value
                          : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _dotColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            Text(
              widget.state.label,
              style: TextStyle(
                color: _dotColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
