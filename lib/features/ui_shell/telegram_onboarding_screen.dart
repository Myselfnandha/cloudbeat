import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class TelegramOnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCompleted;

  const TelegramOnboardingScreen({super.key, this.onCompleted});

  @override
  ConsumerState<TelegramOnboardingScreen> createState() => _TelegramOnboardingScreenState();
}

class _TelegramOnboardingScreenState extends ConsumerState<TelegramOnboardingScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = 'Enter phone in international format (e.g. +14155552671)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendPhoneNumber(phone);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to request Telegram auth code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter the verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendAuthCode(code);
    } catch (e) {
      setState(() => _errorMessage = 'Invalid code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your cloud 2FA password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendPassword(password);
    } catch (e) {
      setState(() => _errorMessage = 'Incorrect 2FA password: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultContractProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: StreamBuilder<VaultAuthState>(
          stream: vault.authStateStream,
          initialData: vault.currentAuthState,
          builder: (context, snapshot) {
            final authState = snapshot.data ?? VaultAuthState.unauthenticated;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // CloudBeat App Icon Badge
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accentGradientEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.cloud_sync_rounded, color: Colors.black, size: 44),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'CloudBeat Vault',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Unlimited Bit-Perfect FLAC Streaming via Telegram MTProto',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Step Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _buildStepContent(authState),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStepContent(VaultAuthState state) {
    if (state == VaultAuthState.authenticated) {
      return _buildSuccessStep();
    } else if (state == VaultAuthState.waitPassword) {
      return _buildPasswordStep();
    } else if (state == VaultAuthState.waitCode) {
      return _buildCodeStep();
    } else {
      return _buildPhoneStep();
    }
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP 1 OF 3',
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Connect Your Telegram Account',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your audio vault files are encrypted and stored in your private Telegram cloud storage.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: 'Phone Number',
            labelStyle: const TextStyle(color: AppTheme.textMuted),
            hintText: '+14155552671',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            prefixIcon: const Icon(Icons.phone_rounded, color: AppTheme.primary),
            filled: true,
            fillColor: AppTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitPhone,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : const Text(
                    'Send Verification Code',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP 2 OF 3',
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter Verification Code',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'We sent a 5-digit code to your Telegram app for ${_phoneController.text}.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '•••••',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            filled: true,
            fillColor: AppTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : const Text(
                    'Verify Code',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP 3 OF 3',
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Two-Factor Authentication',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your Telegram account is protected by cloud 2FA password.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _passwordController,
          obscureText: true,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: '2FA Password',
            labelStyle: const TextStyle(color: AppTheme.textMuted),
            prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primary),
            filled: true,
            fillColor: AppTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : const Text(
                    'Unlock Vault',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      children: [
        const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 56),
        const SizedBox(height: 12),
        const Text(
          'Telegram Vault Connected!',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your private Supergroup and decade forum topics have been configured. You are ready to stream and store bit-perfect FLAC audio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: widget.onCompleted,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text(
              'Enter CloudBeat Vault',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
