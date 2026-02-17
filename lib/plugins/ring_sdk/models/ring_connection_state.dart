enum RingConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  bound,
  disconnecting;

  static RingConnectionState fromString(String value) {
    return RingConnectionState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RingConnectionState.disconnected,
    );
  }

  bool get isConnected => this == connected || this == bound;
  bool get isActive => this == scanning || this == connecting || this == disconnecting;

  String get label {
    switch (this) {
      case disconnected:
        return 'Disconnected';
      case scanning:
        return 'Scanning…';
      case connecting:
        return 'Connecting…';
      case connected:
        return 'Connected';
      case bound:
        return 'Bound';
      case disconnecting:
        return 'Disconnecting…';
    }
  }
}
