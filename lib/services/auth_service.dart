import 'package:flutter/foundation.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  bool get isAuthenticated => _apiClient.isAuthenticated;

  /// Requests a nonce from the server for the given public key
  Future<String> requestNonce(String pubkey) async {
    final response = await _apiClient.post('/auth/nonce', {
      'pubkey': pubkey,
    });
    return response['nonce'] as String;
  }

  /// Verifies the signature with the server and stores the JWT
  Future<bool> verifySignature(String pubkey, String signature, String nonce) async {
    try {
      final response = await _apiClient.post('/auth/verify', {
        'pubkey': pubkey,
        'signature': signature,
        'nonce': nonce,
      });
      
      final token = response['token'] as String?;
      if (token != null) {
        await _apiClient.setToken(token);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AuthService] Verify signature failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _apiClient.setToken(null);
    notifyListeners();
  }
}
