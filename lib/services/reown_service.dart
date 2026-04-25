import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../providers/wallet_provider.dart';

class ReownService {
  final Ref ref;
  ReownAppKitModal? _appKitModal;
  bool _isInitialized = false;
  
  ReownAppKitModal? get appKitModal => _appKitModal;
  bool get isInitialized => _isInitialized;

  ReownService(this.ref);

  Future<void> init(BuildContext context) async {
    if (_isInitialized) return;
    
    // Try --dart-define first (production builds), fallback to .env file (development)
    const dartDefineProjectId = String.fromEnvironment('PROJECT_ID', defaultValue: '');
    final envProjectId = dotenv.env['PROJECT_ID'] ?? '';
    final projectId = dartDefineProjectId.isNotEmpty ? dartDefineProjectId : envProjectId;
    
    if (projectId.isEmpty) {
      debugPrint('[ReownService] Warning: PROJECT_ID is empty!');
      debugPrint('[ReownService] Please set PROJECT_ID via --dart-define or in .env file');
      debugPrint('[ReownService] Get your Project ID from https://cloud.reown.com/');
    } else {
      debugPrint('[ReownService] Project ID configured successfully');
    }

    _appKitModal = ReownAppKitModal(
      context: context,
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'SeekNirvana',
        description: 'Experience the intersection of ancient wisdom and cutting-edge technology',
        url: 'https://seeknirvana.app',
        icons: ['https://seeknirvana.com/SeekNirvana-logo.png'],
        redirect: Redirect(
          native: 'seeknirvana://',
          universal: 'https://seeknirvana.com',
        ),
      ),
      // Enable wallet, email, and social logins
      featuresConfig: FeaturesConfig(
        socials: const [
          AppKitSocialOption.Email,  // Email-based login
          AppKitSocialOption.Google, // Gmail/Google login
        ],
      ),
    );

    await _appKitModal!.init();

    _appKitModal!.addListener(_onAppKitStateChange);
    _onAppKitStateChange();
    
    _isInitialized = true;
  }

  void _onAppKitStateChange() {
    if (_appKitModal == null) return;
    final session = _appKitModal!.session;
    if (session != null) {
      // Assuming session.address holds the public key for Solana connection
      final address = session.getAddress('solana');
      ref.read(walletAddressProvider.notifier).update(address);
    } else {
      ref.read(walletAddressProvider.notifier).update(null);
    }
  }

  Future<void> disconnect() async {
    if (_appKitModal == null) return;
    await _appKitModal!.disconnect();
    ref.read(walletAddressProvider.notifier).update(null);
  }
}

final reownServiceProvider = Provider<ReownService>((ref) {
  return ReownService(ref);
});
