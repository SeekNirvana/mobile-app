import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

// --- API Client ---
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  client.init();
  return client;
});

// --- Auth Service ---
final authServiceProvider = Provider<AuthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthService(apiClient);
});

// --- Wallet State ---
class WalletAddressNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? address) => state = address;
}
final walletAddressProvider = NotifierProvider<WalletAddressNotifier, String?>(WalletAddressNotifier.new);

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.isAuthenticated;
});

// Placeholder for Token balances (would fetch via Reown / RPC)
class DoubleNotifier extends Notifier<double> {
  @override
  double build() => 0.0;
  void update(double value) => state = value;
}
final solBalanceProvider = NotifierProvider<DoubleNotifier, double>(DoubleNotifier.new);
final nirvTokenBalanceProvider = NotifierProvider<DoubleNotifier, double>(DoubleNotifier.new);
