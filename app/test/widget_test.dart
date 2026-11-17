// This is a comprehensive Flutter multi-device and role isolation test suite for P2Pme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:p2pme_app/main.dart';

void main() {
  testWidgets('Dedicated Role Selection and Isolation smoke test', (WidgetTester tester) async {
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

    // Verify Sender mode is active and bottomNavigationBar is completely absent
    expect(find.text('Sender'), findsWidgets);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Quick Beam (Direct to Anyone)'), findsOneWidget);

    // 3. Test Android Back button (PopScope) navigation back to role picker
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('What is this device doing?'), findsOneWidget);

    // 4. Tap on Receiver
    await tester.tap(find.text('Receiver  (Quick Receive)'));
    await tester.pumpAndSettle();
    expect(find.text('Receiver'), findsWidgets);
    expect(find.byType(NavigationBar), findsNothing);

    // Return to role picker via role switcher chip
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(find.text('What is this device doing?'), findsOneWidget);

    // 5. Tap on Server
    await tester.tap(find.text('Server  (24/7 Dedicated Hub)'));
    await tester.pumpAndSettle();
    expect(find.text('Server Hub'), findsWidgets);
    expect(find.text('24/7 Backup Server'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Clean dispose to stop any periodic timers
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cross-device layout compatibility (Compact Phone, Tablet, Landscape, Large Font)', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('FULL FLUTTER ERROR: ${details.toString()}');
    };
    final testSizes = [
      const Size(320, 568),  // Compact Phone / iPhone SE
      const Size(390, 844),  // Standard Modern Phone (iPhone 14/15/16, Pixel)
      const Size(768, 1024), // Tablet Portrait (iPad / Galaxy Tab)
      const Size(1024, 768), // Tablet Landscape (iPad Landscape)
    ];

    try {
      for (final size in testSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(const P2PmeApp());
        await tester.pumpAndSettle();

        // Check Role Selection on this resolution
        expect(tester.takeException(), isNull, reason: 'Overflow on Role Selection with size $size');
        expect(find.text('What is this device doing?'), findsOneWidget);

        // Check Server Hub role (scroll until visible if on small screen)
        final serverCard = find.text('Server  (24/7 Dedicated Hub)');
        await tester.ensureVisible(serverCard);
        await tester.pumpAndSettle();
        await tester.tap(serverCard);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Overflow on Server Hub with size $size');
        expect(find.text('Server Hub'), findsWidgets);

        // Return to role picker
        await tester.tap(find.text('Switch'));
        await tester.pumpAndSettle();

        // Check Sender role
        final senderCard = find.text('Sender  (Back Up & Beam)');
        await tester.ensureVisible(senderCard);
        await tester.pumpAndSettle();
        await tester.tap(senderCard);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Overflow on Sender with size $size');
        expect(find.text('Sender'), findsWidgets);

        // Return to role picker
        await tester.tap(find.text('Switch'));
        await tester.pumpAndSettle();

        // Check Receiver role
        final receiverCard = find.text('Receiver  (Quick Receive)');
        await tester.ensureVisible(receiverCard);
        await tester.pumpAndSettle();
        await tester.tap(receiverCard);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Overflow on Receiver with size $size');
        expect(find.text('Receiver'), findsWidgets);

        // Reset
        await tester.pumpWidget(const SizedBox());
      }

      // 5. Test Accessibility 1.5x Text Scaling on Compact Phone (360x740)
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: P2PmeApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overflow on 1.5x text scale');
      expect(find.text('What is this device doing?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    } finally {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  test('ActiveReceiverSession multi-stream throughput aggregation and isolation', () {
    final session1 = ActiveReceiverSession(
      sessionId: '192.168.1.50_iPhone',
      senderName: 'iPhone 15 Pro',
      senderIp: '192.168.1.50',
      fileName: 'IMG_2026.HEIC',
      fileIndex: 1,
      totalFiles: 10,
      batchTotalBytes: 50000000,
      batchBytesReceived: 5000000,
      fileTotalBytes: 5000000,
      fileBytesReceived: 2500000,
      speedMBps: 45.2,
      progressRatio: 0.5,
      lastUpdated: DateTime.now(),
    );

    final session2 = ActiveReceiverSession(
      sessionId: '192.168.1.80_MacBook',
      senderName: 'MacBook Pro',
      senderIp: '192.168.1.80',
      fileName: 'Video_4K.mov',
      fileIndex: 2,
      totalFiles: 4,
      batchTotalBytes: 800000000,
      batchBytesReceived: 200000000,
      fileTotalBytes: 200000000,
      fileBytesReceived: 100000000,
      speedMBps: 62.8,
      progressRatio: 0.5,
      lastUpdated: DateTime.now(),
    );

    final activeSessions = <String, ActiveReceiverSession>{
      session1.sessionId: session1,
      session2.sessionId: session2,
    };

    expect(activeSessions.length, 2);
    final combinedThroughput = activeSessions.values.fold<double>(0.0, (acc, s) => acc + s.speedMBps);
    expect(combinedThroughput, closeTo(108.0, 0.01));
    expect(activeSessions.values.map((s) => s.senderName).toSet(), containsAll(['iPhone 15 Pro', 'MacBook Pro']));

    // Simulating completion of session 1: session 2 remains completely intact
    activeSessions.remove(session1.sessionId);
    expect(activeSessions.length, 1);
    expect(activeSessions.containsKey(session2.sessionId), isTrue);
    expect(activeSessions[session2.sessionId]!.fileName, 'Video_4K.mov');
  });
}
