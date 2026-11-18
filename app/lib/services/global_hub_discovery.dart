import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'stun_service.dart';
import 'upnp_service.dart';

class ResolvedHub {
  final String hubId;
  final String publicIp;
  final int publicPort;
  final String? localIp;
  final int? localPort;
  final String deviceName;
  final bool upnpActive;
  final int ageSeconds;

  const ResolvedHub({
    required this.hubId,
    required this.publicIp,
    required this.publicPort,
    this.localIp,
    this.localPort,
    required this.deviceName,
    required this.upnpActive,
    required this.ageSeconds,
  });

  String get wanUrl => 'http://$publicIp:$publicPort';

  @override
  String toString() => '$deviceName ($publicIp:$publicPort, age: ${ageSeconds}s)';
}

class HubAnnouncementState {
  final String hubId;
  final String? publicIp;
  final int publicPort;
  final UpnpResult? upnpResult;
  final StunResult? stunResult;
  final bool isAnnounced;
  final DateTime? lastAnnouncedAt;
  final String? error;

  const HubAnnouncementState({
    required this.hubId,
    this.publicIp,
    required this.publicPort,
    this.upnpResult,
    this.stunResult,
    required this.isAnnounced,
    this.lastAnnouncedAt,
    this.error,
  });

  bool get isUpnpActive => upnpResult?.isSuccess == true;
  String get statusSummary {
    if (isAnnounced && isUpnpActive && publicIp != null) {
      return 'Global WAN Active (UPnP: $publicIp:$publicPort)';
    } else if (isAnnounced && publicIp != null) {
      return 'Global WAN Active (STUN: $publicIp:$publicPort)';
    } else if (isAnnounced) {
      return 'Global WAN Announcing...';
    } else {
      return 'Local Wi-Fi Only';
    }
  }
}

/// Zero-Knowledge Global Hub Discovery and Tracker Coordinator
class GlobalHubDiscovery {
  static const String defaultTrackerBase = 'https://p2pme.pages.dev';
  static Timer? _keepAliveTimer;
  static HubAnnouncementState? _lastState;

  static HubAnnouncementState? get lastState => _lastState;

  /// Derive 256-bit SHA-256 identifier from secret key (zero secret leakage)
  static String computeHubId(String secretKey) {
    final clean = secretKey.trim();
    return sha256.convert(utf8.encode(clean)).toString();
  }

  /// Start 24/7 Server Hub Global WAN announcement with automatic UPnP & STUN
  static Future<HubAnnouncementState> startAnnouncement({
    required String secretKey,
    required String localIp,
    required int port,
    required String deviceName,
    String trackerBase = defaultTrackerBase,
  }) async {
    final hubId = computeHubId(secretKey);

    // 1. Run UPnP Port Mapping and Google STUN in parallel
    final upnpFuture = UpnpService.mapPort(port: port, localIp: localIp);
    final stunFuture = StunService.discoverPublicEndpoint();

    final results = await Future.wait([upnpFuture, stunFuture]);
    final upnpRes = results[0] as UpnpResult;
    final stunRes = results[1] as StunResult?;

    final publicIp = upnpRes.externalIp ?? stunRes?.publicIp;
    final publicPort = upnpRes.isSuccess ? upnpRes.externalPort : (stunRes?.publicPort ?? port);

    // 2. Announce to Cloudflare Pages edge tracker
    final announced = await _postAnnouncement(
      trackerBase: trackerBase,
      hubId: hubId,
      publicIp: publicIp,
      publicPort: publicPort,
      localIp: localIp,
      localPort: port,
      deviceName: deviceName,
      upnpActive: upnpRes.isSuccess,
    );

    _lastState = HubAnnouncementState(
      hubId: hubId,
      publicIp: publicIp,
      publicPort: publicPort,
      upnpResult: upnpRes,
      stunResult: stunRes,
      isAnnounced: announced,
      lastAnnouncedAt: announced ? DateTime.now() : null,
      error: announced ? null : 'Failed to reach Cloudflare edge tracker.',
    );

    // 3. Start keep-alive loop (re-announce every 5 minutes to refresh 15m TTL)
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _postAnnouncement(
        trackerBase: trackerBase,
        hubId: hubId,
        publicIp: _lastState?.publicIp,
        publicPort: _lastState?.publicPort ?? port,
        localIp: localIp,
        localPort: port,
        deviceName: deviceName,
        upnpActive: _lastState?.isUpnpActive ?? false,
      );
    });

    return _lastState!;
  }

  /// Stop announcement and clean up router port mapping
  static Future<void> stopAnnouncement({int port = 45455}) async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    final controlUrl = _lastState?.upnpResult?.controlUrl;
    final serviceType = _lastState?.upnpResult?.serviceType;
    if (controlUrl != null && serviceType != null) {
      await UpnpService.unmapPort(
        port: port,
        controlUrl: controlUrl,
        serviceType: serviceType,
      );
    }
    _lastState = null;
  }

  /// Sender queries Cloudflare tracker to resolve a paired server by its token
  static Future<ResolvedHub?> resolveHub({
    required String secretKeyOrToken,
    String trackerBase = defaultTrackerBase,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final hubId = computeHubId(secretKeyOrToken);
      final client = HttpClient()..connectionTimeout = timeout;
      final uri = Uri.parse('$trackerBase/api/hub/resolve?hub_id=$hubId');
      final req = await client.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(resp).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['status'] == 'active') {
          return ResolvedHub(
            hubId: json['hub_id'] as String,
            publicIp: json['public_ip'] as String,
            publicPort: (json['public_port'] as num).toInt(),
            localIp: json['local_ip'] as String?,
            localPort: (json['local_port'] as num?)?.toInt(),
            deviceName: (json['device_name'] as String?) ?? 'Server Hub',
            upnpActive: json['upnp_active'] == true,
            ageSeconds: (json['age_seconds'] as num?)?.toInt() ?? 0,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _postAnnouncement({
    required String trackerBase,
    required String hubId,
    required String? publicIp,
    required int publicPort,
    required String localIp,
    required int localPort,
    required String deviceName,
    required bool upnpActive,
  }) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final uri = Uri.parse('$trackerBase/api/hub/announce');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');

      final payload = jsonEncode({
        'hub_id': hubId,
        'public_ip': publicIp ?? '',
        'public_port': publicPort,
        'local_ip': localIp,
        'local_port': localPort,
        'device_name': deviceName,
        'upnp_active': upnpActive,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      req.write(payload);
      final resp = await req.close();
      return resp.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }
}
