import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import '../../core/session/zarz_session_manager.dart';

/// In-App Modal WebView bottom sheet for Cloudflare Turnstile verification.
/// Intercepts `cloudbeat://session-grant` and exchanges token seamlessly without app switching.
class ZarzTurnstileSheet extends ConsumerStatefulWidget {
  const ZarzTurnstileSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ZarzTurnstileSheet(),
    );
  }

  @override
  ConsumerState<ZarzTurnstileSheet> createState() => _ZarzTurnstileSheetState();
}

class _ZarzTurnstileSheetState extends ConsumerState<ZarzTurnstileSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[ZarzTurnstileSheet.initState]');
    _initializeChallenge();
  }

  Future<void> _initializeChallenge() async {
    final zarz = ref.read(zarzSessionManagerProvider);
    try {
      final challenge = await zarz.bootstrap();
      if (!mounted) return;

      final cbUrl = '${ZarzSessionManager.callbackScheme}://${ZarzSessionManager.callbackHost}?state=${Uri.encodeComponent(challenge.serverNonce)}';
      final challengeUri = Uri.parse('${zarz.baseUrl}/v2/challenge').replace(queryParameters: {
        'id': challenge.challengeId,
        'cb': cbUrl,
      });

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF121212))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              AppLogger.trace('[ZarzTurnstileSheet.onPageStarted]', 'url: $url');
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (url) {
              AppLogger.trace('[ZarzTurnstileSheet.onPageFinished]', 'url: $url');
              if (mounted) setState(() => _isLoading = false);
            },
            onWebResourceError: (error) {
              AppLogger.trace('[ZarzTurnstileSheet.error]', 'desc: ${error.description}');
            },
            onNavigationRequest: (request) async {
              AppLogger.trace('[ZarzTurnstileSheet.navRequest]', 'url: ${request.url}');
              final uriStr = request.url;
              if (uriStr.startsWith('cloudbeat://') ||
                  uriStr.startsWith('spotiflac://') ||
                  uriStr.contains('session-grant')) {
                final parsed = zarz.parseCallback(uriStr);
                if (parsed != null && parsed.grant.isNotEmpty) {
                  try {
                    await zarz.completeGrant(
                      grantToken: parsed.grant,
                      challengeId: challenge.challengeId,
                      state: parsed.state,
                    );
                    if (mounted) {
                      Navigator.pop(context, true);
                    }
                  } catch (e, st) {
                    AppLogger.e('ZarzTurnstileSheet', 'grant exchange failed', e, st);
                    if (mounted) {
                      setState(() => _errorMessage = 'Exchange error: $e');
                    }
                  }
                }
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(challengeUri);

      if (mounted) {
        setState(() {
          _webViewController = controller;
        });
      }
    } catch (e, st) {
      AppLogger.e('ZarzTurnstileSheet', 'bootstrap error', e, st);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load Turnstile challenge: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.85,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Drag handle & Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
              ),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            color: colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hi-Res Verification',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Solve Turnstile to unlock 24-bit FLAC streams',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: colorScheme.onSurfaceVariant,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Loading Progress Bar
          if (_isLoading)
            LinearProgressIndicator(
              backgroundColor: colorScheme.surfaceContainer,
              color: colorScheme.primary,
              minHeight: 3,
            ),

          // Main WebView or Error
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = null;
                              });
                              _initializeChallenge();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : _webViewController != null
                    ? WebViewWidget(controller: _webViewController!)
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
          ),
        ],
      ),
    );
  }
}
