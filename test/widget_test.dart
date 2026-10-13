// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:theja_aura/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AuraApp dashboard smoke test', (WidgetTester tester) async {
    const MethodChannel controlChannel =
        MethodChannel('com.thejatech.aura/tunnel_control');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
      if (call.method == 'getStatus') return 'disconnected';
      if (call.method == 'getRules') return <dynamic>[];
      if (call.method == 'syncRules') return true;
      return null;
    });

    await tester.pumpWidget(const AuraApp());
    await tester.pumpAndSettle();

    expect(find.text("Theja's Aura"), findsOneWidget);
    expect(find.text('Protection Disabled'), findsOneWidget);
    expect(find.text('Enable Firewall'), findsOneWidget);
  });
}
