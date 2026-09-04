import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class TelegramOnboardingScreen extends ConsumerStatefulWidget {
  const TelegramOnboardingScreen({super.key});

  @override
  ConsumerState<TelegramOnboardingScreen> createState() => _TelegramOnboardingScreenState();
}

class _TelegramOnboardingScreenState extends ConsumerState<TelegramOnboardingScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  int _currentStep = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultContractProvider);

    // Watch auth state changes to progress steps automatically
    ref.listen<VaultAuthState>(
      vaultContractProvider.select((v) => v.currentAuthState),
      (previous, next) {
        if (next == VaultAuthState.waitCode && _currentStep == 0) {
          setState(() => _currentStep = 1);
        } else if (next == VaultAuthState.waitPassword && _currentStep == 1) {
          setState(() => _currentStep = 2);
        } else if (next == VaultAuthState.authenticated) {
          setState(() => _currentStep = 3);
          // main.dart StreamBuilder will automatically swap to MainNavigationShell
        }
      },
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 40.0, bottom: 20.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_done_rounded, size: 64, color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text(
                      'Connect to CloudBeat',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Unlimited Lossless Storage via Telegram',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primary,
                    onPrimary: Colors.black,
                  ),
                  canvasColor: AppTheme.background,
                ),
                child: Stepper(
                  currentStep: _currentStep,
                  type: StepperType.vertical,
                  onStepTapped: (step) {
                    if (step < _currentStep) {
                      setState(() => _currentStep = step);
                    }
                  },
                  controlsBuilder: (context, details) {
                    return const SizedBox.shrink(); // Hide default controls
                  },
                  steps: [
                    Step(
                      title: const Text('Phone Number', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter your Telegram phone number', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: '+1 234 567 8900',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_phoneController.text.trim().isNotEmpty) {
                                vault.sendPhoneNumber(_phoneController.text.trim());
                              }
                            },
                            child: const Text('Send Verification Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Verification Code', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter the code sent to your Telegram app', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: '12345',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_codeController.text.trim().isNotEmpty) {
                                vault.sendAuthCode(_codeController.text.trim());
                              }
                            },
                            child: const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Two-Step Verification', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter your cloud password (if enabled)', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 2,
                      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_passwordController.text.isNotEmpty) {
                                vault.sendPassword(_passwordController.text);
                              }
                            },
                            child: const Text('Submit Password', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Vault Ready', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Successfully connected', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 3,
                      state: _currentStep >= 3 ? StepState.complete : StepState.indexed,
                      content: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppTheme.secondary, size: 48),
                              SizedBox(height: 16),
                              Text(
                                'CloudBeat Vault Created',
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Taking you to your dashboard...',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
