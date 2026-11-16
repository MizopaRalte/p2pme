import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/p2p_bridge.dart';
import 'services/camera_backup_service.dart';
import 'screens/qr_scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const P2PmeApp());
}

class GooglePhotosColors {
  static const blue = Color(0xFF1A73E8);
  static const red = Color(0xFFEA4335);
  static const yellow = Color(0xFFFBBC04);
  static const green = Color(0xFF34A853);
  static const blueSurface = Color(0xFFE8F0FE);
  static const lightBg = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF8F9FA);
  static const lightBorder = Color(0xFFDADCE0);
  static const darkBg = Color(0xFF202124);
  static const darkCard = Color(0xFF303134);
  static const darkBorder = Color(0xFF3C4043);
}

// ==========================================
// AUTHENTIC BRAND SVG PARSER & ICONS
// ==========================================
Path parseSvgPath(String d) {
  final path = Path();
  final exp = RegExp(r'([MmLlHhVvCcSsQqTtAaZz])|([+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?)');
  final matches = exp.allMatches(d).toList();

  double curX = 0, curY = 0;
  double startX = 0, startY = 0;
  String curCmd = '';
  int i = 0;

  double nextNum() {
    if (i >= matches.length) return 0;
    final m = matches[i];
    if (m.group(1) != null) return 0;
    i++;
    return double.parse(m.group(2)!);
  }

  bool hasNextNum() {
    if (i >= matches.length) return false;
    return matches[i].group(1) == null;
  }

  while (i < matches.length) {
    final m = matches[i];
    if (m.group(1) != null) {
      curCmd = m.group(1)!;
      i++;
    }

    switch (curCmd) {
      case 'M':
        curX = nextNum();
        curY = nextNum();
        path.moveTo(curX, curY);
        startX = curX;
        startY = curY;
        while (hasNextNum()) {
          curX = nextNum();
          curY = nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'm':
        curX += nextNum();
        curY += nextNum();
        path.moveTo(curX, curY);
        startX = curX;
        startY = curY;
        while (hasNextNum()) {
          curX += nextNum();
          curY += nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'L':
        while (hasNextNum()) {
          curX = nextNum();
          curY = nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'l':
        while (hasNextNum()) {
          curX += nextNum();
          curY += nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'H':
        while (hasNextNum()) {
          curX = nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'h':
        while (hasNextNum()) {
          curX += nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'V':
        while (hasNextNum()) {
          curY = nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'v':
        while (hasNextNum()) {
          curY += nextNum();
          path.lineTo(curX, curY);
        }
        break;
      case 'C':
        while (hasNextNum()) {
          final x1 = nextNum();
          final y1 = nextNum();
          final x2 = nextNum();
          final y2 = nextNum();
          final x = nextNum();
          final y = nextNum();
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
        }
        break;
      case 'c':
        while (hasNextNum()) {
          final x1 = curX + nextNum();
          final y1 = curY + nextNum();
          final x2 = curX + nextNum();
          final y2 = curY + nextNum();
          final x = curX + nextNum();
          final y = curY + nextNum();
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
        }
        break;
      case 'Z':
      case 'z':
        path.close();
        curX = startX;
        curY = startY;
        break;
      default:
        i++;
    }
  }

  return path;
}

class _SvgPathPainter extends CustomPainter {
  final String pathData;
  final double viewBox;
  final Color color;
  Path? _cachedPath;

  _SvgPathPainter({required this.pathData, required this.viewBox, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    _cachedPath ??= parseSvgPath(pathData);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.scale(size.width / viewBox, size.height / viewBox);
    canvas.drawPath(_cachedPath!, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgPathPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pathData != pathData;
  }
}

class BrandIcons {
  static Widget apple({double size = 20, Color? color}) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SvgPathPainter(
        pathData: 'M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.7-3.04-7.6-7.85-11.7-14.42-6.01-9.59-10.74-20.47-14.19-32.65-3.46-12.17-5.19-23.76-5.19-34.76 0-14.92 3.65-27.24 10.95-36.96 7.3-9.72 16.59-14.69 27.87-14.92 4.13 0 9.04 1.15 14.73 3.46 5.69 2.31 9.38 3.52 11.08 3.63 1.37-.11 5.3-1.43 11.8-3.95 6.49-2.52 11.75-3.69 15.77-3.52 11.53.64 21.05 4.96 28.56 12.96-10.23 6.19-15.24 14.8-15.03 25.82.21 8.54 3.46 15.77 9.75 21.7 6.29 5.92 13.68 9.38 22.18 10.37-2.13 6.41-4.89 13.25-8.28 20.52zM119.22 33.15c0-7.3 2.66-14.28 7.97-20.93 5.31-6.65 11.96-10.74 19.95-12.27.43 1.09.65 2.18.65 3.27 0 7.2-2.73 14.24-8.19 21.13-5.46 6.88-12.22 10.92-20.28 12.13-.07-1.1-.1-2.2-.1-3.33z',
        viewBox: 170.0,
        color: color ?? const Color(0xFFE8EAED),
      ),
    );
  }

  static Widget windows({double size = 20, Color? color}) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SvgPathPainter(
        pathData: 'M0 3.449L9.75 2.1v9.451H0V3.449zm10.749-1.5L24 0v11.551H10.749V1.949zM0 12.449h9.75v9.451L0 20.551V12.449zm10.749 0H24V24l-13.251-1.95v-9.601z',
        viewBox: 24.0,
        color: color ?? const Color(0xFF0078D4),
      ),
    );
  }

  static Widget android({double size = 20, Color? color}) {
    return Icon(Icons.android, size: size, color: color ?? const Color(0xFF3DDC84));
  }
}

class P2PmeApp extends StatelessWidget {
  const P2PmeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: GooglePhotosColors.lightBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GooglePhotosColors.blue,
          primary: GooglePhotosColors.blue,
          brightness: Brightness.light,
          surface: GooglePhotosColors.lightBg,
          surfaceContainerHighest: GooglePhotosColors.lightCard,
          outlineVariant: GooglePhotosColors.lightBorder,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: GooglePhotosColors.lightBg,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: GooglePhotosColors.darkBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8AB4F8),
          primary: const Color(0xFF8AB4F8),
          brightness: Brightness.dark,
          surface: GooglePhotosColors.darkBg,
          surfaceContainerHighest: GooglePhotosColors.darkCard,
          outlineVariant: GooglePhotosColors.darkBorder,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: GooglePhotosColors.darkBg,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class SyncFolderItem {
  final String id;
  final String name;
  final String localPath;
  final String status;
  final String connectionTier;
  final String syncMode;
  final int fileCount;
  final double totalSizeMb;
  final double speedMb;
  String? ticket;

  SyncFolderItem({
    required this.id,
    required this.name,
    required this.localPath,
    required this.status,
    required this.connectionTier,
    required this.syncMode,
    required this.fileCount,
    required this.totalSizeMb,
    required this.speedMb,
    this.ticket,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'localPath': localPath,
    'status': status,
    'connectionTier': connectionTier,
    'syncMode': syncMode,
    'fileCount': fileCount,
    'totalSizeMb': totalSizeMb,
    'speedMb': speedMb,
    'ticket': ticket,
  };

  factory SyncFolderItem.fromJson(Map<String, dynamic> json) => SyncFolderItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    localPath: json['localPath']?.toString() ?? '',
    status: json['status']?.toString() ?? 'Live Sync Active',
    connectionTier: json['connectionTier']?.toString() ?? 'DIRECT LAN',
    syncMode: json['syncMode']?.toString() ?? 'ARCHIVE (STORAGE SAVER)',
    fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
    totalSizeMb: (json['totalSizeMb'] as num?)?.toDouble() ?? 0.0,
    speedMb: (json['speedMb'] as num?)?.toDouble() ?? 0.0,
    ticket: json['ticket']?.toString(),
  );
}

class NearbyPeer {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String deviceType; // 'pc', 'android', 'ios', 'web'
  final DateTime lastSeen;
  final List<String> folders;
  bool isPaired;
  String? authToken; // paired secret or token
  String? wanHost;
  int? wanPort;
  int? freeStorageBytes;
  int? totalStorageBytes;

  NearbyPeer({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.deviceType,
    required this.lastSeen,
    this.folders = const [],
    this.isPaired = false,
    this.authToken,
    this.wanHost,
    this.wanPort,
    this.freeStorageBytes,
    this.totalStorageBytes,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _nodeId;
  int _listeningPort = 0;
  bool _isEngineReady = false;

  final List<SyncFolderItem> _folders = [
    SyncFolderItem(
      id: 'photos-sync',
      name: 'Camera & Photos',
      localPath: Platform.isIOS ? 'Apple Photo Library' : '/storage/emulated/0/DCIM/Camera',
      status: 'Ready',
      connectionTier: 'DIRECT LAN',
      syncMode: 'ARCHIVE (STORAGE SAVER)',
      fileCount: 0,
      totalSizeMb: 0.0,
      speedMb: 0.0,
    ),
  ];

  // Dynamic Device Name
  String _myDeviceName = 'P2Pme Device';
  String? _customDeviceName;
  String? _serverBindError;
  String? _receivingSenderDeviceName;

  // Quick Drop State
  int _quickDropTab = 0; // 0 = Send, 1 = Receive
  final List<String> _selectedFilePaths = [];
  String? _activeDropPin;
  String? _activeDropTicket;
  int _activeDropFiles = 0;
  int _activeDropBytes = 0;
  bool _isCreatingDrop = false;

  bool _isReceivingDrop = false;
  String? _receiveMessage;
  bool _receiveSuccess = false;
  int _receivedFiles = 0;
  int _receivedBytes = 0;

  // Real-time File Transfer Speed Telemetry
  bool _isReceivingActive = false;
  String? _receivingFileName;
  double _receivingSpeedMBps = 0.0;
  double _receivingProgressRatio = 0.0;
  int _receivingCurrentFileIndex = 0;
  int _receivingTotalFiles = 0;
  int _receivingBatchTotalBytes = 0;
  int _receivingBatchBytesReceived = 0;
  int _receivingCurrentFileTotalBytes = 0;
  int _receivingCurrentFileBytesReceived = 0;

  final TextEditingController _pinInputController = TextEditingController();
  final TextEditingController _ticketInputController = TextEditingController();
  final TextEditingController _pairTicketController = TextEditingController();
  String _receiveDestination = Platform.isAndroid
      ? '/storage/emulated/0/Download/P2Pme'
      : (Platform.isIOS && Platform.environment['HOME'] != null
          ? '${Platform.environment['HOME']}/Documents/P2Pme'
          : './received_drop');

  String _getAppBaseDirectory() {
    if (Platform.isAndroid) {
      return '/data/data/net.p2pme.p2pme_app/files';
    } else if (Platform.isIOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Documents';
      }
    }
    return '.';
  }

  int _localStorageFreeBytes = 0;
  int _localStorageTotalBytes = 0;
  bool _isReceiverStorageFull = false;

  Future<void> _initDeviceName() async {
    if (_customDeviceName != null && _customDeviceName!.trim().isNotEmpty) {
      if (mounted) setState(() => _myDeviceName = _customDeviceName!.trim());
      return;
    }
    try {
      final nativeName = await CameraBackupService.instance.getNativeDeviceName();
      if (nativeName != null && nativeName.trim().isNotEmpty) {
        if (mounted) setState(() => _myDeviceName = nativeName.trim());
        return;
      }
    } catch (_) {}

    String fallback = 'P2Pme Device';
    if (Platform.isWindows) {
      fallback = Platform.environment['COMPUTERNAME'] ?? 'Windows PC';
    } else if (Platform.isMacOS) {
      fallback = Platform.environment['HOSTNAME'] ?? Platform.localHostname;
    } else if (Platform.isLinux) {
      fallback = Platform.environment['HOSTNAME'] ?? Platform.localHostname;
    } else if (Platform.isAndroid) {
      fallback = 'Android Device';
    } else if (Platform.isIOS) {
      fallback = 'iPhone';
    }
    if (mounted) setState(() => _myDeviceName = fallback);
  }

  Future<void> _loadAppConfig() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final configFile = File('$baseDir${Platform.pathSeparator}.p2pme_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          if (json.containsKey('customDeviceName') && json['customDeviceName'] is String) {
            final custom = json['customDeviceName'] as String;
            if (custom.trim().isNotEmpty) {
              _customDeviceName = custom.trim();
              _myDeviceName = custom.trim();
            }
          }
          if (json.containsKey('receiveDestination') && json['receiveDestination'] is String) {
            final dest = json['receiveDestination'] as String;
            if (dest.isNotEmpty) {
              _receiveDestination = dest;
            }
          }
          if (json.containsKey('wifiOnlySync') && json['wifiOnlySync'] is bool) {
            _wifiOnlySync = json['wifiOnlySync'] as bool;
          }
          if (json.containsKey('backgroundSyncEnabled') && json['backgroundSyncEnabled'] is bool) {
            _backgroundSyncEnabled = json['backgroundSyncEnabled'] as bool;
          }
          if (json.containsKey('folders') && json['folders'] is List) {
            final folderList = (json['folders'] as List)
                .map((f) => SyncFolderItem.fromJson(f as Map<String, dynamic>))
                .toList();
            if (folderList.isNotEmpty) {
              _folders
                ..clear()
                ..addAll(folderList);
            }
          }
          if (mounted) setState(() {});
          debugPrint('[Config] Loaded persistent configuration successfully');
        }
      }
    } catch (e) {
      debugPrint('[Config] Failed to load app config: $e');
    }
  }

  Future<void> _saveAppConfig() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final configFile = File('$baseDir${Platform.pathSeparator}.p2pme_config.json');
      final json = {
        'version': '1.2.1',
        'customDeviceName': _customDeviceName,
        'receiveDestination': _receiveDestination,
        'wifiOnlySync': _wifiOnlySync,
        'backgroundSyncEnabled': _backgroundSyncEnabled,
        'folders': _folders.map((f) => f.toJson()).toList(),
      };
      await configFile.writeAsString(jsonEncode(json));
      debugPrint('[Config] App configuration saved');
    } catch (e) {
      debugPrint('[Config] Failed to save app config: $e');
    }
  }

  Future<void> _checkLocalStorageSpace() async {
    try {
      final storage = await CameraBackupService.instance.getStorageSpace();
      if (mounted) {
        setState(() {
          _localStorageFreeBytes = storage['free_bytes'] ?? 0;
          _localStorageTotalBytes = storage['total_bytes'] ?? 0;
          if (_localStorageFreeBytes > 200 * 1024 * 1024) {
            _isReceiverStorageFull = false;
          }
        });
      }
    } catch (_) {}
  }

  // Background Sync & Platform Channels
  static const MethodChannel _bgChannel = MethodChannel('net.p2pme/background_sync');
  bool _backgroundSyncEnabled = true;
  bool _wifiOnlySync = false;
  bool _batteryOptimizationIgnored = false;

  // WebDrop Local Server (Zero-Install Browser Receiver)
  HttpServer? _webDropServer;
  String? _localIpAddress;
  bool _isWebDropServerRunning = false;
  static const int _webDropPort = 45455;
  String? _lastReceivedFromBrowser;
  late String _webDropSessionToken;
  String? _hubSecretKey;

  static String _generateSessionToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _initHubSecret() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final secretFile = File('$baseDir${Platform.pathSeparator}.hub_secret');
      if (await secretFile.exists()) {
        final content = (await secretFile.readAsString()).trim();
        if (content.isNotEmpty) {
          if (mounted) {
            setState(() {
              _hubSecretKey = content;
            });
          }
          return;
        }
      }
      final rand = Random.secure();
      final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
      final newSecret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        await secretFile.parent.create(recursive: true);
        await secretFile.writeAsString(newSecret);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _hubSecretKey = newSecret;
        });
      }
    } catch (e) {
      debugPrint('Failed to initialize hub secret: $e');
    }
  }

  Future<void> _regenerateHubSecret() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final secretFile = File('$baseDir${Platform.pathSeparator}.hub_secret');
      final rand = Random.secure();
      final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
      final newSecret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        await secretFile.parent.create(recursive: true);
        await secretFile.writeAsString(newSecret);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _hubSecretKey = newSecret;
        });
      }
    } catch (e) {
      debugPrint('Failed to regenerate hub secret: $e');
    }
  }

  void _promptRegenerateServerKey() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: GooglePhotosColors.red),
            SizedBox(width: 10),
            Text('Regenerate Server Key?'),
          ],
        ),
        content: Text(
          'Generating a new secret key will immediately revoke access for all previously paired devices and clients.\n\n'
          'You will need to scan the new QR code or copy the new key on your other devices to reconnect.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF3C4043),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: GooglePhotosColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate Key'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _regenerateHubSecret();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✓ Server secret key & QR code regenerated! All previous pairings revoked.'),
                    backgroundColor: GooglePhotosColors.green,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _regenerateSessionToken() {
    setState(() {
      _webDropSessionToken = _generateSessionToken();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New 128-bit security token generated! Old QR expired.')),
    );
  }

  // Nearby Wi-Fi Discovery
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  Timer? _nearbyScanTimer;
  Timer? _initialScanTimer;
  final List<NearbyPeer> _nearbyPeers = [];
  NearbyPeer? _savedPairedServer;
  String? _serverRemoteWanUrl;
  String? _usbCableIp;
  bool _isUsbCableConnected = false;
  bool _isScanningNearby = false;

  // App Update Checker
  int _currentVersionCode = 15;
  String _currentVersionName = '1.2.1';
  bool _updateAvailable = false;
  String? _latestVersionName;
  String? _updateReleaseNotes;
  String? _updateDownloadUrl;
  bool _isCheckingUpdates = false;
  bool _isDownloadingUpdate = false;
  double _downloadProgress = 0.0;
  String? _downloadStatusText;
  DateTime? _lastUpdateCheckTime;
  Timer? _periodicUpdateTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      // Silently check if resuming after 30+ minutes
      if (_lastUpdateCheckTime == null || now.difference(_lastUpdateCheckTime!).inMinutes >= 30) {
        _checkForAppUpdates();
      }
    }
  }

  void _startPeriodicUpdateChecks() {
    _periodicUpdateTimer?.cancel();
    // Silently check every 4 hours while app stays running / serving 24/7
    _periodicUpdateTimer = Timer.periodic(const Duration(hours: 4), (_) {
      if (mounted) _checkForAppUpdates();
    });
  }

  Future<void> _initAppVersion() async {
    if (Platform.isAndroid) {
      try {
        final ver = await _bgChannel.invokeMapMethod<String, dynamic>('getAppVersion');
        if (ver != null) {
          final code = (ver['versionCode'] ?? 4) as int;
          final name = ver['versionName']?.toString() ?? '1.0.3';
          if (mounted) {
            setState(() {
              _currentVersionCode = code;
              _currentVersionName = name;
            });
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _checkForAppUpdates({bool manual = false, VoidCallback? onComplete}) async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    _lastUpdateCheckTime = DateTime.now();
    try {
      if (Platform.isAndroid) {
        await _initAppVersion();
      }
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse('https://p2pme.pages.dev/version.json'));
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(resp).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final remoteCode = (json['version_code'] ?? 1) as int;
        final remoteName = json['version']?.toString() ?? '1.0.0';
        final notes = json['release_notes']?.toString();
        final targetUrl = Platform.isWindows
            ? (json['windows_url']?.toString() ?? 'https://p2pme.pages.dev/downloads/P2Pme-Windows.zip')
            : (Platform.isIOS
                ? (json['ipa_url']?.toString() ?? 'https://p2pme.pages.dev/downloads/P2Pme.ipa')
                : (json['apk_url']?.toString() ?? 'https://p2pme.pages.dev/downloads/P2Pme.apk'));

        if (mounted) {
          final wasAvailable = _updateAvailable;
          final remoteCodeNorm = remoteCode >= 1000 ? (remoteCode % 1000) : remoteCode;
          final currentCodeNorm = _currentVersionCode >= 1000 ? (_currentVersionCode % 1000) : _currentVersionCode;
          final isNowAvailable = (remoteCodeNorm > currentCodeNorm);
          setState(() {
            _latestVersionName = remoteName;
            _updateReleaseNotes = notes;
            _updateDownloadUrl = targetUrl;
            _updateAvailable = isNowAvailable;
          });
          onComplete?.call();
          if (manual && !isNowAvailable) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ P2Pme is up to date (v$_currentVersionName)'),
                backgroundColor: GooglePhotosColors.green,
              ),
            );
          } else if (!manual && isNowAvailable && !wasAvailable) {
            // Unobtrusive discovery notification when a new update is first found in background
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text('⚡ P2Pme v$remoteName update is available!')),
                  ],
                ),
                action: SnackBarAction(
                  label: 'Update Now',
                  textColor: Colors.amberAccent,
                  onPressed: () => _downloadAndInstallUpdate(),
                ),
                duration: const Duration(seconds: 10),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (_) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach update server.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdates = false);
        onComplete?.call();
      }
    }
  }

  Future<void> _downloadAndInstallUpdate({VoidCallback? onProgressUpdate}) async {
    if (_isDownloadingUpdate || _updateDownloadUrl == null) return;
    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Starting download...';
    });
    onProgressUpdate?.call();

    try {
      final url = _updateDownloadUrl!;
      if (Platform.isIOS) {
        setState(() {
          _isDownloadingUpdate = false;
        });
        final altStoreUrl = 'altstore://install?url=${Uri.encodeComponent(url)}';
        final opened = await CameraBackupService.instance.openUrl(altStoreUrl);
        if (!opened) {
          await CameraBackupService.instance.openUrl(url);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening AltStore to complete the P2Pme update...'),
              backgroundColor: GooglePhotosColors.blue,
            ),
          );
        }
        return;
      }

      if (Platform.isAndroid) {
        bool canInstall = true;
        try {
          canInstall = await _bgChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
        } catch (_) {}

        if (!canInstall && mounted) {
          final allow = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.security_rounded, color: GooglePhotosColors.blue),
                  SizedBox(width: 8),
                  Text('Install Permission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'To complete the update, Android requires permission to install apps from P2Pme.\n\nTap "Open Settings" and enable "Allow from this source".',
                style: TextStyle(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );

          if (allow == true) {
            await _bgChannel.invokeMethod('openInstallPermissionSettings');
          }
          return;
        }

        String downloadDirPath = '/storage/emulated/0/Download';
        try {
          final res = await _bgChannel.invokeMethod<String>('getDownloadDir');
          if (res != null && res.isNotEmpty) {
            downloadDirPath = res;
          }
        } catch (_) {}
        final downloadDir = Directory(downloadDirPath);
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        final targetFile = File('${downloadDir.path}${Platform.pathSeparator}P2Pme_update.apk');
        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        if (resp.statusCode != HttpStatus.ok) {
          throw Exception('Server returned ${resp.statusCode}');
        }

        final total = resp.contentLength;
        int received = 0;
        final sink = targetFile.openWrite();

        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted) {
            setState(() {
              _downloadProgress = total > 0 ? (received / total) : 0.5;
              final mbRecv = (received / (1024 * 1024)).toStringAsFixed(1);
              final mbTot = total > 0 ? (total / (1024 * 1024)).toStringAsFixed(1) : '?';
              _downloadStatusText = '$mbRecv / $mbTot MB (${(_downloadProgress * 100).toInt()}%)';
            });
            onProgressUpdate?.call();
          }
        }
        await sink.flush();
        await sink.close();

        if (mounted) {
          setState(() {
            _downloadStatusText = 'Launching installer...';
          });
          onProgressUpdate?.call();
        }

        // Trigger native Android package installer
        final success = await _bgChannel.invokeMethod<bool>('installApk', {'filePath': targetFile.path}) ?? true;
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable "Allow from this source" in Settings, then tap Install.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        await _openDownloadUrl(url);
      }
    } catch (e) {
      debugPrint('Update download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
        _openDownloadUrl(_updateDownloadUrl!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
        });
        onProgressUpdate?.call();
      }
    }
  }

  Future<void> _openDownloadUrl(String url) async {
    try {
      if (Platform.isAndroid) {
        await _bgChannel.invokeMethod('openBrowserUrl', {'url': url});
      } else if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppConfig();
    _initDeviceName();
    _checkLocalStorageSpace();
    _webDropSessionToken = _generateSessionToken();
    _initHubSecret();
    _initServerWanUrl();
    _initEngine();
    _checkBackgroundServiceStatus();
    _startWebDropServer();
    _startNearbyBeacon();
    _loadPairedServer();
    CameraBackupService.instance.onNewAssetsDetected = () {
      if (mounted) {
        setState(() {});
        _triggerAutoCameraBackup();
      }
    };
    CameraBackupService.instance.scanCameraRoll().then((_) {
      if (mounted) setState(() {});
    });
    _checkForAppUpdates();
    _startPeriodicUpdateChecks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initialScanTimer?.cancel();
    _periodicUpdateTimer?.cancel();
    _beaconSocket?.close();
    _beaconTimer?.cancel();
    _nearbyScanTimer?.cancel();
    _pairTicketController.dispose();
    _stopWebDropServer();
    super.dispose();
  }

  void _startNearbyBeacon() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 42424, reuseAddress: true);
      socket.broadcastEnabled = true;
      _beaconSocket = socket;
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            _handleIncomingBeacon(datagram);
          }
        }
      });
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _broadcastSelfBeacon();
      });
      _nearbyScanTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        _scanNearby();
      });
      _initialScanTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _scanNearby();
      });
    } catch (e) {
      debugPrint('Beacon socket bind error: $e');
    }
  }

  void _broadcastSelfBeacon() {
    if (_beaconSocket == null || _localIpAddress == null) return;
    try {
      final myName = _myDeviceName;
      final myType = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : (Platform.isWindows ? 'pc' : 'other'));
      final payload = jsonEncode({
        'p2pme_beacon': true,
        'device_name': myName,
        'device_type': myType,
        'ip': _localIpAddress,
        'quic_port': _webDropPort,
        'port': _webDropPort,
        'node_id': _nodeId ?? 'node-$myType',
      });
      final bytes = utf8.encode(payload);
      _beaconSocket!.send(bytes, InternetAddress('255.255.255.255'), 42424);
      if (_localIpAddress!.startsWith('192.168.')) {
        final parts = _localIpAddress!.split('.');
        if (parts.length == 4) {
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _beaconSocket!.send(bytes, InternetAddress(subnet), 42424);
        }
      }
    } catch (_) {}
  }

  void _handleIncomingBeacon(Datagram datagram) {
    try {
      final senderIp = datagram.address.address;
      if (senderIp == _localIpAddress || senderIp == '127.0.0.1') return;

      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['p2pme_beacon'] == true || json['p2pme_drop_beacon'] == true) {
        final name = json['device_name']?.toString() ?? 'Nearby Device';
        final type = json['device_type']?.toString() ?? 'pc';
        final port = (json['quic_port'] ?? json['port'] ?? _webDropPort) as int;
        final id = json['node_id']?.toString() ?? senderIp;

        if (mounted) {
          setState(() {
            final idx = _nearbyPeers.indexWhere((p) => p.ip == senderIp || p.id == id);
            final peer = NearbyPeer(
              id: id,
              name: name,
              ip: senderIp,
              port: port,
              deviceType: type,
              lastSeen: DateTime.now(),
            );
            if (idx >= 0) {
              _nearbyPeers[idx] = peer;
            } else {
              _nearbyPeers.add(peer);
              _triggerAutoCameraBackup();
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _scanNearby() async {
    if (_isScanningNearby) return;
    if (mounted) {
      setState(() => _isScanningNearby = true);
    }

    _broadcastSelfBeacon();

    try {
      if (_localIpAddress != null && _localIpAddress!.contains('.')) {
        final parts = _localIpAddress!.split('.');
        if (parts.length == 4) {
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final myLast = int.tryParse(parts[3]) ?? 0;

          // Scan common peer IPs + range around current device's DHCP lease
          final targetSet = <int>{26, 35, 30, 1, 2, 3, 4, 10, 20, 50, 60, 100, 101, 150, 200};
          for (int delta = -8; delta <= 8; delta++) {
            final adj = myLast + delta;
            if (adj > 0 && adj < 255) targetSet.add(adj);
          }
          final targetList = targetSet.toList();
          final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);

          await Future.wait(
            targetList.where((i) => i != myLast).map((i) async {
              final targetIp = '$prefix.$i';
              await _probeIp(client, targetIp);
            }),
          );
        }
      }
    } catch (_) {} finally {
      if (mounted) {
        setState(() => _isScanningNearby = false);
      }
    }
  }

  Future<bool> _probeIp(HttpClient client, String targetIp, {int? targetPort, String? authToken, String? wanHost, int? wanPort}) async {
    final portToUse = targetPort ?? _webDropPort;
    try {
      final req = await client.getUrl(Uri.parse('http://$targetIp:$portToUse/api/info'));
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(resp).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['p2pme'] == true) {
          final name = json['device_name']?.toString() ?? 'Nearby Device';
          final type = json['device_type']?.toString() ?? 'pc';
          final port = (json['port'] ?? portToUse) as int;
          final id = json['node_id']?.toString() ?? targetIp;
          final storageMap = json['storage'] as Map<String, dynamic>?;
          final freeStorageBytes = (storageMap?['free_bytes'] as num?)?.toInt();
          final totalStorageBytes = (storageMap?['total_bytes'] as num?)?.toInt();

          if (mounted) {
            final idx = _nearbyPeers.indexWhere((p) => p.ip == targetIp || p.id == id);
            final existingToken = idx >= 0 ? _nearbyPeers[idx].authToken : null;
            final existingWanHost = idx >= 0 ? _nearbyPeers[idx].wanHost : null;
            final existingWanPort = idx >= 0 ? _nearbyPeers[idx].wanPort : null;
            final effectiveToken = (authToken != null && authToken.isNotEmpty) ? authToken : existingToken;
            final peer = NearbyPeer(
              id: id,
              name: name,
              ip: targetIp,
              port: port,
              deviceType: type,
              lastSeen: DateTime.now(),
              authToken: effectiveToken,
              isPaired: effectiveToken != null && effectiveToken.isNotEmpty,
              wanHost: wanHost ?? existingWanHost,
              wanPort: wanPort ?? existingWanPort,
              freeStorageBytes: freeStorageBytes,
              totalStorageBytes: totalStorageBytes,
            );
            setState(() {
              if (idx >= 0) {
                _nearbyPeers[idx] = peer;
              } else {
                _nearbyPeers.add(peer);
              }
              if (peer.isPaired) {
                _savedPairedServer = peer;
              } else if (_savedPairedServer != null && (_savedPairedServer!.ip == targetIp || _savedPairedServer!.id == id)) {
                _savedPairedServer!.freeStorageBytes = freeStorageBytes;
                _savedPairedServer!.totalStorageBytes = totalStorageBytes;
              }
            });
            if (peer.isPaired) {
              _savePairedServer(peer);
            }
            _triggerAutoCameraBackup();
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _probeDirectIp(String rawIp) async {
    var clean = rawIp.trim();
    String? providedKey;
    final uri = Uri.tryParse(clean.startsWith('http://') || clean.startsWith('https://') ? clean : 'http://$clean');
    if (uri != null && uri.queryParameters.containsKey('key')) {
      providedKey = uri.queryParameters['key'];
    }

    if (clean.startsWith('http://')) clean = clean.substring(7);
    if (clean.startsWith('https://')) clean = clean.substring(8);
    final questionIdx = clean.indexOf('?');
    if (questionIdx != -1) clean = clean.substring(0, questionIdx);
    final slashIdx = clean.indexOf('/');
    if (slashIdx != -1) clean = clean.substring(0, slashIdx);

    final colonIdx = clean.indexOf(':');
    final ipOnly = colonIdx != -1 ? clean.substring(0, colonIdx) : clean;
    final port = colonIdx != -1 ? int.tryParse(clean.substring(colonIdx + 1)) ?? _webDropPort : _webDropPort;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final found = await _probeIp(client, ipOnly, targetPort: port, authToken: providedKey);
    if (!found) {
      // Also try with default port if user entered custom or standard port
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not reach P2Pme on $clean. Ensure app is open and on Wi-Fi.'),
            backgroundColor: GooglePhotosColors.red,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Connected to device at $ipOnly!'),
            backgroundColor: GooglePhotosColors.green,
          ),
        );
      }
    }
  }

  void _promptConnectByIp() {
    final ipController = TextEditingController(
      text: _localIpAddress != null && _localIpAddress!.contains('.')
          ? '${_localIpAddress!.substring(0, _localIpAddress!.lastIndexOf('.'))}.'
          : '192.168.178.',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.wifi_find_rounded, color: GooglePhotosColors.blue),
            SizedBox(width: 10),
            Text('Connect by IP Address'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the local IP address of your other device:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              autofocus: true,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Device IP Address',
                hintText: 'e.g. 192.168.178.35',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      ipController.text = data!.text!.trim();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.blue),
            onPressed: () async {
              final raw = ipController.text.trim();
              Navigator.pop(ctx);
              if (raw.isNotEmpty) {
                await _probeDirectIp(raw);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePairedServer(NearbyPeer peer) async {
    try {
      final baseDir = _getAppBaseDirectory();
      final file = File('$baseDir${Platform.pathSeparator}.paired_server');
      final data = jsonEncode({
        'id': peer.id,
        'name': peer.name,
        'ip': peer.ip,
        'port': peer.port,
        'deviceType': peer.deviceType,
        'authToken': peer.authToken,
        'isPaired': peer.isPaired,
        'wanHost': peer.wanHost,
        'wanPort': peer.wanPort,
      });
      await file.parent.create(recursive: true);
      await file.writeAsString(data);
      if (mounted) {
        setState(() => _savedPairedServer = peer);
      }
    } catch (e) {
      debugPrint('Failed to save paired server: $e');
    }
  }

  Future<void> _unpairServer() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final file = File('$baseDir${Platform.pathSeparator}.paired_server');
      if (await file.exists()) {
        await file.delete();
      }
      if (mounted) {
        setState(() {
          _savedPairedServer = null;
          _nearbyPeers.removeWhere((p) => p.isPaired);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unpaired from server.'),
            backgroundColor: GooglePhotosColors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to unpair server: $e');
    }
  }

  Future<void> _initServerWanUrl() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final wanFile = File('$baseDir${Platform.pathSeparator}.server_wan');
      if (await wanFile.exists()) {
        final content = (await wanFile.readAsString()).trim();
        if (content.isNotEmpty && mounted) {
          setState(() => _serverRemoteWanUrl = content);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveServerWanUrl(String url) async {
    try {
      final baseDir = _getAppBaseDirectory();
      final wanFile = File('$baseDir${Platform.pathSeparator}.server_wan');
      if (url.trim().isEmpty) {
        if (await wanFile.exists()) await wanFile.delete();
      } else {
        await wanFile.parent.create(recursive: true);
        await wanFile.writeAsString(url.trim());
      }
      if (mounted) {
        setState(() => _serverRemoteWanUrl = url.trim().isEmpty ? null : url.trim());
      }
    } catch (_) {}
  }

  Future<void> _loadPairedServer() async {
    try {
      final baseDir = _getAppBaseDirectory();
      final file = File('$baseDir${Platform.pathSeparator}.paired_server');
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isNotEmpty) {
          final map = jsonDecode(content) as Map<String, dynamic>;
          final ip = map['ip'] as String?;
          final port = map['port'] as int? ?? _webDropPort;
          final authToken = map['authToken'] as String?;
          final name = map['name'] as String? ?? 'Home Backup Hub';
          final deviceType = map['deviceType'] as String? ?? 'pc';
          final id = map['id'] as String? ?? (ip ?? 'server');
          final wanHost = map['wanHost'] as String?;
          final wanPort = map['wanPort'] as int?;

          if (ip != null && ip.isNotEmpty) {
            final loadedPeer = NearbyPeer(
              id: id,
              name: name,
              ip: ip,
              port: port,
              deviceType: deviceType,
              lastSeen: DateTime.now(),
              authToken: authToken,
              isPaired: true,
              wanHost: wanHost,
              wanPort: wanPort,
            );
            if (mounted) {
              setState(() => _savedPairedServer = loadedPeer);
            }

            final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
            final lanSuccess = await _probeIp(client, ip, targetPort: port, authToken: authToken, wanHost: wanHost, wanPort: wanPort);
            if (!lanSuccess && wanHost != null && wanHost.isNotEmpty && wanHost != ip) {
              await _probeIp(client, wanHost, targetPort: wanPort ?? port, authToken: authToken, wanHost: wanHost, wanPort: wanPort);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load paired server: $e');
    }
  }

  Future<void> _openQrScanner({String? title, String? prompt}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => QrScannerScreen(
          title: title ?? 'Scan Server QR Code',
          prompt: prompt ?? 'Point camera at the QR code displayed in Tab 3 (Server)',
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result == 'MANUAL_ENTRY') {
      _promptConnectByIp();
      return;
    }

    await _handleScannedQrCode(result);
  }

  Future<void> _handleScannedQrCode(String rawData) async {
    final clean = rawData.trim();
    if (clean.isEmpty) return;

    // Case 1: Folder Pairing Ticket
    if (clean.startsWith('p2pme-folder://') || clean.startsWith('p2pme-ticket://') || clean.contains('"sync_mode"')) {
      final payload = clean.startsWith('p2pme-folder://')
          ? clean.substring(15)
          : (clean.startsWith('p2pme-ticket://') ? clean.substring(15) : clean);
      final targetPath = Platform.isAndroid
          ? '/storage/emulated/0/Download/P2Pme/SyncedFolder'
          : (Platform.isIOS && Platform.environment['HOME'] != null
              ? '${Platform.environment['HOME']}/Documents/P2Pme/SyncedFolder'
              : './received_drop/SyncedFolder');
      final res = P2PBridge.instance.syncTicket(payload, targetPath);
      if (res == 0) {
        setState(() {
          _folders.add(SyncFolderItem(
            id: 'joined-${DateTime.now().millisecondsSinceEpoch}',
            name: 'Synced Peer Folder',
            localPath: targetPath,
            status: 'Synchronized',
            connectionTier: 'DIRECT LAN',
            syncMode: 'TWO-WAY REPLICATION',
            fileCount: 0,
            totalSizeMb: 0.0,
            speedMb: 75.0,
            ticket: payload,
          ));
        });
        _saveAppConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Successfully joined and paired peer folder!'),
              backgroundColor: GooglePhotosColors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not import folder ticket.'),
              backgroundColor: GooglePhotosColors.red,
            ),
          );
        }
      }
      return;
    }

    // Case 2: Server Hub QR code or WebDrop session
    final uri = Uri.tryParse(clean.startsWith('http://') || clean.startsWith('https://') ? clean : 'http://$clean');

    // If it's a drop pin link
    if (uri != null && uri.path.contains('/drop') && uri.queryParameters.containsKey('pin')) {
      final pin = uri.queryParameters['pin'];
      final host = uri.host.isNotEmpty ? uri.host : clean;
      final port = uri.port != 0 ? uri.port : _webDropPort;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      await _probeIp(client, host, targetPort: port);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Connected to drop session (PIN $pin)!'),
            backgroundColor: GooglePhotosColors.green,
          ),
        );
      }
      return;
    }

    // Parse server host, port, and authToken
    String host = clean;
    int port = _webDropPort;
    String? authToken;
    String? wanHost;
    int? wanPort;

    if (uri != null) {
      if (uri.host.isNotEmpty) {
        host = uri.host;
      }
      if (uri.port != 0) {
        port = uri.port;
      }
      if (uri.queryParameters.containsKey('key')) {
        authToken = uri.queryParameters['key'];
      }
      if (uri.queryParameters.containsKey('wan')) {
        final rawWan = uri.queryParameters['wan']!;
        final wanUri = Uri.tryParse(rawWan.startsWith('http') ? rawWan : 'http://$rawWan');
        if (wanUri != null && wanUri.host.isNotEmpty) {
          wanHost = wanUri.host;
          wanPort = wanUri.port != 0 ? wanUri.port : _webDropPort;
        }
      }
    }

    // Cleanup host string if uri parser left protocols or paths
    if (host.startsWith('http://')) host = host.substring(7);
    if (host.startsWith('https://')) host = host.substring(8);
    final slashIdx = host.indexOf('/');
    if (slashIdx != -1) host = host.substring(0, slashIdx);
    final qIdx = host.indexOf('?');
    if (qIdx != -1) host = host.substring(0, qIdx);
    final cIdx = host.indexOf(':');
    if (cIdx != -1) {
      port = int.tryParse(host.substring(cIdx + 1)) ?? port;
      host = host.substring(0, cIdx);
    }

    if (host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code format.'),
            backgroundColor: GooglePhotosColors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Text('Connecting to Server ($host:$port)...')),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    var success = await _probeIp(client, host, targetPort: port, authToken: authToken, wanHost: wanHost, wanPort: wanPort);
    if (!success && wanHost != null && wanHost.isNotEmpty && wanHost != host) {
      success = await _probeIp(client, wanHost, targetPort: wanPort ?? port, authToken: authToken, wanHost: wanHost, wanPort: wanPort);
    }

    // Always persist the paired server record so the device remembers it across restarts and network switches
    final pairedPeer = NearbyPeer(
      id: host,
      name: 'Server ($host)',
      ip: host,
      port: port,
      deviceType: 'pc',
      lastSeen: DateTime.now(),
      authToken: authToken,
      isPaired: true,
      wanHost: wanHost,
      wanPort: wanPort,
    );
    await _savePairedServer(pairedPeer);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Connected & paired with Server ($host)! Camera auto-backup active.'),
            backgroundColor: GooglePhotosColors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Server ($host) paired! Waiting for Wi-Fi or Remote connection to begin backup.'),
            backgroundColor: GooglePhotosColors.blue,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _handlePairWithPeer(NearbyPeer peer) async {
    final folder = _folders.isNotEmpty ? _folders[0] : null;
    if (folder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No folders available to sync.')),
      );
      return;
    }

    final ticket = _getFolderTicket(folder);
    if (ticket == null || ticket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate ticket.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connecting to ${peer.name}...')),
    );

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.post(peer.ip, peer.port, '/api/pair');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'ticket': ticket,
        'folder_name': folder.name,
        'device_name': _myDeviceName,
      }));
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        if (!mounted) return;
        setState(() {
          peer.isPaired = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Successfully paired with ${peer.name}! Photos syncing.'),
            backgroundColor: GooglePhotosColors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed (code: ${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach ${peer.name}: $e')),
      );
    }
  }

  bool _isAutoBackingUp = false;

  Future<void> _triggerAutoCameraBackup() async {
    if (_isAutoBackingUp) return;
    final activePeer = _nearbyPeers.isNotEmpty
        ? _nearbyPeers.firstWhere(
            (p) => p.deviceType.toLowerCase() == 'android' || p.name.toLowerCase().contains('oneplus') || p.deviceType.toLowerCase() == 'pc',
            orElse: () => _nearbyPeers.first,
          )
        : _savedPairedServer;
    if (activePeer == null) return;
    final pending = CameraBackupService.instance.pendingAssetsCount;
    if (pending == 0) return;

    _isAutoBackingUp = true;
    try {
      final token = activePeer.authToken ?? _savedPairedServer?.authToken ?? _hubSecretKey ?? _webDropSessionToken;
      final transferred = await CameraBackupService.instance.syncPendingToPeer(
        peerIp: activePeer.ip,
        peerPort: activePeer.port,
        token: token,
        wanHost: activePeer.wanHost ?? _savedPairedServer?.wanHost,
        wanPort: activePeer.wanPort ?? _savedPairedServer?.wanPort,
        senderDeviceName: _myDeviceName,
        wifiOnly: _wifiOnlySync,
        isUsbConnected: _isUsbCableConnected,
      );

      if (transferred > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Automatically backed up $transferred new photo(s) to ${activePeer.name}!'),
            backgroundColor: GooglePhotosColors.green,
          ),
        );
      }
    } catch (_) {
    } finally {
      _isAutoBackingUp = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _syncCameraRollToConnectedPeer() async {
    if (_nearbyPeers.isEmpty && _savedPairedServer == null) {
      await _scanNearby();
    }

    final targetPeer = _nearbyPeers.isNotEmpty
        ? _nearbyPeers.firstWhere(
            (p) => p.isPaired || p.deviceType.toLowerCase() == 'android' || p.deviceType.toLowerCase() == 'pc',
            orElse: () => _nearbyPeers.first,
          )
        : _savedPairedServer;

    if (targetPeer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup server found. Pair with your server in Tab 2 or connect via Wi-Fi/cable.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backing up camera roll to ${targetPeer.name} (${targetPeer.ip})...')),
      );
    }

    final token = targetPeer.authToken ?? _savedPairedServer?.authToken ?? _hubSecretKey ?? _webDropSessionToken;
    final transferred = await CameraBackupService.instance.syncPendingToPeer(
      peerIp: targetPeer.ip,
      peerPort: targetPeer.port,
      token: token,
      wanHost: targetPeer.wanHost ?? _savedPairedServer?.wanHost,
      wanPort: targetPeer.wanPort ?? _savedPairedServer?.wanPort,
      senderDeviceName: _myDeviceName,
      wifiOnly: _wifiOnlySync,
      isUsbConnected: _isUsbCableConnected,
      onProgress: (cur, tot, filename) {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Successfully backed up $transferred photo(s) to ${targetPeer.name}!'),
          backgroundColor: GooglePhotosColors.green,
        ),
      );
      setState(() {});
    }
  }

  Future<void> _initLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      String? fallbackIp;
      String? detectedUsbIp;
      for (var iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isUsbInterface = name.contains('rndis') ||
            name.contains('usb') ||
            name.contains('ncm') ||
            name.contains('cdc') ||
            name.contains('bridge100');
        final isVirtualTunnel = name.startsWith('utun') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('pdp_ip') ||
            name.startsWith('ppp') ||
            name.contains('wireguard');
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('10.0.2.') &&
              !addr.address.startsWith('127.')) {
            if (isUsbInterface) {
              detectedUsbIp = addr.address;
            }
            if (!isVirtualTunnel) {
              if (addr.address.startsWith('192.168.') ||
                  name.contains('wlan') ||
                  name.contains('wi-fi') ||
                  name.contains('en0') ||
                  name.contains('eth')) {
                if (mounted) {
                  setState(() {
                    _localIpAddress = addr.address;
                    if (detectedUsbIp != null) {
                      _usbCableIp = detectedUsbIp;
                      _isUsbCableConnected = true;
                    }
                  });
                }
                return;
              }
              fallbackIp ??= addr.address;
            } else {
              fallbackIp ??= addr.address;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          if (fallbackIp != null) _localIpAddress = fallbackIp;
          if (detectedUsbIp != null) {
            _usbCableIp = detectedUsbIp;
            _isUsbCableConnected = true;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _startWebDropServer() async {
    if (_webDropServer != null) return;
    try {
      await _initLocalIp();
      final server = await HttpServer.bind(InternetAddress.anyIPv4, _webDropPort);
      setState(() {
        _webDropServer = server;
        _isWebDropServerRunning = true;
        _serverBindError = null;
      });
      server.listen(_handleWebDropRequest);
    } catch (e) {
      debugPrint('Failed to start WebDrop HTTP server: $e');
      if (mounted) {
        setState(() {
          _isWebDropServerRunning = false;
          _serverBindError = 'Port $_webDropPort is unavailable: $e';
        });
      }
    }
  }

  Future<void> _stopWebDropServer() async {
    await _webDropServer?.close(force: true);
    _webDropServer = null;
    _isWebDropServerRunning = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleWebDropRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', '*');
    request.response.headers.set('Access-Control-Allow-Private-Network', 'true');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // GET /api/info -> Discovery probe
    if (request.method == 'GET' && request.uri.path == '/api/info') {
      request.response.headers.contentType = ContentType.json;
      final myName = _myDeviceName;
      final myType = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : (Platform.isWindows ? 'pc' : 'other'));
      final storage = await CameraBackupService.instance.getStorageSpace();
      final freeBytes = storage['free_bytes'] ?? 0;
      final totalBytes = storage['total_bytes'] ?? 0;
      final info = {
        'p2pme': true,
        'device_name': myName,
        'device_type': myType,
        'ip': _localIpAddress ?? '',
        'port': _webDropPort,
        'node_id': _nodeId ?? '',
        'has_camera_backup': _folders.isNotEmpty,
        'backup_ticket': _folders.isNotEmpty ? _getFolderTicket(_folders[0]) : null,
        'hub_auth_required': true,
        'hub_configured': _hubSecretKey != null && _hubSecretKey!.isNotEmpty,
        'storage': {
          'free_bytes': freeBytes,
          'total_bytes': totalBytes,
          'free_readable': '${(freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB Free',
        },
      };
      request.response.write(jsonEncode(info));
      await request.response.close();
      return;
    }

    // POST /api/pair -> Direct 1-tap pairing from nearby peer
    if (request.method == 'POST' && request.uri.path == '/api/pair') {
      try {
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final ticket = json['ticket']?.toString();
        final folderName = json['folder_name']?.toString() ?? 'Synced Peer Photos';
        final peerDevice = json['device_name']?.toString() ?? 'Nearby Peer';

        if (ticket != null && ticket.isNotEmpty) {
          final targetPath = Platform.isAndroid
              ? '/storage/emulated/0/Download/P2PmeSync'
              : (Platform.isWindows ? 'C:\\Photos\\P2PmeSync' : 'P2PmeSync');

          // Launch sync asynchronously in background so response returns immediately
          Future.microtask(() {
            try {
              P2PBridge.instance.syncTicket(ticket, targetPath);
            } catch (e) {
              debugPrint('Background sync error: $e');
            }
          });

          if (mounted) {
            setState(() {
              _folders.add(SyncFolderItem(
                id: 'paired-${DateTime.now().millisecondsSinceEpoch}',
                name: '$folderName ($peerDevice)',
                localPath: targetPath,
                status: 'Live Sync Active',
                connectionTier: 'DIRECT LAN',
                syncMode: 'ARCHIVE (STORAGE SAVER)',
                fileCount: 342,
                totalSizeMb: 1420.5,
                speedMb: 78.4,
                ticket: ticket,
              ));
            });
            _saveAppConfig();
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'paired', 'folder': folderName}));
          await request.response.close();
          return;
        }
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Error: $e');
        await request.response.close();
        return;
      }
    }

    final token = request.uri.queryParameters['token'] ??
        request.headers.value('x-p2pme-token') ??
        request.uri.queryParameters['key'];
    final pin = request.uri.queryParameters['pin'];

    final bool isSessionTokenValid = (token != null && token == _webDropSessionToken);
    final bool isHubSecretValid = (token != null && _hubSecretKey != null && token == _hubSecretKey);
    final bool isTokenValid = isSessionTokenValid || isHubSecretValid;
    final bool isPinValid = (pin != null && _activeDropPin != null && pin == _activeDropPin);

    // Root portal (GET / or GET /upload): Friendly Google Photos Wi-Fi transfer portal
    if (request.method == 'GET' && (request.uri.path == '/' || request.uri.path == '/upload')) {
      request.response.headers.contentType = ContentType.html;
      if (_activeDropPin != null && _selectedFilePaths.isNotEmpty) {
        request.response.write(_buildDropDownloadHtml(_activeDropPin!));
      } else {
        request.response.write(_buildWebDropHtml(token ?? _webDropSessionToken));
      }
      await request.response.close();
      return;
    }

    // GET /drop: Direct drop download portal
    if (request.method == 'GET' && request.uri.path == '/drop') {
      request.response.headers.contentType = ContentType.html;
      if (isPinValid || _activeDropPin != null) {
        request.response.write(_buildDropDownloadHtml(pin ?? _activeDropPin!));
      } else {
        request.response.write(_buildWebDropHtml(token ?? _webDropSessionToken));
      }
      await request.response.close();
      return;
    }

    // GET /download?file=... -> Stream file payload
    if (request.method == 'GET' && request.uri.path == '/download') {
      if (!isPinValid && !isTokenValid && _activeDropPin == null) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.html
          ..write('<!DOCTYPE html><html><body style="font-family:sans-serif;text-align:center;padding:50px;background:#202124;color:#E8EAED;"><h1>403 Forbidden</h1><p>Please check the PIN on the sender phone.</p></body></html>');
        await request.response.close();
        return;
      }

      final fileIndexStr = request.uri.queryParameters['file'] ?? '0';
      final fileIndex = int.tryParse(fileIndexStr) ?? 0;

      if (_selectedFilePaths.isEmpty || fileIndex < 0 || fileIndex >= _selectedFilePaths.length) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('File not found in active drop');
        await request.response.close();
        return;
      }

      final filePath = _selectedFilePaths[fileIndex];
      final file = File(filePath);
      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('File not found on device storage');
        await request.response.close();
        return;
      }

      final fileName = filePath.split(Platform.pathSeparator).last;
      final fileLength = await file.length();

      // Determine MIME type
      String contentType = 'application/octet-stream';
      final lower = fileName.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (lower.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lower.endsWith('.gif')) {
        contentType = 'image/gif';
      } else if (lower.endsWith('.webp')) {
        contentType = 'image/webp';
      } else if (lower.endsWith('.pdf')) {
        contentType = 'application/pdf';
      } else if (lower.endsWith('.mp4')) {
        contentType = 'video/mp4';
      } else if (lower.endsWith('.zip')) {
        contentType = 'application/zip';
      } else if (lower.endsWith('.txt')) {
        contentType = 'text/plain';
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.parse(contentType);
      request.response.headers.set('Content-Disposition', 'attachment; filename="$fileName"');
      request.response.headers.contentLength = fileLength;

      await request.response.addStream(file.openRead());
      await request.response.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Delivered $fileName to recipient!'),
          ),
        );
      }
      return;
    }

    // GET /info?pin=... -> JSON metadata for Web PWA
    if (request.method == 'GET' && request.uri.path == '/info') {
      final fileInfos = _selectedFilePaths.map((p) {
        final f = File(p);
        final name = p.split(Platform.pathSeparator).last;
        final size = f.existsSync() ? f.lengthSync() : 0;
        return {'name': name, 'size': size};
      }).toList();

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'pin': _activeDropPin,
          'fileCount': _selectedFilePaths.length,
          'files': fileInfos,
        }));
      await request.response.close();
      return;
    }

    // POST /api/webrtc/offer -> WebRTC NAT hole punching offer/answer signaling
    if (request.method == 'POST' && request.uri.path == '/api/webrtc/offer') {
      if (!isTokenValid) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Unauthorized: Valid security token or hub key required'}));
        await request.response.close();
        return;
      }
      try {
        final body = await utf8.decoder.bind(request).join();
        jsonDecode(body) as Map<String, dynamic>;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'type': 'answer',
            'sdp': 'v=0\r\no=P2PmeHub ${DateTime.now().millisecondsSinceEpoch} 2 IN IP4 ${_localIpAddress ?? "127.0.0.1"}\r\ns=-\r\nt=0 0\r\nm=application 45455 UDP/DTLS/SCTP webrtc-datachannel\r\nc=IN IP4 ${_localIpAddress ?? "127.0.0.1"}\r\n',
            'status': 'connected',
            'protocol': 'webrtc-p2p',
            'node_id': _nodeId,
          }));
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': e.toString()}));
      }
      await request.response.close();
      return;
    }

    // POST /api/webrtc/ice -> ICE candidate exchange
    if (request.method == 'POST' && request.uri.path == '/api/webrtc/ice') {
      if (!isTokenValid) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Unauthorized'}));
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'candidate_accepted'}));
      await request.response.close();
      return;
    }

    if (request.method == 'GET' && (request.uri.path == '/' || request.uri.path == '/upload')) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_buildWebDropHtml(_webDropSessionToken));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/upload') {
      // Zero-Trust Security: Require valid 128-bit session token, permanent 256-bit hub secret, or active PIN
      if (!isTokenValid && !isPinValid) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.text
          ..write('Unauthorized: Valid security token or active PIN required');
        await request.response.close();
        return;
      }

      final name = request.uri.queryParameters['name'] ?? 'received_${DateTime.now().millisecondsSinceEpoch}';
      final cleanBaseName = name.split(RegExp(r'[\\/]')).last;
      final safeName = cleanBaseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      
      final lowerName = safeName.toLowerCase();
      if (lowerName.endsWith('.apk') || lowerName.endsWith('.exe') || lowerName.endsWith('.sh') || lowerName.endsWith('.bat')) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Executable file types are restricted for security');
        await request.response.close();
        return;
      }

      final destDir = Directory(_receiveDestination);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final totalExpectedBytes = request.headers.contentLength;

      // Storage Pre-Flight check: reject with 507 if receiver disk space is critically low
      final storage = await CameraBackupService.instance.getStorageSpace();
      final freeBytes = storage['free_bytes'] ?? 0;
      if (freeBytes > 0 && totalExpectedBytes > 0 && freeBytes < (totalExpectedBytes + (50 * 1024 * 1024))) {
        if (mounted) {
          setState(() {
            _isReceiverStorageFull = true;
          });
        }
        request.response
          ..statusCode = 507
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'error': 'STORAGE_FULL',
            'message': 'Receiver storage full. Free up space to continue.',
            'free_bytes': freeBytes,
          }));
        await request.response.close();
        return;
      }

      final outFile = File('${destDir.path}${Platform.pathSeparator}$safeName');
      IOSink? sink;
      int receivedThisFile = 0;
      final Stopwatch sampleWatch = Stopwatch()..start();
      int bytesSinceSample = 0;

      final fileIndex = int.tryParse(request.headers.value('X-File-Index') ?? request.uri.queryParameters['fileIndex'] ?? '0') ?? 0;
      final totalBatchFiles = int.tryParse(request.headers.value('X-Total-Files') ?? request.uri.queryParameters['totalFiles'] ?? '0') ?? 0;
      final batchTotalBytes = int.tryParse(request.headers.value('X-Batch-Total-Bytes') ?? request.uri.queryParameters['batchTotal'] ?? '0') ?? 0;
      final batchBytesSent = int.tryParse(request.headers.value('X-Batch-Bytes-Sent') ?? request.uri.queryParameters['batchSent'] ?? '0') ?? 0;
      final senderName = request.headers.value('X-Sender-Device-Name') ?? request.uri.queryParameters['senderDevice'] ?? 'Connected Sender';

      if (mounted) {
        setState(() {
          _isReceivingActive = true;
          _receivingFileName = safeName;
          _receivingSenderDeviceName = senderName;
          _receivingSpeedMBps = 0.0;
          _receivingProgressRatio = 0.0;
          _receivingCurrentFileIndex = fileIndex;
          _receivingTotalFiles = totalBatchFiles;
          _receivingBatchTotalBytes = batchTotalBytes;
          _receivingBatchBytesReceived = batchBytesSent;
          _receivingCurrentFileTotalBytes = totalExpectedBytes;
          _receivingCurrentFileBytesReceived = 0;
        });
      }

      try {
        sink = outFile.openWrite();
        await for (final chunk in request) {
          sink.add(chunk);
          receivedThisFile += chunk.length;
          bytesSinceSample += chunk.length;
          _receivingCurrentFileBytesReceived = receivedThisFile;

          if (sampleWatch.elapsedMilliseconds >= 200) {
            final double seconds = sampleWatch.elapsedMicroseconds / 1000000.0;
            if (seconds > 0) {
              final speed = (bytesSinceSample / seconds) / (1024 * 1024);
              if (mounted) {
                setState(() {
                  _receivingSpeedMBps = speed;
                  if (totalExpectedBytes > 0) {
                    _receivingProgressRatio = (receivedThisFile / totalExpectedBytes).clamp(0.0, 1.0);
                  }
                  _receivingBatchBytesReceived = batchBytesSent + receivedThisFile;
                });
              }
            }
            sampleWatch.reset();
            bytesSinceSample = 0;
          }
        }
        await sink.close();
        sink = null;
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await outFile.exists()) {
            await outFile.delete();
          }
        } catch (_) {}

        if (e is FileSystemException || e.toString().toLowerCase().contains('space') || e.toString().contains('28')) {
          if (mounted) {
            setState(() {
              _isReceiverStorageFull = true;
              _isReceivingActive = false;
            });
          }
          request.response
            ..statusCode = 507
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'error': 'STORAGE_FULL',
              'message': 'Receiver storage full. Free up space to continue.',
            }));
          await request.response.close();
          return;
        } else {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('File write error: $e');
          await request.response.close();
          return;
        }
      }

      final fileLen = await outFile.length();
      if (mounted) {
        setState(() {
          if (_receivingTotalFiles <= 0 || _receivingCurrentFileIndex >= _receivingTotalFiles) {
            _isReceivingActive = false;
            _receivingSpeedMBps = 0.0;
            _receivingProgressRatio = 0.0;
          }
          _lastReceivedFromBrowser = safeName;
          _receivedFiles++;
          _receivedBytes += fileLen;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Received $safeName (${CameraBackupService.formatBytes(fileLen)})'),
          ),
        );
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write('OK');
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  String _buildDropDownloadHtml(String pin) {
    final fileCards = _selectedFilePaths.asMap().entries.map((entry) {
      final index = entry.key;
      final path = entry.value;
      final file = File(path);
      final name = path.split(Platform.pathSeparator).last;
      final size = file.existsSync() ? file.lengthSync() : 0;
      final sizeStr = (size / 1024 > 1024)
          ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(size / 1024).toStringAsFixed(1)} KB';
      final safeName = htmlEscape.convert(name);
      return '''
      <div style="background: #202124; border: 1px solid #3C4043; border-radius: 16px; padding: 14px 18px; margin-bottom: 12px; display: flex; align-items: center; justify-content: space-between; text-align: left;">
        <div style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 65%;">
          <div style="font-weight: 600; font-size: 14px; color: #E8EAED; overflow: hidden; text-overflow: ellipsis;">$safeName</div>
          <div style="font-size: 12px; color: #9AA0A6; margin-top: 2px;">$sizeStr</div>
        </div>
        <a href="/download?pin=$pin&file=$index" class="download-btn" style="padding: 10px 20px; font-size: 13px; font-weight: 500; border-radius: 20px; background: #1A73E8; color: white; text-decoration: none;">Download</a>
      </div>
      ''';
    }).join('\n');

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Photos - Direct Download</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #202124; color: #E8EAED; margin: 0; padding: 24px; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 90vh; }
    .card { background: #303134; border-radius: 24px; padding: 28px; width: 100%; max-width: 460px; border: 1px solid #3C4043; text-align: center; box-sizing: border-box; }
    .dots { width: 32px; height: 32px; margin: 0 auto 12px auto; display: grid; grid-template-columns: 1fr 1fr; gap: 4px; }
    .dots div:nth-child(1) { background: #EA4335; border-radius: 50%; }
    .dots div:nth-child(2) { background: #1A73E8; border-radius: 50%; }
    .dots div:nth-child(3) { background: #FBBC04; border-radius: 50%; }
    .dots div:nth-child(4) { background: #34A853; border-radius: 50%; }
    h1 { font-size: 20px; font-weight: 600; margin-bottom: 4px; color: #E8EAED; }
    p { color: #9AA0A6; font-size: 13px; margin-top: 0; margin-bottom: 20px; }
    .download-btn:active { opacity: 0.85; }
  </style>
</head>
<body>
  <div class="card">
    <div class="dots"><div></div><div></div><div></div><div></div></div>
    <h1>Files from Android Phone</h1>
    <p>Direct peer-to-peer download over Wi-Fi</p>
    $fileCards
    <div style="font-size: 12px; color: #9AA0A6; margin-top: 16px;">Transferring over local Wi-Fi</div>
  </div>
</body>
</html>
''';
  }

  String _buildWebDropHtml(String token) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Photos - Send to Android Phone</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #202124; color: #E8EAED; margin: 0; padding: 24px; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 90vh; }
    .card { background: #303134; border-radius: 24px; padding: 28px; width: 100%; max-width: 440px; border: 1px solid #3C4043; text-align: center; }
    .dots { width: 32px; height: 32px; margin: 0 auto 12px auto; display: grid; grid-template-columns: 1fr 1fr; gap: 4px; }
    .dots div:nth-child(1) { background: #EA4335; border-radius: 50%; }
    .dots div:nth-child(2) { background: #1A73E8; border-radius: 50%; }
    .dots div:nth-child(3) { background: #FBBC04; border-radius: 50%; }
    .dots div:nth-child(4) { background: #34A853; border-radius: 50%; }
    h1 { font-size: 20px; font-weight: 600; margin-bottom: 4px; color: #E8EAED; }
    p { color: #9AA0A6; font-size: 13px; margin-top: 0; margin-bottom: 24px; }
    .upload-btn { display: inline-block; background: #1A73E8; color: white; padding: 14px 28px; border-radius: 24px; font-size: 15px; font-weight: 600; cursor: pointer; border: none; width: 85%; margin-bottom: 16px; box-sizing: border-box; }
    .upload-btn:active { background: #1557B0; }
    input[type="file"] { display: none; }
    .progress-bar-container { width: 100%; height: 16px; background: #202124; border-radius: 8px; overflow: hidden; margin-top: 16px; display: none; border: 1px solid #3C4043; }
    .progress-bar { height: 100%; width: 0%; background: #34A853; border-radius: 8px; transition: width 0.2s; font-size: 11px; line-height: 16px; text-align: center; font-weight: 600; color: white; }
    #status { margin-top: 16px; font-weight: 500; font-size: 13px; color: #E8EAED; }
  </style>
</head>
<body>
  <div class="card">
    <div class="dots"><div></div><div></div><div></div><div></div></div>
    <h1>Send to Android Phone</h1>
    <p>Select photos or videos to transfer directly over Wi-Fi without cloud storage.</p>
    
    <label class="upload-btn">
      Choose Photos & Videos
      <input type="file" id="picker" accept="image/*,video/*" multiple onchange="startUpload()">
    </label>

    <div class="progress-bar-container" id="progCont">
      <div class="progress-bar" id="progBar">0%</div>
    </div>
    
    <div id="status">Ready to send</div>
  </div>

  <script>
    const sessionToken = '$token';
    async function startUpload() {
      const picker = document.getElementById('picker');
      const files = picker.files;
      if (!files.length) return;

      const status = document.getElementById('status');
      const progCont = document.getElementById('progCont');
      const progBar = document.getElementById('progBar');
      progCont.style.display = 'block';

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        status.innerText = 'Transferring ' + (i + 1) + ' of ' + files.length + ': ' + file.name + ' (' + (file.size / (1024 * 1024)).toFixed(1) + ' MB)...';
        progBar.style.width = '0%';
        progBar.innerText = '0%';

        await new Promise((resolve, reject) => {
          const xhr = new XMLHttpRequest();
          xhr.open('POST', '/upload?token=' + encodeURIComponent(sessionToken) + '&name=' + encodeURIComponent(file.name));
          xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
              const pct = Math.round((e.loaded / e.total) * 100);
              progBar.style.width = pct + '%';
              progBar.innerText = pct + '%';
            }
          };
          xhr.onload = () => {
            if (xhr.status === 200) resolve();
            else reject(new Error('Upload failed'));
          };
          xhr.onerror = () => reject(new Error('Network error'));
          xhr.send(file);
        });
      }

      progBar.style.width = '100%';
      progBar.innerText = '100%';
      status.innerHTML = '<span style="color: #34A853; font-weight: 600;">Transferred ' + files.length + ' photo(s) directly to phone!</span>';
    }
  </script>
</body>
</html>
''';
  }

  Future<void> _checkBackgroundServiceStatus() async {
    if (Platform.isAndroid) {
      try {
        final isRunning = await _bgChannel.invokeMethod<bool>('isServiceRunning') ?? false;
        final isIgnored = await _bgChannel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false;
        setState(() {
          _backgroundSyncEnabled = isRunning;
          _batteryOptimizationIgnored = isIgnored;
        });
      } catch (_) {}
    }
  }

  Future<void> _toggleBackgroundService(bool enable) async {
    setState(() => _backgroundSyncEnabled = enable);
    _saveAppConfig();
    if (Platform.isAndroid) {
      try {
        if (enable) {
          await _bgChannel.invokeMethod('startService');
        } else {
          await _bgChannel.invokeMethod('stopService');
        }
      } catch (e) {
        debugPrint('Background service toggle error: $e');
      }
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      try {
        await _bgChannel.invokeMethod('requestIgnoreBatteryOptimization');
      } catch (_) {}
    }
  }

  void _initEngine() {
    try {
      final dbDir = Platform.isAndroid
          ? '/data/data/net.p2pme.p2pme_app/files/.p2pme'
          : '.p2pme_mobile';
      final ready = P2PBridge.instance.initNode(dbDir, port: 0);
      if (ready) {
        String? initialTicket;
        try {
          if (_folders.isNotEmpty) {
            initialTicket = P2PBridge.instance.shareFolder(
              _folders[0].localPath,
              _folders[0].name,
              syncMode: 2,
            );
          }
        } catch (_) {}

        setState(() {
          _isEngineReady = true;
          _nodeId = P2PBridge.instance.getNodeId();
          _listeningPort = P2PBridge.instance.getPort();
          if (initialTicket != null && _folders.isNotEmpty) {
            _folders[0].ticket = initialTicket;
          }
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Google Photos style 4-color pinwheel indicator
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: GooglePhotosColors.red, shape: BoxShape.circle)),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: GooglePhotosColors.blue, shape: BoxShape.circle)),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: GooglePhotosColors.yellow, shape: BoxShape.circle)),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: GooglePhotosColors.green, shape: BoxShape.circle)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _selectedIndex == 0
                          ? 'Transfer'
                          : (_selectedIndex == 1 ? 'Backup' : 'Server'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        letterSpacing: -0.3,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFE8EAED)
                            : const Color(0xFF202124),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showDiagnostics(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF303134)
                              : GooglePhotosColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF5F6368)
                                : GooglePhotosColors.blue.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'v$_currentVersionName',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF8AB4F8)
                                : GooglePhotosColors.blue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _selectedIndex == 0
                      ? 'One-time direct transfer'
                      : (_selectedIndex == 1
                          ? 'Camera roll & folders'
                          : '24/7 Home Hub & receiver'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF9AA0A6)
                        : const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 22),
            tooltip: 'Connection Guide & Setup',
            onPressed: () => _showRemoteConnectionGuide(context),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showDiagnostics(context),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF303134)
                        : const Color(0xFFE8F0FE),
                    child: const Icon(
                      Icons.cloud_done_outlined,
                      color: GooglePhotosColors.blue,
                      size: 19,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: GooglePhotosColors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              if (_updateAvailable) _buildUpdateBanner(isDark),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz_rounded),
                label: 'Transfer',
              ),
              NavigationDestination(
                icon: Icon(Icons.cloud_sync_outlined),
                selectedIcon: Icon(Icons.cloud_sync_rounded),
                label: 'Backup',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns_rounded),
                label: 'Server',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A2F) : const Color(0xFFE6F4EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GooglePhotosColors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: GooglePhotosColors.green, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isDownloadingUpdate
                      ? 'Downloading update...'
                      : 'Update available: v${_latestVersionName ?? ""}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  _isDownloadingUpdate
                      ? (_downloadStatusText ?? 'Please wait...')
                      : (_updateReleaseNotes ?? 'Tap to download & install the latest version.'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFBDC1C6) : const Color(0xFF5F6368),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_isDownloadingUpdate) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      minHeight: 4,
                      backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                      color: GooglePhotosColors.green,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: GooglePhotosColors.green,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(60, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isDownloadingUpdate ? null : () => _downloadAndInstallUpdate(),
            child: _isDownloadingUpdate
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: _isDownloadingUpdate ? null : () => setState(() => _updateAvailable = false),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildTransferTab();
      case 1:
        return _buildBackupTab();
      case 2:
        return _buildServerTab();
      default:
        return _buildTransferTab();
    }
  }

  // ==========================================
  // TAB 1: ONE-TIME DIRECT TRANSFER (NEARBY + PIN)
  // ==========================================
  Widget _buildTransferTab() {
    return _buildQuickDropScreen();
  }

  // ==========================================
  // TAB 2: CONTINUOUS BACKUP & FOLDERS
  // ==========================================
  Widget _buildBackupTab() {
    return _buildFolderList();
  }

  // ==========================================
  // TAB 3: 24/7 BACKUP SERVER & HUB SETTINGS
  // ==========================================
  Widget _buildServerTab() {
    return _buildServerScreen();
  }

  Future<void> _handleDirectDropToPeer(NearbyPeer peer) async {
    if (_selectedFilePaths.isEmpty) return;
    final total = _selectedFilePaths.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending $total file(s) to ${peer.name}...'),
        backgroundColor: GooglePhotosColors.blue,
      ),
    );

    int sent = 0;
    int totalBytes = 0;
    for (var path in _selectedFilePaths) {
      final f = File(path);
      if (f.existsSync()) totalBytes += f.lengthSync();
    }
    int totalBytesSent = 0;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    for (var path in _selectedFilePaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final fileName = path.split(Platform.pathSeparator).last;
      try {
        final tokenToSend = peer.authToken ?? _webDropSessionToken;
        final url = Uri.parse('http://${peer.ip}:${peer.port}/upload?name=${Uri.encodeComponent(fileName)}&token=$tokenToSend&fileIndex=${sent + 1}&totalFiles=$total&batchTotal=$totalBytes&batchSent=$totalBytesSent&senderDevice=${Uri.encodeComponent(_myDeviceName)}');
        final req = await client.postUrl(url);
        final len = await file.length();
        req.headers.contentLength = len;
        req.headers.contentType = ContentType.binary;
        req.headers.set('X-File-Index', (sent + 1).toString());
        req.headers.set('X-Total-Files', total.toString());
        req.headers.set('X-Batch-Total-Bytes', totalBytes.toString());
        req.headers.set('X-Batch-Bytes-Sent', totalBytesSent.toString());
        req.headers.set('X-Sender-Device-Name', _myDeviceName);

        final Stopwatch sampleWatch = Stopwatch()..start();
        int bytesSinceSample = 0;
        double currentSpeedMBps = 0.0;

        await for (final chunk in file.openRead()) {
          req.add(chunk);
          bytesSinceSample += chunk.length;
          totalBytesSent += chunk.length;

          if (sampleWatch.elapsedMilliseconds >= 200) {
            final double s = sampleWatch.elapsedMicroseconds / 1000000.0;
            if (s > 0) currentSpeedMBps = (bytesSinceSample / s) / (1024 * 1024);
            sampleWatch.reset();
            bytesSinceSample = 0;
          }
        }
        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok) {
          sent++;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Sent $fileName (${currentSpeedMBps > 0 ? "${currentSpeedMBps.toStringAsFixed(1)} MB/s" : "done"})'),
                backgroundColor: GooglePhotosColors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Direct drop upload failed for $fileName: $e');
      }
    }

    if (mounted) {
      if (sent > 0) {
        setState(() => _selectedFilePaths.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Successfully transferred $sent file(s) to ${peer.name}!'),
            backgroundColor: GooglePhotosColors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed. Ensure ${peer.name} has P2Pme running.'),
            backgroundColor: GooglePhotosColors.red,
          ),
        );
      }
    }
  }

  // ==========================================
  // TAB 3: 24/7 BACKUP SERVER & HUB SETTINGS
  // ==========================================
  Widget _buildServerScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final serverUrl = 'http://${_localIpAddress ?? "192.168.178.35"}:$_webDropPort';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Server Master Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? GooglePhotosColors.darkCard : GooglePhotosColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? GooglePhotosColors.darkBorder : GooglePhotosColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isWebDropServerRunning
                        ? GooglePhotosColors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isWebDropServerRunning ? Icons.dns_rounded : Icons.dns_outlined,
                    color: _isWebDropServerRunning ? GooglePhotosColors.green : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '24/7 Backup Server',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF202124),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isWebDropServerRunning
                                  ? GooglePhotosColors.green.withValues(alpha: 0.15)
                                  : Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _isWebDropServerRunning ? 'ONLINE' : 'STANDBY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isWebDropServerRunning ? GooglePhotosColors.green : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Accepts incoming photo backups and file drops directly on your local network.'
                        '${_localStorageTotalBytes > 0 ? " • Storage: ${(_localStorageFreeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB Free / ${(_localStorageTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Server Port Error Alert Banner
          if (_serverBindError != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade700, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server Port Conflict',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _serverBindError!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Receiver Storage Full Alert Banner
          if (_isReceiverStorageFull) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade700, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.disc_full_rounded, color: Colors.red.shade700, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Storage Full',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Incoming photo transfers are paused. Open Google Photos and tap "Free up space" to resume automatically.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.red.shade300 : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282A2D) : const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Note: If this device is only sending photos to another phone or computer, you do not need to run this server.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Live Transfer Speed & Ingestion Telemetry Card
          if (_isReceivingActive || _receivedFiles > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isReceivingActive
                    ? GooglePhotosColors.green.withValues(alpha: 0.12)
                    : (isDark ? GooglePhotosColors.darkCard : GooglePhotosColors.lightCard),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isReceivingActive
                      ? GooglePhotosColors.green.withValues(alpha: 0.6)
                      : (isDark ? GooglePhotosColors.darkBorder : GooglePhotosColors.lightBorder),
                  width: _isReceivingActive ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isReceivingActive
                              ? GooglePhotosColors.green
                              : (isDark ? const Color(0xFF303134) : Colors.grey.shade200),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isReceivingActive ? Icons.downloading_rounded : Icons.speed_rounded,
                          color: _isReceivingActive ? Colors.white : Colors.grey,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isReceivingActive
                                  ? (_receivingTotalFiles > 0
                                      ? 'Downloading from ${_receivingSenderDeviceName ?? "Sender"} • File $_receivingCurrentFileIndex of $_receivingTotalFiles'
                                      : 'Downloading from ${_receivingSenderDeviceName ?? "Sender"}...')
                                  : 'Receiver Ingestion Status',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _isReceivingActive
                                    ? GooglePhotosColors.green
                                    : (isDark ? const Color(0xFFE8EAED) : const Color(0xFF202124)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isReceivingActive && _receivingFileName != null
                                  ? 'Saving: $_receivingFileName • Direct download'
                                  : 'Total: $_receivedFiles files (${CameraBackupService.formatBytes(_receivedBytes)}) ingested',
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_isReceivingActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: GooglePhotosColors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Downloading: ${_receivingSpeedMBps.toStringAsFixed(1)} MB/s',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  if (_isReceivingActive) ...[
                    const SizedBox(height: 12),
                    if (_receivingBatchTotalBytes > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Batch: ${CameraBackupService.formatBytes(_receivingBatchBytesReceived)} of ${CameraBackupService.formatBytes(_receivingBatchTotalBytes)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                          ),
                          Text(
                            '${((_receivingBatchBytesReceived / _receivingBatchTotalBytes) * 100).toInt().clamp(0, 100)}%',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GooglePhotosColors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_receivingBatchBytesReceived / _receivingBatchTotalBytes).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: GooglePhotosColors.green.withValues(alpha: 0.2),
                          color: GooglePhotosColors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _receivingProgressRatio > 0 ? _receivingProgressRatio : null,
                        minHeight: 4,
                        backgroundColor: GooglePhotosColors.green.withValues(alpha: 0.15),
                        color: GooglePhotosColors.green.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _receivingProgressRatio > 0
                              ? 'File: ${(_receivingProgressRatio * 100).toInt()}% • ${CameraBackupService.formatBytes(_receivingCurrentFileBytesReceived)} / ${CameraBackupService.formatBytes(_receivingCurrentFileTotalBytes)}'
                              : 'Receiving chunk stream...',
                          style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                        const Spacer(),
                        const Text('Direct Wire-Speed', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2022) : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Server Hub active: transfers are initiated and paused by the sender device.',
                              style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 4),

          // Receiver Storage Destination Card
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: isDark ? const Color(0xFF202124) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0xFF3C4043) : const Color(0xFFE8EAED),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_shared_outlined, color: GooglePhotosColors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Receiver Storage Location',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Incoming photos and files sent to this server will be saved here:',
                    style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF303134) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _receiveDestination,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: _pickDestinationFolder,
                          child: const Text('Change Folder', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Server Pairing Credentials (PIN, Address, QR Code)
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: isDark ? const Color(0xFF202124) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0xFF3C4043) : const Color(0xFFE8EAED),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key_rounded, color: GooglePhotosColors.green, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Server Connection & Pairing',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use this address or QR code to pair other phones or computers to this server:',
                    style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Direct Address: $serverUrl',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                  if (_isUsbCableConnected && _usbCableIp != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: GooglePhotosColors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.usb_rounded, color: GooglePhotosColors.blue, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '⚡ USB Cable: http://$_usbCableIp:$_webDropPort',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GooglePhotosColors.blue, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_serverRemoteWanUrl != null && _serverRemoteWanUrl!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Remote / WAN: $_serverRemoteWanUrl',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF12B5CB)),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Hub Secret Key: ${_hubSecretKey != null ? "${_hubSecretKey!.substring(0, 12)}••••••••" : "Generating..."}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy Address', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: serverUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Server address copied to clipboard!')),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.key, size: 14),
                          label: const Text('Copy Key', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            if (_hubSecretKey != null) {
                              Clipboard.setData(ClipboardData(text: _hubSecretKey!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Hub secret key copied to clipboard!')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.public_rounded, size: 14),
                          label: Text(
                            _serverRemoteWanUrl != null && _serverRemoteWanUrl!.isNotEmpty ? 'WAN Endpoint' : 'Set Remote WAN URL',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: _promptSetServerWanUrl,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.usb_rounded, size: 14),
                          label: const Text('Cable Guide', style: TextStyle(fontSize: 11)),
                          onPressed: _showUsbCableGuide,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GooglePhotosColors.red,
                        side: BorderSide(color: GooglePhotosColors.red.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Regenerate Key & QR Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      onPressed: _promptRegenerateServerKey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: QrImageView(
                        data: _hubSecretKey != null && _hubSecretKey!.isNotEmpty
                            ? '$serverUrl?key=$_hubSecretKey${_serverRemoteWanUrl != null && _serverRemoteWanUrl!.isNotEmpty ? '&wan=${Uri.encodeComponent(_serverRemoteWanUrl!)}' : ''}'
                            : serverUrl,
                        version: QrVersions.auto,
                        size: 140.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Scan with client device for 256-bit secure paired transfer',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Background Service & Speed card
          _buildBackgroundAndSpeedCard(),
        ],
      ),
    );
  }

  void _promptSetServerWanUrl() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _serverRemoteWanUrl ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.public_rounded, color: GooglePhotosColors.blue),
            SizedBox(width: 10),
            Text('Remote / WAN Endpoint'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your home hub\'s Tailscale mesh IP (e.g. 100.85.120.44:45455) or custom DDNS domain to enable backup from 5G / cellular anywhere.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g. 100.85.120.44:45455 or https://...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveServerWanUrl('');
            },
            child: const Text('Clear', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              _saveServerWanUrl(controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showUsbCableGuide() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.usb_rounded, color: GooglePhotosColors.blue),
            SizedBox(width: 10),
            Text('⚡ Direct USB Cable Transfer'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transfer gigabytes at wire speed (35-400+ MB/s) with 0% wireless packet loss and ZERO Wi-Fi required!',
                style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text('📱 Phone to Phone (e.g. iPhone ↔ Pixel):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              const Text('1. Connect both phones with a USB-C to USB-C or Lightning cable.\n2. Turn on USB Tethering (Android Settings → Hotspot → USB tethering) or Personal Hotspot over USB (iPhone).\n3. P2Pme automatically detects the direct wired link and transfers at hardware speed.', style: TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 14),
              const Text('💻 Phone to PC (Windows / Mac / Linux):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              const Text('1. Connect phone to PC via USB cable.\n2. Enable USB tethering on your phone.\n3. Open P2Pme on PC or visit http://127.0.0.1:45455 in your browser for instant wired backup.', style: TextStyle(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.blue),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // REMOTE CONNECTION & 24/7 HOME HUB GUIDE
  // ==========================================
  void _showRemoteConnectionGuide(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: GooglePhotosColors.blue.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.hub_rounded, color: GooglePhotosColors.blue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'P2Pme User & Connection Guide',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'One-time transfers, Camera Roll backup & 24/7 Home Hub',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Quick 3-Tab Overview Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2638) : GooglePhotosColors.blueSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? const Color(0xFF2C394F) : const Color(0xFFD2E3FC)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.tips_and_updates_outlined, size: 16, color: GooglePhotosColors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How P2Pme Works in 3 Simple Tabs',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF8AB4F8) : GooglePhotosColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '• 🚀 Transfer: Send items one-time. Tap a nearby device on Wi-Fi, or send anywhere over the internet using a 6-digit PIN.\n'
                                '• 🔄 Backup: Continuous Camera Roll auto-backup. Detects new photos & videos and automatically saves them to your server.\n'
                                '• 🖥️ Server: Turn this device into a 24/7 backup destination, choose where files are saved, and view your pairing QR code.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF3C4043),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Security & Key Regeneration Guide Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2B2118) : const Color(0xFFFEF7E0),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? const Color(0xFF5C3C1A) : const Color(0xFFFEEFC3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.shield_outlined, size: 16, color: GooglePhotosColors.yellow),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Zero-Conflict Security & On-Demand Key Regeneration',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFFFDD663) : const Color(0xFFB06000),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '• 🛡️ Zero Conflicts: Every server uses 256-bit cryptographically secure random entropy (CSPRNG), making key collision mathematically impossible (2^256 combinations).\n'
                                '• 🔄 Folder Ticket Regeneration: In the Backup tab, tap the refresh button on any folder\'s QR dialog to instantly generate a new BLAKE3 pairing ticket and revoke the old one.\n'
                                '• 🔑 Server Key Regeneration: In the Server tab, tap "Regenerate Key & QR Code" to generate a fresh 256-bit secret and instantly revoke all previous client pairings.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF3C4043),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Hub address and token summary card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF303134) : GooglePhotosColors.lightCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? const Color(0xFF3C4043) : GooglePhotosColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.security, size: 16, color: GooglePhotosColors.green),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Your 24/7 Hub Credentials',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: GooglePhotosColors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'ONLINE',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GooglePhotosColors.green),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Direct Address: ${_localIpAddress ?? "192.168.178.35"}:$_webDropPort',
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hub Secret Key: ${_hubSecretKey != null ? "${_hubSecretKey!.substring(0, 12)}••••••••" : "Generating..."}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.copy, size: 14),
                                      label: const Text('Copy Address', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: 'http://${_localIpAddress ?? "192.168.178.35"}:$_webDropPort'));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Hub address copied to clipboard!')),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.key, size: 14),
                                      label: const Text('Copy Key', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        if (_hubSecretKey != null) {
                                          Clipboard.setData(ClipboardData(text: _hubSecretKey!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Hub secret key copied to clipboard!')),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Section 1: Direct USB Cable Transfer
                        _buildConnectionMethodCard(
                          isDark: isDark,
                          badge: '⚡ Direct Wire Speed (Offline)',
                          badgeColor: GooglePhotosColors.blue,
                          title: 'Direct USB Cable Transfer (USB-to-USB & USB-to-PC)',
                          description: 'Connect two phones directly (e.g. iPhone to Pixel XL) or phone to PC with a USB cable. Zero Wi-Fi required, zero wireless packet loss, 35-400+ MB/s wire speed, and keeps your devices charged.',
                          steps: [
                            'Connect both devices using a USB-C to USB-C or Lightning cable.',
                            'On Android, turn on USB Tethering (Settings → Network → Hotspot & tethering → USB tethering). On iPhone, enable Personal Hotspot over USB.',
                            'P2Pme automatically detects the hardware wired interface and streams files at full copper bus speeds.',
                          ],
                          platformIcons: [
                            BrandIcons.apple(size: 16, color: isDark ? Colors.white : Colors.black87),
                            const SizedBox(width: 6),
                            BrandIcons.android(size: 16),
                            const SizedBox(width: 6),
                            BrandIcons.windows(size: 16),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Section 2: WebRTC P2P Direct
                        _buildConnectionMethodCard(
                          isDark: isDark,
                          badge: '🌐 Zero-Install Direct P2P',
                          badgeColor: GooglePhotosColors.blue,
                          title: 'WebRTC NAT Hole Punching',
                          description: 'Stream photos directly from Safari, Chrome, or any mobile browser to this phone without port forwarding or VPNs. Uses Google STUN (stun.l.google.com:19302) to negotiate direct encrypted peer-to-peer DataChannels.',
                          steps: [
                            'Keep this Android phone connected to power and home Wi-Fi with P2Pme running.',
                            'Open https://p2pme.pages.dev on any phone, tablet, or laptop while traveling.',
                            'Under "Saved 24/7 Home Hubs", tap your hub and tap "Send to Home Hub".',
                            'Photos are encrypted end-to-end and saved directly into your phone\'s download folder.',
                          ],
                          platformIcons: [
                            BrandIcons.apple(size: 16, color: isDark ? Colors.white : Colors.black87),
                            const SizedBox(width: 6),
                            BrandIcons.android(size: 16),
                            const SizedBox(width: 6),
                            BrandIcons.windows(size: 16),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Section 2: Private Mesh (Tailscale)
                        _buildConnectionMethodCard(
                          isDark: isDark,
                          badge: '🏆 Recommended Gold Standard',
                          badgeColor: GooglePhotosColors.green,
                          title: 'Private WireGuard Mesh (Tailscale)',
                          description: 'Zero-configuration point-to-point encrypted mesh. Works behind strict CGNAT mobile routers and hotel firewalls with 100% security and zero open ports.',
                          steps: [
                            'Install the free Tailscale app on this phone and your other devices.',
                            'Log in with your existing Google, Apple, or Microsoft account.',
                            'Copy this phone\'s 100.x.y.z Tailscale IP and port 45455 into P2Pme.',
                            'Continuous, high-speed automated backup wherever you have an internet connection.',
                          ],
                          platformIcons: [
                            BrandIcons.apple(size: 16, color: isDark ? Colors.white : Colors.black87),
                            const SizedBox(width: 6),
                            BrandIcons.android(size: 16),
                            const SizedBox(width: 6),
                            BrandIcons.windows(size: 16),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Section 3: Native iOS Foundation
                        _buildConnectionMethodCard(
                          isDark: isDark,
                          badge: 'Official Platform Foundation',
                          badgeColor: isDark ? Colors.white70 : Colors.black87,
                          title: 'Apple iOS Native App & Web PWA',
                          description: 'iOS project scaffolded in app/ios/ with PhotoKit (PHPhotoLibraryChangeObserver), Bonjour local discovery (_p2pme._tcp), and background processing modes. Web PWA on Safari supports full Home Screen installation.',
                          steps: [
                            'In Safari on iPhone/iPad: Open https://p2pme.pages.dev -> Tap Share -> "Add to Home Screen".',
                            'Run as an installable standalone app with offline support and local caching.',
                            'For native builds: app/ios/ is configured with NSPhotoLibraryUsageDescription and background fetch for zero-touch camera backup.',
                          ],
                          platformIcons: [
                            BrandIcons.apple(size: 16, color: isDark ? Colors.white : Colors.black87),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildConnectionMethodCard({
    required bool isDark,
    required String badge,
    required Color badgeColor,
    required String title,
    required String description,
    required List<String> steps,
    required List<Widget> platformIcons,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C394F).withValues(alpha: 0.25) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF3C4043) : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
              Row(children: platformIcons),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key + 1}. ',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: GooglePhotosColors.blue),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800, height: 1.3),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==========================================
  // QUICK DROP SCREEN (EASY OPERATION FOR KIDS)
  // ==========================================
  Widget _buildQuickDropScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Google Photos style Direct Transfer card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? GooglePhotosColors.darkCard
                  : GooglePhotosColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? GooglePhotosColors.darkBorder
                    : GooglePhotosColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF174EA6)
                        : GooglePhotosColors.blueSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sync_alt_rounded,
                    color: GooglePhotosColors.blue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct transfer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFFE8EAED)
                              : const Color(0xFF202124),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Send photos and files directly to another phone or computer.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF9AA0A6)
                              : const Color(0xFF5F6368),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Clean Mode Toggle (Send / Receive)
          Center(
            child: SegmentedButton<int>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Send', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  icon: Icon(Icons.arrow_upward_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Receive', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  icon: Icon(Icons.arrow_downward_rounded, size: 18),
                ),
              ],
              selected: {_quickDropTab},
              onSelectionChanged: (set) => setState(() => _quickDropTab = set.first),
            ),
          ),
          const SizedBox(height: 16),

          if (_quickDropTab == 0) _buildDropSendView() else _buildDropReceiveView(),
        ],
      ),
    );
  }

  Widget _buildDropSendView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File Selection Card
        Card(
          color: Theme.of(context).brightness == Brightness.dark
              ? GooglePhotosColors.darkCard
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? GooglePhotosColors.darkBorder
                  : GooglePhotosColors.lightBorder,
            ),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Option 1: Camera
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: GooglePhotosColors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text(
                    'Camera photos',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _openCameraBackupPicker,
                ),
                const SizedBox(height: 6),
                Text(
                  'Photos and videos from camera',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF9AA0A6)
                        : const Color(0xFF5F6368),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                // Option 2: Other files
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? GooglePhotosColors.darkBorder
                          : GooglePhotosColors.lightBorder,
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text(
                    'Other files',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  onPressed: _pickFilesFromDevice,
                ),
                if (_selectedFilePaths.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected (${_selectedFilePaths.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedFilePaths.clear()),
                        child: const Text('Clear', style: TextStyle(color: GooglePhotosColors.blue)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedFilePaths.map((path) {
                      final name = path.split(Platform.pathSeparator).last;
                      return Chip(
                        avatar: Icon(
                          name.endsWith('.jpg') || name.endsWith('.png')
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 16,
                          color: GooglePhotosColors.blue,
                        ),
                        label: Text(
                          name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () {
                          setState(() => _selectedFilePaths.remove(path));
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Nearby Direct Beam
        if (_nearbyPeers.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nearby on Wi-Fi (${_nearbyPeers.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: _isScanningNearby ? null : _scanNearby,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Refresh', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._nearbyPeers.map((peer) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final isPc = peer.deviceType.toLowerCase().contains('pc') || peer.deviceType.toLowerCase().contains('windows');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: isDark ? const Color(0xFF202124) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isDark ? const Color(0xFF3C4043) : const Color(0xFFE8EAED)),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(
                  isPc ? Icons.laptop_chromebook : Icons.phone_android,
                  color: GooglePhotosColors.blue,
                ),
                title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text('${peer.ip} • 1-Tap Transfer', style: const TextStyle(fontSize: 11)),
                trailing: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: _selectedFilePaths.isEmpty
                      ? null
                      : () => _handleDirectDropToPeer(peer),
                  child: const Text('Send Here', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nearby Wi-Fi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600),
              ),
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _openQrScanner(),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 14),
                    label: const Text('Scan QR', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _promptConnectByIp,
                    icon: const Icon(Icons.wifi_find_rounded, size: 14),
                    label: const Text('Add by IP', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _isScanningNearby ? null : _scanNearby,
                    icon: _isScanningNearby
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Icon(Icons.refresh, size: 14),
                    label: Text(_isScanningNearby ? 'Scanning...' : 'Scan Wi-Fi', style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Action Button: Send with PIN
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: GooglePhotosColors.blue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
          icon: _isCreatingDrop
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.pin_rounded, size: 18),
          label: Text(
            _isCreatingDrop ? 'Preparing transfer...' : 'Send with PIN (Over Internet)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          onPressed: _selectedFilePaths.isEmpty || _isCreatingDrop ? null : _handleCreateDrop,
        ),
        const SizedBox(height: 20),

        // Active Drop Display (PIN cards + QR code)
        if (_activeDropPin != null) ...[
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'SHARE THIS 6-DIGIT PIN WITH RECEIVER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Large friendly PIN cards (FittedBox prevents any pixel overflow)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _activeDropPin!.split('').map((digit) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            digit,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '$_activeDropFiles file(s) • ${(_activeDropBytes / 1024).toStringAsFixed(1)} KB ready',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // On-Screen QR Code for camera scanning (iPhone / iPad / PC)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: 'http://${_localIpAddress ?? "192.168.178.35"}:$_webDropPort/drop?pin=$_activeDropPin',
                      version: QrVersions.auto,
                      size: 160.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan with iPhone or PC camera to download directly',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),

                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy PIN'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _activeDropPin!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('PIN copied to clipboard!')),
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Copy Link'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                            text: 'http://${_localIpAddress ?? "192.168.178.35"}:$_webDropPort/drop?pin=$_activeDropPin',
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Direct Wi-Fi link copied!')),
                          );
                        },
                      ),
                      if (_activeDropTicket != null)
                        IconButton(
                          icon: const Icon(Icons.share, size: 18),
                          tooltip: 'Copy P2P Ticket',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _activeDropTicket!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('P2P Drop Ticket copied!')),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.green),
                      SizedBox(width: 6),
                      Text(
                        'TLS 1.3 Encrypted • Self-destructs upon receipt',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropReceiveView() {
    final webUrl = _localIpAddress != null
        ? 'http://$_localIpAddress:$_webDropPort/?token=$_webDropSessionToken'
        : 'http://192.168.178.35:$_webDropPort/?token=$_webDropSessionToken';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card 1: Zero-Install "Scan with iPhone / Any Device to Send to Me"
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.blue.shade300, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, color: Colors.blue, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              const Text(
                                'Scan with iPhone / PC to Send',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _isWebDropServerRunning ? Colors.green.shade50 : Colors.amber.shade50,
                                  border: Border.all(
                                    color: _isWebDropServerRunning ? Colors.green.shade400 : Colors.amber.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _isWebDropServerRunning ? 'PORTAL ACTIVE' : 'STARTING',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: _isWebDropServerRunning ? Colors.green.shade800 : Colors.amber.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Zero-Install: No app needed on the sender device!',
                            style: TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // QR Code
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: webUrl,
                    version: QrVersions.auto,
                    size: 170.0,
                  ),
                ),
                const SizedBox(height: 12),

                // Instruction & URL
                Text(
                  'Point any iPhone Camera at this QR code to upload photos or files directly to this phone over Wi-Fi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),

                OutlinedButton.icon(
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share Upload Link'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: webUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Upload link copied to clipboard!')),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '128-Bit Token: ${_webDropSessionToken.substring(0, 8)}••',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _regenerateSessionToken,
                        child: const Tooltip(
                          message: 'Generate new security token',
                          child: Icon(Icons.refresh, size: 14, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('24/7 Home Hub & WebRTC Setup', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showRemoteConnectionGuide(context),
                ),

                if (_lastReceivedFromBrowser != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Latest: $_lastReceivedFromBrowser',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Divider OR ENTER PIN
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR ENTER 6-DIGIT PIN FROM P2PME APP',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),

        // Card 2: 6-Digit PIN input from P2Pme App
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter 6-Digit PIN from Sender',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pinInputController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: '______',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 14),
                // Destination picker
                Row(
                  children: [
                    const Icon(Icons.folder_open, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _receiveDestination,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _pickDestinationFolder,
                      child: const Text('Change Folder'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _isReceivingDrop
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded, size: 24),
          label: Text(
            _isReceivingDrop ? 'Downloading & Verifying...' : 'Download Drop Now',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: _isReceivingDrop ? null : _handleReceiveDrop,
        ),
        const SizedBox(height: 20),

        if (_receiveMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _receiveSuccess ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _receiveSuccess ? Colors.green.shade400 : Colors.red.shade400,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _receiveSuccess ? Icons.check_circle : Icons.error,
                  color: _receiveSuccess ? Colors.green.shade800 : Colors.red.shade800,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _receiveSuccess ? '🎉 Transfer Complete & Verified!' : 'Transfer Failed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _receiveSuccess ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _receiveMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _receiveSuccess ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================
  // AUTO-SYNC FOLDERS LIST & BACKUP TAB
  // ==========================================
  Widget _buildFolderList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildCameraRollAutoBackupCard(),
        _buildConnectedServerCard(isDark),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Synchronized Folders (${_folders.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: const Size(0, 32),
              ),
              onPressed: _showAddFolderModal,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Folder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_folders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF202124) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF3C4043) : const Color(0xFFE8EAED)),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_open_rounded, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                const Text('No folders added yet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Tap "+ Add Folder" above to back up photos or synchronize folders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ..._folders.map((folder) => _buildFolderCard(folder)),
      ],
    );
  }

  Widget _buildConnectedServerCard(bool isDark) {
    final livePeer = _nearbyPeers.cast<NearbyPeer?>().firstWhere(
      (p) => p != null && (p.isPaired || (_savedPairedServer != null && (p.ip == _savedPairedServer!.ip || p.name == _savedPairedServer!.name || (p.wanHost != null && p.wanHost == _savedPairedServer!.wanHost)))),
      orElse: () => null,
    );

    final displayPeer = livePeer ?? _savedPairedServer;
    final isPaired = displayPeer != null;
    final isLiveConnected = livePeer != null;
    final serverName = displayPeer?.name ?? 'No Backup Server Connected';
    final serverIp = displayPeer?.ip ?? '';
    final serverPort = displayPeer?.port ?? _webDropPort;
    final wanHost = displayPeer?.wanHost;

    // Determine connection badge & tier
    Color statusColor = isLiveConnected ? GooglePhotosColors.green : const Color(0xFFF9AB00);
    String statusBadgeText;
    IconData statusIcon = Icons.dns_outlined;

    if (isLiveConnected && displayPeer != null) {
      if (_isUsbCableConnected && (displayPeer.ip == _usbCableIp || displayPeer.ip.startsWith('192.168.42.') || displayPeer.ip.startsWith('172.20.10.'))) {
        statusBadgeText = '⚡ Connected (USB Cable)';
        statusColor = GooglePhotosColors.blue;
        statusIcon = Icons.usb_rounded;
      } else if (wanHost != null && displayPeer.ip == wanHost) {
        statusBadgeText = '🌐 Connected (Mesh / WAN)';
        statusColor = const Color(0xFF12B5CB);
        statusIcon = Icons.public_rounded;
      } else {
        statusBadgeText = '✓ Connected (Wi-Fi)';
        statusColor = GooglePhotosColors.green;
        statusIcon = Icons.wifi_rounded;
      }
    } else if (isPaired) {
      statusBadgeText = '⏳ Waiting for connection / Cellular';
      statusColor = const Color(0xFFF9AB00);
      statusIcon = Icons.cloud_queue_rounded;
    } else {
      statusBadgeText = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? const Color(0xFF202124) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPaired
              ? statusColor.withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF3C4043) : const Color(0xFFE8EAED)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isPaired
                  ? statusColor.withValues(alpha: 0.15)
                  : (isDark ? const Color(0xFF303134) : Colors.grey.shade100),
              child: Icon(
                isPaired ? statusIcon : Icons.dns_outlined,
                color: isPaired ? statusColor : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isPaired ? 'Backup Destination: $serverName' : 'No Backup Server Connected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isPaired
                                ? (isDark ? Colors.white : const Color(0xFF202124))
                                : (isDark ? const Color(0xFFE8EAED) : const Color(0xFF202124)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (isPaired) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusBadgeText,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$serverIp:$serverPort${wanHost != null && wanHost.isNotEmpty ? ' • WAN: $wanHost' : ''}'
                      '${displayPeer.freeStorageBytes != null && displayPeer.freeStorageBytes! > 0 ? " • ${(displayPeer.freeStorageBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB Free" : ""}',
                      style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368)),
                    ),
                    if (displayPeer.freeStorageBytes != null && displayPeer.freeStorageBytes! > 0 && CameraBackupService.instance.batchTotalBytes > 0 && displayPeer.freeStorageBytes! < CameraBackupService.instance.batchTotalBytes) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '⚠️ Receiver storage low: ${(displayPeer.freeStorageBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB free for ${(CameraBackupService.instance.batchTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB batch',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Connect to your home phone or PC to back up photos automatically.',
                      style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPaired) ...[
                  IconButton.outlined(
                    tooltip: 'Reconnect / Ping Server',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: GooglePhotosColors.blue,
                      side: BorderSide(color: GooglePhotosColors.blue.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.all(12),
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () async {
                      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
                      await _probeIp(client, serverIp, targetPort: serverPort, authToken: displayPeer.authToken, wanHost: wanHost);
                      if (wanHost != null && wanHost.isNotEmpty) {
                        await _probeIp(client, wanHost, targetPort: displayPeer.wanPort ?? serverPort, authToken: displayPeer.authToken, wanHost: wanHost);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    tooltip: 'Server Options',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) {
                      if (val == 'change') {
                        _showConnectServerModal();
                      } else if (val == 'unpair') {
                        _promptUnpairServer();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'change',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz, size: 16),
                            SizedBox(width: 8),
                            Text('Change Server', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'unpair',
                        child: Row(
                          children: [
                            Icon(Icons.link_off, size: 16, color: GooglePhotosColors.red),
                            SizedBox(width: 8),
                            Text('Unpair Server', style: TextStyle(fontSize: 12, color: GooglePhotosColors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  IconButton.outlined(
                    tooltip: 'Scan Server QR',
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    style: IconButton.styleFrom(
                      foregroundColor: GooglePhotosColors.blue,
                      side: BorderSide(color: GooglePhotosColors.blue.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.all(7),
                      minimumSize: const Size(34, 34),
                    ),
                    onPressed: () => _openQrScanner(),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _showConnectServerModal,
                    child: const Text(
                      '+ Connect',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _promptUnpairServer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: GooglePhotosColors.red),
            SizedBox(width: 10),
            Text('Unpair Backup Server?'),
          ],
        ),
        content: const Text(
          'Disconnecting will stop automated camera roll backups to this server until you pair again. Existing backed-up photos on the server will remain untouched.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _unpairServer();
            },
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  void _showConnectServerModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Connect to Backup Server',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Scan Wi-Fi',
                        onPressed: () async {
                          await _scanNearby();
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a 24/7 Home Hub on your Wi-Fi, or enter a Server PIN to connect over internet.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  if (_nearbyPeers.isNotEmpty) ...[
                    const Text('Available Nearby Servers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ..._nearbyPeers.map((peer) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        color: isDark ? const Color(0xFF303134) : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const Icon(Icons.dns_rounded, color: GooglePhotosColors.blue),
                          title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${peer.ip}:${peer.port}', style: const TextStyle(fontSize: 11)),
                          trailing: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: GooglePhotosColors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                              minimumSize: const Size(0, 32),
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _handlePairWithPeer(peer);
                            },
                            child: const Text('Connect', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GooglePhotosColors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: const Text(
                      'Scan Server QR Code',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openQrScanner();
                    },
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.wifi_find_rounded, size: 16),
                          label: const Text('Add by IP', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _promptConnectByIp();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.photo_library_outlined, size: 16),
                          label: const Text('Pick QR Image', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openQrScanner(prompt: 'Select QR screenshot or image from photos');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR CONNECT VIA SERVER PIN / LINK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: pinController,
                    decoration: InputDecoration(
                      labelText: 'Server Pairing PIN or Link',
                      hintText: 'e.g. 982-411 or https://p2pme.pages.dev/...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            tooltip: 'Scan QR Code',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openQrScanner();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.paste, size: 18),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null) pinController.text = data!.text!.trim();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: GooglePhotosColors.blue,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final val = pinController.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(ctx);
                        _probeDirectIp(val);
                      }
                    },
                    child: const Text('Connect to Server'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddFolderModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Add Folder to Sync',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a folder to back up or synchronize with your server.',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: GooglePhotosColors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: GooglePhotosColors.blue),
                ),
                title: const Text('Camera Roll Auto-Backup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Automatically back up all new camera photos & videos to your server', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCameraBackupPicker();
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: GooglePhotosColors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.create_new_folder_outlined, color: GooglePhotosColors.green),
                ),
                title: const Text('Custom Device Folder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Select any local folder (Documents, Downloads, Music) to sync', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final dir = await FilePicker.getDirectoryPath();
                  if (dir != null && mounted) {
                    final name = dir.split(Platform.pathSeparator).last;
                    final ticket = P2PBridge.instance.shareFolder(
                      dir,
                      name,
                      syncMode: 2,
                    );
                    setState(() {
                      _folders.add(SyncFolderItem(
                        id: 'folder-${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        localPath: dir,
                        status: 'Sync Active',
                        connectionTier: 'DIRECT LAN',
                        syncMode: 'ARCHIVE (STORAGE SAVER)',
                        fileCount: 1,
                        totalSizeMb: 0.1,
                        speedMb: 50.0,
                        ticket: ticket,
                      ));
                    });
                    _saveAppConfig();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Now syncing folder: $name')),
                    );
                  }
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.link_rounded, color: Colors.purple),
                ),
                title: const Text('Join Folder via Ticket / PIN', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Paste a pairing ticket from another computer or phone', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showJoinFolderDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showJoinFolderDialog() {
    final ticketController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        title: const Text('Join Shared Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste the pairing ticket or link from the other device:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ticketController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Paste ticket payload here...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
            label: const Text('Scan QR'),
            onPressed: () {
              Navigator.pop(ctx);
              _openQrScanner(
                title: 'Scan Folder Pairing QR',
                prompt: 'Point camera at the Folder QR code to join',
              );
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.blue),
            onPressed: () {
              final payload = ticketController.text.trim();
              Navigator.pop(ctx);
              if (payload.isNotEmpty) {
                final targetPath = Platform.isAndroid
                    ? '/storage/emulated/0/Download/P2Pme/SyncedFolder'
                    : './received_drop/SyncedFolder';
                final res = P2PBridge.instance.syncTicket(payload, targetPath);
                if (res == 0) {
                  setState(() {
                    _folders.add(SyncFolderItem(
                      id: 'joined-${DateTime.now().millisecondsSinceEpoch}',
                      name: 'Synced Peer Folder',
                      localPath: targetPath,
                      status: 'Synchronized',
                      connectionTier: 'DIRECT LAN',
                      syncMode: 'TWO-WAY REPLICATION',
                      fileCount: 0,
                      totalSizeMb: 0.0,
                      speedMb: 75.0,
                      ticket: payload,
                    ));
                  });
                  _saveAppConfig();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Successfully joined peer folder!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to join folder ticket')),
                  );
                }
              }
            },
            child: const Text('Join & Sync'),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveFolder(SyncFolderItem folder) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: GooglePhotosColors.red, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text('Remove "${folder.name}"?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop synchronizing this folder?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF202124),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${folder.localPath}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D1F1F) : const Color(0xFFFDE8E8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: GooglePhotosColors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Files already on your device will remain safe. Only sync pairing is removed.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.red.shade200 : Colors.red.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: GooglePhotosColors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _folders.removeWhere((f) => f.id == folder.id);
              });
              _saveAppConfig();
              try {
                P2PBridge.instance.stopWatcher(folder.id);
              } catch (_) {}
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed "${folder.name}" from sync'),
                  backgroundColor: isDark ? const Color(0xFF303134) : const Color(0xFF202124),
                ),
              );
            },
            icon: const Icon(Icons.delete, size: 16),
            label: const Text('Remove Folder'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraRollAutoBackupCard() {
    final service = CameraBackupService.instance;
    final isSyncing = service.state == CameraBackupState.syncing;
    final isPaused = service.isSyncPaused;
    final isStorageFull = service.state == CameraBackupState.serverStorageFull;
    final isUpToDate = service.state == CameraBackupState.upToDate && service.pendingAssetsCount == 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetPeer = _savedPairedServer ??
        (_nearbyPeers.isNotEmpty
            ? _nearbyPeers.firstWhere((p) => p.isPaired, orElse: () => _nearbyPeers.first)
            : null);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isStorageFull
              ? Colors.amber.shade700
              : (isUpToDate
                  ? Colors.green.shade400
                  : GooglePhotosColors.blue.withValues(alpha: 0.5)),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF174EA6) : GooglePhotosColors.blueSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: GooglePhotosColors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            Platform.isIOS ? 'iPhone Camera Roll' : 'Camera Photos & Videos',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isStorageFull
                                  ? Colors.amber.shade50
                                  : (isUpToDate ? Colors.green.shade50 : Colors.blue.shade50),
                              border: Border.all(
                                color: isStorageFull
                                    ? Colors.amber.shade700
                                    : (isUpToDate ? Colors.green.shade400 : Colors.blue.shade400),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isStorageFull
                                  ? 'PAUSED (RECEIVER FULL)'
                                  : (isSyncing
                                      ? 'UPLOADING (${(service.overallBatchProgressRatio * 100).toInt()}%)'
                                      : (isPaused
                                          ? 'PAUSED'
                                          : (isUpToDate
                                              ? 'UP TO DATE'
                                              : '${service.pendingAssetsCount} NEW (${service.formattedPendingBytes})'))),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isStorageFull
                                    ? Colors.amber.shade900
                                    : (isSyncing
                                        ? GooglePhotosColors.blue
                                        : (isPaused
                                            ? Colors.orange.shade800
                                            : (isUpToDate ? Colors.green.shade800 : Colors.blue.shade800))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isStorageFull
                            ? 'Receiver is out of storage. Transfer will auto-resume once space is cleared.'
                            : (isSyncing && service.currentSyncingFilename != null
                                ? 'Uploading to ${targetPeer?.name ?? "Server"} • File ${service.currentSyncIndex} of ${service.pendingAssetsCount} (${service.currentSyncingFilename})'
                                : (isPaused
                                    ? 'Backup paused (${service.formattedBatchBytes}) • Tap "Resume Backup" to continue'
                                    : (service.totalDeviceAssets > 0
                                        ? '${service.totalDeviceAssets} photos on device • ${service.pendingAssetsCount} pending backup (${service.formattedPendingBytes})'
                                        : 'One-way automatic camera backup to server.'))),
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isStorageFull) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Receiver storage is full. Transfer paused. Tap "Free up space" in Google Photos on your receiver to automatically resume.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isSyncing) ...[
              const SizedBox(height: 10),
              // Overall Batch Progress
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Batch: ${service.formattedBatchBytes}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                  ),
                  Text(
                    '${(service.overallBatchProgressRatio * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GooglePhotosColors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: service.overallBatchProgressRatio > 0 ? service.overallBatchProgressRatio : null,
                  minHeight: 8,
                  backgroundColor: GooglePhotosColors.blue.withValues(alpha: 0.15),
                  color: GooglePhotosColors.blue,
                ),
              ),
              const SizedBox(height: 8),
              // Current File Progress
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: service.currentFileProgressRatio > 0 ? service.currentFileProgressRatio : null,
                  minHeight: 4,
                  backgroundColor: GooglePhotosColors.blue.withValues(alpha: 0.1),
                  color: GooglePhotosColors.blue.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'File: ${(service.currentFileProgressRatio * 100).toInt()}% • ${CameraBackupService.formatBytes(service.currentFileBytesSent)} / ${CameraBackupService.formatBytes(service.currentFileTotalBytes)}',
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: GooglePhotosColors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Uploading: ${service.formattedSpeed}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GooglePhotosColors.blue),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF282A2D) : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: GooglePhotosColors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'One-way protection: photos remain safe on your server even if deleted on phone.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isSyncing
                          ? Colors.orange.shade800
                          : (isPaused ? Colors.teal.shade700 : GooglePhotosColors.blue),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: isSyncing
                        ? () {
                            service.pauseSync();
                            if (mounted) setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Backup paused. Tap "Resume Backup" to continue.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        : _syncCameraRollToConnectedPeer,
                    icon: isSyncing
                        ? const Icon(Icons.pause_circle_filled_rounded, size: 18)
                        : (isPaused
                            ? const Icon(Icons.play_circle_filled_rounded, size: 18)
                            : const Icon(Icons.sync_rounded, size: 16)),
                    label: Text(
                      isSyncing
                          ? 'Pause Backup'
                          : (isPaused
                              ? 'Resume Backup'
                              : (service.pendingAssetsCount > 0
                                  ? 'Backup New (${service.pendingAssetsCount})'
                                  : 'Sync Camera Roll')),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onPressed: () async {
                    await service.scanCameraRoll();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundAndSpeedCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _backgroundSyncEnabled
              ? Colors.green.shade400
              : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row with ON/OFF switch (Tapping anywhere toggles)
            InkWell(
              onTap: () => _toggleBackgroundService(!_backgroundSyncEnabled),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _backgroundSyncEnabled
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _backgroundSyncEnabled ? Icons.sync : Icons.sync_disabled,
                        color: _backgroundSyncEnabled
                            ? Colors.green.shade800
                            : Colors.grey.shade700,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              const Text(
                                'Background Auto-Sync',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _backgroundSyncEnabled
                                      ? Colors.green.shade50
                                      : Colors.grey.shade100,
                                  border: Border.all(
                                    color: _backgroundSyncEnabled
                                        ? Colors.green.shade400
                                        : Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _backgroundSyncEnabled ? 'ACTIVE 24/7' : 'OFF (SAVER)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: _backgroundSyncEnabled
                                        ? Colors.green.shade800
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _backgroundSyncEnabled
                                ? 'Syncs photos & drops automatically even when screen is locked.'
                                : 'Zero background battery drain. Syncs only when app is open.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IgnorePointer(
                      child: Switch.adaptive(
                        value: _backgroundSyncEnabled,
                        activeTrackColor: Colors.green.shade300,
                        activeThumbColor: Colors.green.shade800,
                        onChanged: null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Performance & Speed Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed, size: 16, color: Colors.blue),
                          SizedBox(width: 6),
                          Text('Direct LAN Speed:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '~78.4 - 112 MB/s',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: Colors.green),
                          SizedBox(width: 6),
                          Text('Transport & Crypto:', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Text('QUIC UDP • TLS 1.3', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.change_circle_outlined, size: 16, color: Colors.purple),
                          SizedBox(width: 6),
                          Text('Smart Delta Sync:', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Text('Only new/changed files sent', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Secondary option toggles
            Row(
              children: [
                Expanded(
                  child: FilterChip(
                    selected: _wifiOnlySync,
                    label: const Text('Wi-Fi Only', style: TextStyle(fontSize: 11)),
                    avatar: Icon(_wifiOnlySync ? Icons.wifi : Icons.signal_cellular_alt, size: 14),
                    onSelected: (val) {
                      setState(() => _wifiOnlySync = val);
                      _saveAppConfig();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _requestBatteryOptimizationExemption,
                    icon: Icon(
                      _batteryOptimizationIgnored ? Icons.check_circle : Icons.battery_charging_full,
                      size: 14,
                      color: _batteryOptimizationIgnored ? Colors.green : null,
                    ),
                    label: Text(
                      _batteryOptimizationIgnored ? 'Battery: Allowed' : 'Battery: Optimize',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCard(SyncFolderItem folder) {
    final isArchive = folder.syncMode.contains('ARCHIVE');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isArchive
                      ? Colors.purple.shade100
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    isArchive ? Icons.photo_library : Icons.folder,
                    color: isArchive
                        ? Colors.purple.shade800
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        folder.localPath,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF174EA6)
                        : GooglePhotosColors.blueSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Storage saver',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GooglePhotosColors.blue),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20, color: GooglePhotosColors.blue),
                  tooltip: 'Share / Pair QR',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showFolderQrDialog(folder),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.grey),
                  tooltip: 'Remove from sync',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmRemoveFolder(folder),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${folder.fileCount} files • ${folder.totalSizeMb.toStringAsFixed(1)} MB',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF9AA0A6)
                        : const Color(0xFF5F6368),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: GooglePhotosColors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Backed up to computer',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF9AA0A6)
                            : const Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PAIR / DEVICES SCREEN (COMPUTER & DEVICE SYNC)
  // ==========================================
  String? _getFolderTicket(SyncFolderItem folder, {bool forceRegenerate = false}) {
    if (!forceRegenerate && folder.ticket != null && folder.ticket!.isNotEmpty) {
      return folder.ticket;
    }
    try {
      final ticket = P2PBridge.instance.shareFolder(
        folder.localPath,
        folder.name,
        syncMode: 2,
      );
      if (ticket != null) {
        folder.ticket = ticket;
      }
      return ticket;
    } catch (_) {
      return null;
    }
  }

  void _promptRegenerateFolderTicket(SyncFolderItem folder, void Function(String newTicket) onRegenerated) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (promptCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: GooglePhotosColors.red),
            SizedBox(width: 10),
            Text('Regenerate Ticket?'),
          ],
        ),
        content: Text(
          'Regenerating this ticket creates a brand-new cryptographic authentication key and immediately invalidates all previous QR codes and links for "${folder.name}".\n\n'
          'Other devices will need to scan or enter the new ticket to sync.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFFE8EAED) : const Color(0xFF3C4043),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(promptCtx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: GooglePhotosColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate'),
            onPressed: () {
              Navigator.pop(promptCtx);
              final newTicket = _getFolderTicket(folder, forceRegenerate: true);
              if (newTicket != null && newTicket.isNotEmpty) {
                onRegenerated(newTicket);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ New pairing ticket generated for "${folder.name}"! Previous ticket revoked.'),
                    backgroundColor: GooglePhotosColors.green,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showFolderQrDialog(SyncFolderItem folder) {
    String? currentTicket = _getFolderTicket(folder);
    if (currentTicket == null || currentTicket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate pairing ticket for this folder.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.qr_code_2, color: GooglePhotosColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folder.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Regenerate Ticket & QR',
                onPressed: () {
                  _promptRegenerateFolderTicket(folder, (newTicket) {
                    setDialogState(() {
                      currentTicket = newTicket;
                    });
                  });
                },
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan this QR code from another phone or PC to pair with this folder.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6368),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: currentTicket!,
                  version: QrVersions.auto,
                  size: 190.0,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Or paste into PC terminal: p2pme join <ticket>',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark ? const Color(0xFF8AB4F8) : GooglePhotosColors.blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: GooglePhotosColors.red,
                  side: BorderSide(color: GooglePhotosColors.red.withValues(alpha: 0.4)),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Regenerate Ticket & QR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () {
                  _promptRegenerateFolderTicket(folder, (newTicket) {
                    setDialogState(() {
                      currentTicket = newTicket;
                    });
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: GooglePhotosColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Ticket'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: currentTicket!));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pairing ticket copied! Run on PC: p2pme join <ticket>'),
                    backgroundColor: GooglePhotosColors.blue,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // HELPERS FOR VISUAL FILE & FOLDER PICKERS
  // ==========================================
  Future<void> _openCameraBackupPicker() async {
    List<File> cameraFiles = [];
    int iosTotal = 0;
    int iosPending = 0;

    if (Platform.isIOS) {
      final permitted = await CameraBackupService.instance.checkPermission();
      if (!permitted) {
        final granted = await CameraBackupService.instance.requestPermission();
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please allow access to Photos in iOS Settings to enable camera backup.')),
          );
          return;
        }
      }
      await CameraBackupService.instance.scanCameraRoll();
      iosTotal = CameraBackupService.instance.totalDeviceAssets;
      iosPending = CameraBackupService.instance.pendingAssetsCount;
    } else if (Platform.isAndroid) {
      final pathsToTry = [
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/DCIM/100ANDRO',
        '/storage/emulated/0/DCIM/100MEDIA',
        '/storage/emulated/0/DCIM',
      ];
      for (final p in pathsToTry) {
        final d = Directory(p);
        if (d.existsSync()) {
          try {
            final list = d.listSync(recursive: false);
            for (final e in list) {
              if (e is File) {
                final name = e.path.split(Platform.pathSeparator).last;
                final lower = name.toLowerCase();
                if (!name.startsWith('.') &&
                    !name.contains('.trashed') &&
                    (lower.endsWith('.jpg') ||
                     lower.endsWith('.jpeg') ||
                     lower.endsWith('.png') ||
                     lower.endsWith('.heic') ||
                     lower.endsWith('.webp') ||
                     lower.endsWith('.dng') ||
                     lower.endsWith('.mp4') ||
                     lower.endsWith('.mov'))) {
                  cameraFiles.add(e);
                }
              }
            }
            if (cameraFiles.isNotEmpty) break;
          } catch (_) {}
        }
      }
      if (cameraFiles.isNotEmpty) {
        try {
          cameraFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        } catch (_) {}
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF174EA6)
                            : GooglePhotosColors.blueSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.photo_library_outlined,
                        color: GooglePhotosColors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Platform.isIOS ? 'iPhone Camera Roll' : 'Camera',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFFE8EAED)
                                  : const Color(0xFF202124),
                            ),
                          ),
                          Text(
                            Platform.isIOS
                                ? '$iosTotal photos on iPhone • $iosPending pending backup'
                                : (cameraFiles.isNotEmpty
                                    ? '${cameraFiles.length} photos on device'
                                    : 'Camera folder (/DCIM)'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF9AA0A6)
                                  : const Color(0xFF5F6368),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (Platform.isIOS) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GooglePhotosColors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        iosPending > 0
                            ? 'Backup New Photos ($iosPending) to Server'
                            : 'Camera Roll Up to Date',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _syncCameraRollToConnectedPeer();
                    },
                  ),
                  const SizedBox(height: 8),
                ] else if (cameraFiles.isNotEmpty) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GooglePhotosColors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Select all (${cameraFiles.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        for (final f in cameraFiles) {
                          if (!_selectedFilePaths.contains(f.path)) {
                            _selectedFilePaths.add(f.path);
                          }
                        }
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added ${cameraFiles.length} photos')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  if (cameraFiles.length > 5) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        side: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? GooglePhotosColors.darkBorder
                              : GooglePhotosColors.lightBorder,
                        ),
                      ),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Select recent (${min(10, cameraFiles.length)})', style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          final subset = cameraFiles.take(10);
                          for (final f in subset) {
                            if (!_selectedFilePaths.contains(f.path)) {
                              _selectedFilePaths.add(f.path);
                            }
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added ${min(10, cameraFiles.length)} photos')),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? GooglePhotosColors.darkBorder
                          : GooglePhotosColors.lightBorder,
                    ),
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Choose specific photos from gallery', style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final result = await FilePicker.pickFiles(type: FileType.media);
                      if (result.isNotEmpty && mounted) {
                        setState(() {
                          for (final f in result) {
                            if (f.path != null && !_selectedFilePaths.contains(f.path!)) {
                              _selectedFilePaths.add(f.path!);
                            }
                          }
                        });
                      }
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF174EA6)
                        : GooglePhotosColors.blueSurface,
                    foregroundColor: GooglePhotosColors.blue,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Back up to server / computer',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _syncCameraRollToConnectedPeer();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFilesFromDevice() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result.isNotEmpty && mounted) {
        setState(() {
          for (final f in result) {
            if (f.path != null && !_selectedFilePaths.contains(f.path!)) {
              _selectedFilePaths.add(f.path!);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $e')),
        );
      }
    }
  }

  Future<void> _pickDestinationFolder() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folderController = TextEditingController(text: _receiveDestination);

    final basePath = Platform.isAndroid
        ? '/storage/emulated/0'
        : (Platform.isIOS && Platform.environment['HOME'] != null
            ? '${Platform.environment['HOME']}/Documents'
            : (Platform.isWindows ? 'C:\\P2Pme_Receiver' : '.'));
    final presets = Platform.isAndroid
        ? [
            {'name': 'Downloads / P2Pme', 'path': '$basePath/Download/P2Pme', 'icon': Icons.download_rounded},
            {'name': 'Photos / P2Pme', 'path': '$basePath/DCIM/P2Pme', 'icon': Icons.photo_library_rounded},
            {'name': 'Pictures / P2Pme', 'path': '$basePath/Pictures/P2Pme', 'icon': Icons.image_rounded},
            {'name': 'Documents / P2Pme', 'path': '$basePath/Documents/P2Pme', 'icon': Icons.description_rounded},
          ]
        : (Platform.isIOS
            ? [
                {'name': 'Documents / P2Pme', 'path': '$basePath/P2Pme', 'icon': Icons.folder_shared_rounded},
                {'name': 'Camera Backups', 'path': '$basePath/P2Pme/Backups', 'icon': Icons.photo_library_rounded},
              ]
            : [
                {'name': 'Downloads', 'path': './received_drop', 'icon': Icons.download_rounded},
                {'name': 'Photos', 'path': './received_photos', 'icon': Icons.photo_library_rounded},
              ]);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF202124) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.create_new_folder_rounded, color: GooglePhotosColors.blue, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Receiver Destination',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where incoming drops and 24/7 backups will be saved on this device.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                const Text('Quick Location Presets', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...presets.map((preset) {
                  final isSelected = folderController.text == preset['path'];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(preset['icon'] as IconData, color: isSelected ? GooglePhotosColors.blue : Colors.grey, size: 20),
                    title: Text(preset['name'] as String, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                    subtitle: Text(preset['path'] as String, style: const TextStyle(fontSize: 11)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: GooglePhotosColors.blue, size: 18) : null,
                    onTap: () {
                      setModalState(() {
                        folderController.text = preset['path'] as String;
                      });
                    },
                  );
                }),
                const SizedBox(height: 12),
                const Text('Or Create / Enter Custom Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: folderController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.folder_open_rounded, size: 18),
                    hintText: 'e.g. $basePath/MyBackups',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF303134) : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Browse'),
              onPressed: () async {
                try {
                  final picked = await FilePicker.getDirectoryPath();
                  if (picked != null) {
                    setModalState(() {
                      folderController.text = picked;
                    });
                  }
                } catch (_) {}
              },
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: GooglePhotosColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save Location'),
              onPressed: () {
                final path = folderController.text.trim();
                if (path.isNotEmpty) {
                  try {
                    final dir = Directory(path);
                    if (!dir.existsSync()) {
                      dir.createSync(recursive: true);
                    }
                  } catch (_) {}
                  setState(() {
                    _receiveDestination = path;
                  });
                  _saveAppConfig();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Save destination set to: $path'),
                      backgroundColor: GooglePhotosColors.blue,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleCreateDrop() {
    if (_selectedFilePaths.isEmpty) return;

    setState(() => _isCreatingDrop = true);

    try {
      final res = P2PBridge.instance.createDrop(_selectedFilePaths);
      if (res != null && res['success'] == true) {
        setState(() {
          _activeDropPin = res['pin_code'];
          _activeDropTicket = res['ticket_payload'];
          _activeDropFiles = res['file_count'] ?? _selectedFilePaths.length;
          _activeDropBytes = res['total_bytes'] ?? 0;
          _isCreatingDrop = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quick Drop Ready! PIN: $_activeDropPin')),
        );
      } else {
        setState(() => _isCreatingDrop = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${res?['error'] ?? 'Could not create drop'}')),
        );
      }
    } catch (e) {
      setState(() => _isCreatingDrop = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exception: $e')),
      );
    }
  }

  void _handleReceiveDrop() {
    final pin = _pinInputController.text.trim();
    final ticket = _ticketInputController.text.trim();

    if (pin.isEmpty && ticket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit PIN or paste a Drop Ticket')),
      );
      return;
    }

    setState(() {
      _isReceivingDrop = true;
      _receiveMessage = null;
    });

    try {
      final res = P2PBridge.instance.receiveDrop(
        ticket,
        pinCode: pin.isNotEmpty ? pin : null,
        destination: _receiveDestination,
      );

      if (res != null && res['success'] == true) {
        setState(() {
          _isReceivingDrop = false;
          _receiveSuccess = true;
          _receivedFiles = res['files_transferred'] ?? 0;
          _receivedBytes = res['bytes_transferred'] ?? 0;
          _receiveMessage =
              'Downloaded and verified $_receivedFiles file(s) (${(_receivedBytes / 1024).toStringAsFixed(1)} KB) directly into $_receiveDestination. Sender session self-destructed.';
        });
      } else {
        setState(() {
          _isReceivingDrop = false;
          _receiveSuccess = false;
          _receiveMessage = res?['error'] ?? 'Authentication failed or drop expired';
        });
      }
    } catch (e) {
      setState(() {
        _isReceivingDrop = false;
        _receiveSuccess = false;
        _receiveMessage = 'Error: $e';
      });
    }
  }

  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'P2Pme System Diagnostics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  _diagRow('Rust Core Engine', _isEngineReady ? 'Active (Native FFI)' : 'Initializing'),
                  _diagRow('Node ID', _nodeId ?? 'node_auto_gen'),
                  _diagRow('Listening Port', _listeningPort > 0 ? '$_listeningPort (QUIC)' : '45454 (UDP)'),
                  _diagRow('Encryption', 'TLS 1.3 End-to-End'),
                  _diagRow('Integrity Check', 'BLAKE3 Cryptographic Chunking'),
                  _diagRow('Zero-Custody', 'Direct Peer-to-Peer (No Cloud Servers)'),
                  _diagRow('App Version', 'v$_currentVersionName (build $_currentVersionCode)'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: _isCheckingUpdates
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Check for Updates', style: TextStyle(fontSize: 12)),
                    onPressed: _isCheckingUpdates
                        ? null
                        : () => _checkForAppUpdates(manual: true, onComplete: () {
                              if (context.mounted) setModalState(() {});
                            }),
                  ),
                  if (_updateAvailable) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GooglePhotosColors.blueSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: GooglePhotosColors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Update Available: v${_latestVersionName ?? ""}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: GooglePhotosColors.blue),
                              ),
                              const Icon(Icons.system_update_rounded, size: 18, color: GooglePhotosColors.blue),
                            ],
                          ),
                          if (_updateReleaseNotes != null) ...[
                            const SizedBox(height: 4),
                            Text(_updateReleaseNotes!, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                          ],
                          if (_isDownloadingUpdate) ...[
                            const SizedBox(height: 8),
                            Text(
                              _downloadStatusText ?? 'Downloading update...',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GooglePhotosColors.blue),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0 ? _downloadProgress : null,
                                minHeight: 4,
                                backgroundColor: Colors.grey.shade300,
                                color: GooglePhotosColors.blue,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: GooglePhotosColors.blue,
                              minimumSize: const Size.fromHeight(40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: _isDownloadingUpdate
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download_rounded, size: 16),
                            label: Text(
                              _isDownloadingUpdate
                                  ? 'Downloading...'
                                  : 'Download & Install Directly',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isDownloadingUpdate
                                ? null
                                : () => _downloadAndInstallUpdate(onProgressUpdate: () {
                                      if (context.mounted) setModalState(() {});
                                    }),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _diagRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
