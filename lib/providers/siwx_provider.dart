import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_provider.dart';

/// Provider for managing the SIWX (Sign In With X) authentication flow
/// 
/// This provider handles the full authentication flow:
/// 1. Gets nonce from backend
/// 2. Signs message with wallet via Reown AppKit
/// 3. Verifies signature with backend
/// 4. Stores JWT token
class SIWXAuthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // Check if already authenticated
    final authService = ref.read(authServiceProvider);
    return authService.isAuthenticated;
  }

  /// Initiates the SIWX authentication flow
  Future<void> authenticate() async {
    state = const AsyncLoading();
    
    try {
      final walletAddress = ref.read(walletAddressProvider);
      if (walletAddress == null) {
        throw Exception('No wallet connected. Please connect your wallet first.');
      }

      final authService = ref.read(authServiceProvider);

      // Step 1: Request nonce from backend
      debugPrint('[SIWX] Requesting nonce for $walletAddress');
      final nonce = await authService.requestNonce(walletAddress);
      debugPrint('[SIWX] Got nonce: $nonce');

      // Step 2: Create SIWX message
      final message = _createSIWXMessage(walletAddress, nonce);
      debugPrint('[SIWX] Message to sign: $message');

      // Step 3: Sign message with wallet
      debugPrint('[SIWX] Requesting signature from wallet...');
      
      // TODO: Implement actual wallet signing once Reown AppKit API is finalized
      // For now, we'll simulate a successful signature for development
      await Future.delayed(const Duration(seconds: 1));
      const signature = 'mock_signature_for_development';

      // Step 4: Verify signature with backend
      debugPrint('[SIWX] Verifying with backend...');
      final success = await authService.verifySignature(
        walletAddress,
        signature,
        nonce,
      );

      if (success) {
        debugPrint('[SIWX] Authentication successful');
        state = const AsyncData(true);
      } else {
        throw Exception('Signature verification failed. Please try again.');
      }
    } on Exception catch (e) {
      debugPrint('[SIWX] Authentication failed: $e');
      state = AsyncError(_getUserFriendlyError(e), StackTrace.current);
    }
  }

  /// Converts technical errors to user-friendly messages
  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString();
    
    // Connection errors
    if (errorString.contains('Connection refused') || 
        errorString.contains('SocketException') ||
        errorString.contains('Cannot connect')) {
      return 'Unable to connect to authentication server. The server may be temporarily unavailable or your internet connection may be unstable.';
    }
    
    // Timeout errors
    if (errorString.contains('timeout')) {
      return 'The server is taking too long to respond. Please try again later.';
    }
    
    // HTTP errors
    if (errorString.contains('404')) {
      return 'Authentication service not found. Please contact support.';
    }
    if (errorString.contains('500') || errorString.contains('502') || errorString.contains('503')) {
      return 'Authentication server is experiencing issues. Please try again later.';
    }
    
    // Wallet errors
    if (errorString.contains('wallet') || errorString.contains('Wallet')) {
      return errorString;
    }
    
    // Signature errors
    if (errorString.contains('signature') || errorString.contains('Signature')) {
      return 'Signature verification failed. Please make sure you\'re using the correct wallet and try again.';
    }
    
    // Default
    return 'Authentication failed: $errorString';
  }

  /// Creates a SIWX-compliant message for signing
  String _createSIWXMessage(String address, String nonce) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '''seeknirvana.app wants you to sign in with your Solana account:
$address

Sign this message to authenticate with SeekNirvana.

Nonce: $nonce
Issued At: $now
''';
  }

  /// Logs out the user
  Future<void> logout() async {
    final authService = ref.read(authServiceProvider);
    await authService.logout();
    state = const AsyncData(false);
  }

  /// Clears any error state
  void clearError() {
    if (state is AsyncError) {
      state = const AsyncData(false);
    }
  }
}

/// Provider for SIWX authentication state
final siwxAuthProvider = AsyncNotifierProvider<SIWXAuthNotifier, bool>(SIWXAuthNotifier.new);

/// Provider to check if SIWX authentication is in progress
final isAuthenticatingProvider = Provider<bool>((ref) {
  return ref.watch(siwxAuthProvider).isLoading;
});

/// Provider for SIWX authentication error
final siwxAuthErrorProvider = Provider<String?>((ref) {
  final state = ref.watch(siwxAuthProvider);
  return state.error?.toString();
});
