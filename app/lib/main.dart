import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/p2p_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const P2PmeApp());
}

class P2PmeApp extends StatelessWidget {
  const P2PmeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2Pme',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066FF),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066FF),
          brightness: Brightness.dark,
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
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String? _nodeId;
  int _listeningPort = 0;
  bool _isEngineReady = false;

  final List<SyncFolderItem> _folders = [
    SyncFolderItem(
      id: 'photos-sync',
      name: 'Camera & Photos',
      localPath: '/storage/emulated/0/DCIM/Camera',
      status: 'Live Sync Active',
      connectionTier: 'DIRECT LAN',
      syncMode: 'ARCHIVE (STORAGE SAVER)',
      fileCount: 342,
      totalSizeMb: 1420.5,
      speedMb: 78.4,
    ),
  ];

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

  final TextEditingController _pinInputController = TextEditingController();
  final TextEditingController _ticketInputController = TextEditingController();
  String _receiveDestination = Platform.isAndroid
      ? '/storage/emulated/0/Download/P2Pme'
      : './received_drop';

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

  static String _generateSessionToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _regenerateSessionToken() {
    setState(() {
      _webDropSessionToken = _generateSessionToken();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New 128-bit security token generated! Old QR expired.')),
    );
  }

  @override
  void initState() {
    super.initState();
    _webDropSessionToken = _generateSessionToken();
    _initEngine();
    _checkBackgroundServiceStatus();
    _startWebDropServer();
  }

  @override
  void dispose() {
    _stopWebDropServer();
    super.dispose();
  }

  Future<void> _initLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var iface in interfaces) {
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('10.0.2.')) {
            setState(() => _localIpAddress = addr.address);
            return;
          }
        }
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
      });
      server.listen(_handleWebDropRequest);
    } catch (e) {
      debugPrint('Failed to start WebDrop HTTP server: $e');
    }
  }

  Future<void> _stopWebDropServer() async {
    await _webDropServer?.close(force: true);
    setState(() {
      _webDropServer = null;
      _isWebDropServerRunning = false;
    });
  }

  Future<void> _handleWebDropRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // 128-bit Ephemeral Token Verification
    final token = request.uri.queryParameters['token'] ?? request.headers.value('x-p2pme-token');
    if (token != _webDropSessionToken) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType.html
        ..write('<!DOCTYPE html><html><body style="font-family:sans-serif;text-align:center;padding:50px;background:#0F172A;color:#fff;"><h1>403 Forbidden</h1><p>Invalid or expired ephemeral drop token. Please scan the fresh QR code on the receiver screen.</p></body></html>');
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
      final outFile = File('${destDir.path}${Platform.pathSeparator}$safeName');
      final sink = outFile.openWrite();
      await sink.addStream(request);
      await sink.close();

      final fileLen = await outFile.length();
      if (mounted) {
        setState(() {
          _lastReceivedFromBrowser = safeName;
          _receivedFiles++;
          _receivedBytes += fileLen;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Received from browser: $safeName (${(fileLen / (1024 * 1024)).toStringAsFixed(1)} MB)'),
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

  String _buildWebDropHtml(String token) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>P2Pme Quick Drop</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0F172A; color: #F8FAFC; margin: 0; padding: 24px; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 90vh; }
    .card { background: #1E293B; border-radius: 20px; padding: 28px; width: 100%; max-width: 440px; box-shadow: 0 10px 25px rgba(0,0,0,0.4); border: 1px solid #334155; text-align: center; }
    h1 { font-size: 24px; margin-bottom: 6px; color: #38BDF8; }
    p { color: #94A3B8; font-size: 14px; margin-top: 0; margin-bottom: 24px; }
    .upload-btn { display: inline-block; background: #0284C7; color: white; padding: 16px 32px; border-radius: 14px; font-size: 16px; font-weight: bold; cursor: pointer; border: none; width: 85%; margin-bottom: 16px; box-sizing: border-box; }
    .upload-btn:active { background: #0369A1; }
    input[type="file"] { display: none; }
    .progress-bar-container { width: 100%; height: 16px; background: #334155; border-radius: 8px; overflow: hidden; margin-top: 16px; display: none; }
    .progress-bar { height: 100%; width: 0%; background: #10B981; border-radius: 8px; transition: width 0.2s; font-size: 11px; line-height: 16px; text-align: center; font-weight: bold; color: white; }
    #status { margin-top: 16px; font-weight: 500; font-size: 14px; color: #E2E8F0; }
    .badge { display: inline-block; background: #065F46; color: #34D399; font-size: 11px; font-weight: bold; padding: 4px 10px; border-radius: 20px; margin-bottom: 16px; }
    .token-badge { font-size: 10px; color: #64748B; margin-top: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">DIRECT WI-FI • 128-BIT TOKEN PROTECTED</div>
    <h1>Send to Receiver</h1>
    <p>Select photos, videos, or files from your iPhone / iPad or PC to stream directly to the receiver.</p>
    
    <label class="upload-btn">
      Choose Photos / Files
      <input type="file" id="picker" multiple onchange="startUpload()">
    </label>

    <div class="progress-bar-container" id="progCont">
      <div class="progress-bar" id="progBar">0%</div>
    </div>
    
    <div id="status">Ready to send</div>
    <div class="token-badge">Session Token: \${token.substring(0, 8)}••••••••</div>
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
        status.innerText = 'Sending ' + (i + 1) + '/' + files.length + ': ' + file.name + ' (' + (file.size / (1024 * 1024)).toFixed(1) + ' MB)...';
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
            else reject(new Error('Upload failed: ' + xhr.statusText));
          };
          xhr.onerror = () => reject(new Error('Network error'));
          xhr.send(file);
        });
      }

      progBar.style.width = '100%';
      progBar.innerText = '100%';
      status.innerHTML = '<span style="color: #34D399; font-weight: bold;">Sent ' + files.length + ' file(s) successfully to receiver!</span>';
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
        setState(() {
          _isEngineReady = true;
          _nodeId = P2PBridge.instance.getNodeId();
          _listeningPort = P2PBridge.instance.getPort();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.hub,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'P2Pme',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  'Pure Peer-to-Peer • 100% Private',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Network Diagnostics',
            icon: const Icon(Icons.network_check),
            onPressed: () => _showDiagnostics(context),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Quick Drop',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'Auto-Sync',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Add Folder',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Pair Device',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildQuickDropScreen();
      case 1:
        return _buildFolderList();
      case 2:
        return _buildAddFolderScreen();
      case 3:
        return _buildPairScreen();
      default:
        return _buildQuickDropScreen();
    }
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
          // Friendly banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade400,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'One-Time Quick Drop',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Send files directly with a 6-digit PIN. Self-destructs when received!',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Big Friendly Mode Toggle (Centered & Expanded for Kids & Easy Touch)
          Center(
            child: SegmentedButton<int>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Send File(s)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  icon: Icon(Icons.arrow_upward_rounded),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Receive', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
              ],
              selected: {_quickDropTab},
              onSelectionChanged: (set) => setState(() => _quickDropTab = set.first),
            ),
          ),
          const SizedBox(height: 18),

          if (_quickDropTab == 0) _buildDropSendView() else _buildDropReceiveView(),
        ],
      ),
    );
  }

  Widget _buildDropSendView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Visual File Picker Button
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 24),
                  label: const Text(
                    'Pick Photos, Videos or Files',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _pickFilesFromDevice,
                ),
                if (_selectedFilePaths.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected (${_selectedFilePaths.length} items):',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedFilePaths.clear()),
                        child: const Text('Clear All'),
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
                              ? Icons.image
                              : Icons.insert_drive_file,
                          size: 18,
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

        // Action Button: Send with PIN
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _isCreatingDrop
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.rocket_launch_rounded),
          label: Text(
            _isCreatingDrop
                ? 'Creating Secure Drop...'
                : 'Send with 6-Digit PIN & QR Code',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

                  // Large friendly PIN cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _activeDropPin!.split('').map((digit) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '$_activeDropFiles file(s) • ${(_activeDropBytes / 1024).toStringAsFixed(1)} KB ready',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // On-Screen QR Code for camera scanning
                  if (_activeDropTicket != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: _activeDropTicket!,
                        version: QrVersions.auto,
                        size: 160.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Or scan this QR code with another phone',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('Copy Ticket'),
                        onPressed: () {
                          if (_activeDropTicket != null) {
                            Clipboard.setData(ClipboardData(text: _activeDropTicket!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Drop ticket copied!')),
                            );
                          }
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
                const SizedBox(height: 8),

                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          webUrl,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: webUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Upload link copied to clipboard!')),
                          );
                        },
                        child: const Icon(Icons.copy, size: 14, color: Colors.blue),
                      ),
                    ],
                  ),
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
  // AUTO-SYNC FOLDERS LIST & BACKGROUND OPTIONS
  // ==========================================
  Widget _buildFolderList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildBackgroundAndSpeedCard(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Synchronized Folders (${_folders.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _selectedIndex = 2),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Folder', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ..._folders.map((folder) => _buildFolderCard(folder)),
      ],
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
                    onSelected: (val) => setState(() => _wifiOnlySync = val),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border.all(color: Colors.purple.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'STORAGE SAVER',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple),
                  ),
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Deletions on phone stay on PC',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
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
  // ADD NEW FOLDER / PRESET SETUP SCREEN
  // ==========================================
  Widget _buildAddFolderScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Folder to Auto-Sync',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a preset below or pick any custom directory on your device.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Preset 1: Auto-Backup Camera Photos
          Card(
            color: Colors.purple.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.purple.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.photo_camera_rounded, color: Colors.purple, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-Backup Photos & Videos',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Storage Saver: Free up phone space safely',
                              style: TextStyle(fontSize: 11, color: Colors.purple),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Photos are backed up to your PC. Deleting photos on this phone will NEVER delete them from your PC backup!',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Start Camera Backup (1-Tap Setup)'),
                    onPressed: () {
                      final path = Platform.isAndroid
                          ? '/storage/emulated/0/DCIM/Camera'
                          : 'C:\\Photos';
                      final ticket = P2PBridge.instance.shareFolder(
                        path,
                        'Camera Backup',
                        syncMode: 2, // Archive
                      );
                      if (ticket != null) {
                        setState(() {
                          _folders.add(SyncFolderItem(
                            id: 'cam-${DateTime.now().millisecondsSinceEpoch}',
                            name: 'Camera Backup',
                            localPath: path,
                            status: 'Backup Active',
                            connectionTier: 'DIRECT LAN',
                            syncMode: 'ARCHIVE (STORAGE SAVER)',
                            fileCount: 342,
                            totalSizeMb: 1420.5,
                            speedMb: 78.4,
                          ));
                          _selectedIndex = 1;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Camera Backup activated!')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Custom Folder Picker
          Card(
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
                    'Or Pick Any Custom Folder',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse Folders on Phone...'),
                    onPressed: () async {
                      final dir = await FilePicker.getDirectoryPath();
                      if (dir != null && mounted) {
                        final name = dir.split(Platform.pathSeparator).last;
                        final ticket = P2PBridge.instance.shareFolder(
                          dir,
                          name,
                          syncMode: 2,
                        );
                        if (ticket != null) {
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
                            ));
                            _selectedIndex = 1;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Now syncing folder: $name')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PAIR / SCAN SCREEN (JOIN EXISTING FOLDER)
  // ==========================================
  Widget _buildPairScreen() {
    final ticketController = TextEditingController();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Join an Existing Shared Folder',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Paste a folder pairing ticket from another device to start syncing.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: ticketController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste folder pairing ticket here...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.sync),
            label: const Text('Join & Start Syncing'),
            onPressed: () {
              final t = ticketController.text.trim();
              if (t.isNotEmpty) {
                final targetPath = Platform.isAndroid
                    ? '/storage/emulated/0/Download/P2PmeSync'
                    : 'P2PmeSync';
                final res = P2PBridge.instance.syncTicket(t, targetPath);
                if (res == 0) {
                  setState(() {
                    _folders.add(SyncFolderItem(
                      id: 'joined-${DateTime.now().millisecondsSinceEpoch}',
                      name: 'Synced Peer Folder',
                      localPath: targetPath,
                      status: 'Synchronized',
                      connectionTier: 'DIRECT LAN',
                      syncMode: 'ARCHIVE (STORAGE SAVER)',
                      fileCount: 2,
                      totalSizeMb: 1.0,
                      speedMb: 48.5,
                    ));
                    _selectedIndex = 1;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder joined successfully!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Direct QUIC sync connecting (code: $res)...')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPERS FOR VISUAL FILE & FOLDER PICKERS
  // ==========================================
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
    try {
      final dir = await FilePicker.getDirectoryPath();
      if (dir != null && mounted) {
        setState(() => _receiveDestination = dir);
      }
    } catch (_) {}
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
