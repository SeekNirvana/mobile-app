import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reown_appkit/reown_appkit.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/siwx_provider.dart';
import '../../services/reown_service.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isReownInitializing = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initReownService();
    });
  }
  
  Future<void> _initReownService() async {
    final reownService = ref.read(reownServiceProvider);
    if (!reownService.isInitialized) {
      setState(() => _isReownInitializing = true);
      try {
        await reownService.init(context);
      } catch (e) {
        debugPrint('Failed to initialize ReownService: $e');
      } finally {
        if (mounted) {
          setState(() => _isReownInitializing = false);
        }
      }
    } else {
      setState(() => _isReownInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletAddress = ref.watch(walletAddressProvider);
    final isAuth = ref.watch(isAuthenticatedProvider);
    final nirvBalance = ref.watch(nirvTokenBalanceProvider);
    final solBalance = ref.watch(solBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solana Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (walletAddress != null)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => _showDisconnectDialog(context),
              tooltip: 'Disconnect Wallet',
            ),
        ],
      ),
      body: walletAddress == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 80,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Wallet Connected',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Connect a Solana wallet to earn \$NIRV.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  if (_isReownInitializing)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    _buildWalletConnectButton(),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildAddressCard(isDark, walletAddress, isAuth),
                const SizedBox(height: 24),
                if (!isAuth)
                  _buildAuthCard(isDark),
                if (!isAuth) const SizedBox(height: 24),
                _buildBalanceCard(
                  isDark: isDark,
                  title: '\$NIRV Balance',
                  amount: nirvBalance > 0 ? nirvBalance.toStringAsFixed(2) : '0.00',
                  icon: Icons.stars_rounded,
                  color: AppColors.gold,
                ),
                const SizedBox(height: 16),
                _buildBalanceCard(
                  isDark: isDark,
                  title: 'SOL Balance',
                  amount: solBalance > 0 ? solBalance.toStringAsFixed(4) : '0.00',
                  icon: Icons.currency_exchange_rounded,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 32),
                if (_isReownInitializing)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  _buildWalletConnectButton(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: () => _showDisconnectDialog(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Disconnect Wallet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _showDisconnectDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Wallet?'),
        content: const Text(
          'This will disconnect your wallet and sign you out. You\'ll need to reconnect to claim rewards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(siwxAuthProvider.notifier).logout();
      await ref.read(reownServiceProvider).disconnect();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet disconnected')),
        );
      }
    }
  }

  Widget _buildWalletConnectButton() {
    final appKitModal = ref.watch(reownServiceProvider).appKitModal;
    if (appKitModal == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Wallet connection unavailable. Please restart the app.'),
        ),
      );
    }
    return AppKitModalConnectButton(appKit: appKitModal);
  }

  Widget _buildAuthCard(bool isDark) {
    final siwxState = ref.watch(siwxAuthProvider);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Authentication Required',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to claim your \$NIRV tokens and mint achievement NFTs.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: siwxState.isLoading
                  ? null
                  : () async {
                      ref.read(siwxAuthProvider.notifier).clearError();
                      await ref.read(siwxAuthProvider.notifier).authenticate();
                    },
              icon: siwxState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(siwxState.isLoading ? 'Signing In...' : 'Sign In with Wallet'),
            ),
          ),
          if (siwxState.hasError) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Error',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    siwxState.error?.toString() ?? 'Unknown error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade300,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => ref.read(siwxAuthProvider.notifier).clearError(),
                      child: const Text('Dismiss'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressCard(bool isDark, String address, bool isAuth) {
    final shortAddress = '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Connected Address',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAuth 
                          ? AppColors.green.withValues(alpha: 0.2)
                          : AppColors.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAuth ? Icons.check_circle_rounded : Icons.wallet_rounded,
                          size: 12,
                          color: isAuth ? AppColors.green : AppColors.gold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAuth ? 'Authenticated' : 'Connected',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: isAuth ? AppColors.green : AppColors.gold,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  shortAddress,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard({
    required bool isDark,
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
