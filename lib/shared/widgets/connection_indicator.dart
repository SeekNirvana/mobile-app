import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';

class ConnectionIndicator extends StatefulWidget {
  final RingConnectionState state;
  final VoidCallback? onTap;

  const ConnectionIndicator({super.key, required this.state, this.onTap});

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

  IconData get _icon {
    switch (widget.state) {
      case RingConnectionState.connected:
      case RingConnectionState.bound:
        return Icons.bluetooth_connected_rounded;
      case RingConnectionState.scanning:
        return Icons.bluetooth_searching_rounded;
      case RingConnectionState.connecting:
        return Icons.sync_rounded;
      default:
        return Icons.bluetooth_disabled_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.state.label,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _dotColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _dotColor.withValues(alpha: 0.28)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(_icon, color: _dotColor, size: 20),
              Positioned(
                right: 9,
                top: 9,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor.withValues(
                          alpha: widget.state.isActive
                              ? 0.55 + 0.45 * _controller.value
                              : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _dotColor.withValues(alpha: 0.38),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
