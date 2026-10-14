// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:theja_aura/main.dart';
import 'package:theja_aura/core/DI/injection.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (!getIt.isRegistered<DashboardBloc>()) {
      await configureDependencies();
    }
  });

  testWidgets('AuraApp dashboard smoke test', (WidgetTester tester) async {
    const MethodChannel controlChannel = MethodChannel(
      'com.thejatech.aura/tunnel_control',
    );
    const MethodChannel activityChannel = MethodChannel(
      'com.thejatech.aura/activity',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
          if (call.method == 'getStatus') return 'disconnected';
          if (call.method == 'getRules') return <dynamic>[];
          if (call.method == 'syncRules') return true;
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
          if (call.method == 'getDashboardStats') {
            return <String, dynamic>{
              'timeWindowMillis': 86400000,
              'startTime': 0,
              'endTime': 86400000,
              'totalQueries': 100,
              'totalBlocked': 25,
              'totalAllowed': 75,
              'totalFailed': 0,
              'uniqueBlockedDomains': 10,
              'uniqueDomainsTotal': 30,
            };
          }
          if (call.method == 'getTopBlockedDomains') {
            return <dynamic>[
              <String, dynamic>{'domain': 'ads.example.com', 'count': 25},
            ];
          }
          return null;
        });

    await tester.pumpWidget(const AuraApp());
    await tester.pumpAndSettle();

    expect(find.text("Theja's Aura"), findsOneWidget);
    expect(find.text('Protection Disabled'), findsOneWidget);
    expect(find.text('Enable Firewall'), findsOneWidget);
  });
}
