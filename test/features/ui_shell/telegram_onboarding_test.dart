import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloudbeat/features/ui_shell/telegram_onboarding_screen.dart';

void main() {
  testWidgets('TelegramOnboardingScreen renders properly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TelegramOnboardingScreen(),
        ),
      ),
    );

    expect(find.text('Connect to CloudBeat'), findsOneWidget);
    expect(find.byType(Stepper), findsOneWidget);
  });
}
