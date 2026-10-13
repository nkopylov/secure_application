import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_application/secure_application.dart';

// The usual setup: SecureApplication -> secure() -> SecureGate.
Widget app() => SecureApplication(
      nativeRemoveDelay: 100,
      onNeedUnlock: (secure) async {
        secure?.unlock();
        return SecureApplicationAuthenticationStatus.SUCCESS;
      },
      child: Builder(builder: (context) {
        SecureApplicationProvider.of(context)?.secure();
        return const Directionality(
          textDirection: TextDirection.ltr,
          child: SecureGate(child: Text('app')),
        );
      }),
    );

Future<void> toBackground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> toForeground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

/// How much of the gate shows: 1 is the full blur, 0 none.
double gateStrength(WidgetTester tester) {
  final filters = find.byType(BackdropFilter);
  if (filters.evaluate().isEmpty) return 0;
  final cover = find.descendant(of: filters, matching: find.byType(Container));
  final color =
      (tester.widget<Container>(cover).decoration as BoxDecoration).color!;
  // .opacity, not .a: the package still supports Flutter versions without .a
  // ignore: deprecated_member_use
  return color.opacity / 0.6; // SecureGate's default opacity
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('secure_application'), (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('secure_application'), null);
  });

  testWidgets(
      'going to the background again while the gate fades out does not throw '
      'TickerCanceled, and the gate shows in full again', (tester) async {
    await tester.pumpWidget(app());
    await toBackground(tester);
    await toForeground(tester);
    // the unlock fades the gate out (400 ms); go back before it ends
    await tester.pump(const Duration(milliseconds: 100));
    expect(gateStrength(tester), inExclusiveRange(0, 1));

    await toBackground(tester);
    // No frames are drawn while paused: check the first frame after the
    // return. The gate locked again, so the new fade starts from full.
    await toForeground(tester);
    expect(gateStrength(tester), 1);

    // An unhandled TickerCanceled from the dropped fade future fails the test.
    await tester.pump(const Duration(seconds: 1));
    expect(gateStrength(tester), 0);
  });

  testWidgets('control: going to the background after the fade has ended',
      (tester) async {
    await tester.pumpWidget(app());
    await toBackground(tester);
    await toForeground(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(gateStrength(tester), 0);

    await toBackground(tester);
    await toForeground(tester);
    expect(gateStrength(tester), 1);
    await tester.pump(const Duration(seconds: 1));
    expect(gateStrength(tester), 0);
  });
}
