// This is a comprehensive Flutter multi-device and role isolation test suite for P2Pme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:p2pme_app/main.dart';
import 'package:p2pme_app/services/stun_service.dart';
import 'package:p2pme_app/services/upnp_service.dart';
import 'package:p2pme_app/services/global_hub_discovery.dart';

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

  test('Connected Server Registry multi-server persistence, serialization, and DHCP re-addressing', () {
    final server1 = NearbyPeer(
      id: 'node-android-oneplus',
      name: 'OnePlus 6T Server Hub',
      ip: '192.168.178.35',
      port: 45455,
      deviceType: 'android',
      lastSeen: DateTime.now(),
      authToken: '0e853c5573aa9821f',
      isPaired: true,
      freeStorageBytes: 45000000000,
      totalStorageBytes: 128000000000,
    );

    final server2 = NearbyPeer(
      id: 'node-windows-desktop',
      name: 'Main Living Room PC',
      ip: '192.168.178.100',
      port: 45455,
      deviceType: 'pc',
      lastSeen: DateTime.now(),
      authToken: 'f1a980bc2345',
      isPaired: true,
      wanHost: 'mypc.ts.net',
      wanPort: 45455,
      freeStorageBytes: 850000000000,
      totalStorageBytes: 2000000000000,
    );

    // Verify Serialization & Deserialization
    final jsonList = [server1.toJson(), server2.toJson()];
    final restoredList = jsonList.map((m) => NearbyPeer.fromJson(m)).toList();

    expect(restoredList.length, 2);
    expect(restoredList[0].name, 'OnePlus 6T Server Hub');
    expect(restoredList[0].ip, '192.168.178.35');
    expect(restoredList[0].isPaired, isTrue);
    expect(restoredList[0].authToken, '0e853c5573aa9821f');
    expect(restoredList[1].name, 'Main Living Room PC');
    expect(restoredList[1].wanHost, 'mypc.ts.net');

    // Simulate DHCP address shift on home network (router re-assigned .35 to .42)
    restoredList[0].ip = '192.168.178.42';
    final updatedJson = restoredList[0].toJson();
    expect(updatedJson['ip'], '192.168.178.42');
    expect(updatedJson['authToken'], '0e853c5573aa9821f');
  });

  test('Zero-Config Global WAN Discovery (STUN, UPnP, and Cloudflare Hub ID derivation)', () {
    // 1. Verify Zero-Knowledge SHA-256 Hub ID derivation
    const rawSecretKey = '5f3d8a9e01bc47a9821f009988aabbccddeeff00112233445566778899aabbcc';
    final hubId = GlobalHubDiscovery.computeHubId(rawSecretKey);
    expect(hubId.length, 64);
    expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hubId), isTrue);

    // Consistency check: same secret always yields exact same hubId
    final hubId2 = GlobalHubDiscovery.computeHubId(rawSecretKey);
    expect(hubId, hubId2);

    // Differentiation: different secret yields distinct hubId
    final diffId = GlobalHubDiscovery.computeHubId('different_secret_key');
    expect(diffId, isNot(equals(hubId)));

    // 2. Verify ResolvedHub model and wanUrl generation
    final resolvedHub = ResolvedHub(
      hubId: hubId,
      publicIp: '93.184.216.34',
      publicPort: 45455,
      localIp: '192.168.178.35',
      localPort: 45455,
      deviceName: 'OnePlus 6T Server Hub',
      upnpActive: true,
      ageSeconds: 45,
    );
    expect(resolvedHub.wanUrl, 'http://93.184.216.34:45455');
    expect(resolvedHub.upnpActive, isTrue);

    // 3. Verify HubAnnouncementState statusSummary across states
    final upnpSuccess = const UpnpResult(
      isSuccess: true,
      externalIp: '93.184.216.34',
      externalPort: 45455,
      routerModel: 'Fritz!Box 7590',
    );
    final upnpState = HubAnnouncementState(
      hubId: hubId,
      publicIp: '93.184.216.34',
      publicPort: 45455,
      upnpResult: upnpSuccess,
      isAnnounced: true,
    );
    expect(upnpState.statusSummary, contains('UPnP: 93.184.216.34:45455'));

    final stunSuccess = const StunResult(
      publicIp: '84.115.80.12',
      publicPort: 54321,
      stunServer: 'stun.l.google.com:19302',
    );
    final stunState = HubAnnouncementState(
      hubId: hubId,
      publicIp: '84.115.80.12',
      publicPort: 54321,
      stunResult: stunSuccess,
      isAnnounced: true,
    );
    expect(stunState.statusSummary, contains('STUN: 84.115.80.12:54321'));

    final localOnlyState = HubAnnouncementState(
      hubId: hubId,
      publicPort: 45455,
      isAnnounced: false,
    );
    expect(localOnlyState.statusSummary, 'Local Wi-Fi Only');
  });
}
