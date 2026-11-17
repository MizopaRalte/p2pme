// This is a basic Flutter widget test for P2Pme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:p2pme_app/main.dart';

void main() {
  testWidgets('Role Selection flow smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const P2PmeApp());
    await tester.pumpAndSettle();

    // 1. Verify Role Selection Screen is shown on startup
    expect(find.text('What is this device doing?'), findsOneWidget);
    expect(find.text('Sender  (Back Up & Beam)'), findsOneWidget);
    expect(find.text('Receiver  (Quick Receive)'), findsOneWidget);
    expect(find.text('Server  (24/7 Dedicated Hub)'), findsOneWidget);

    // 2. Tap on Sender
    await tester.tap(find.text('Sender  (Back Up & Beam)'));
    await tester.pumpAndSettle();

    // Verify Sender mode is active and role switcher badge exists
    expect(find.text('Sender'), findsWidgets);
    expect(find.text('Backup'), findsWidgets);

    // 3. Tap role switcher to return to selection screen
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('What is this device doing?'), findsOneWidget);

    // 4. Tap on Server
    await tester.tap(find.text('Server  (24/7 Dedicated Hub)'));
    await tester.pumpAndSettle();
    expect(find.text('Server'), findsWidgets);
    expect(find.text('24/7 Backup Server'), findsOneWidget);

    // Dispose app to cleanly cancel periodic background timers
    await tester.pumpWidget(const SizedBox());
  });
}
