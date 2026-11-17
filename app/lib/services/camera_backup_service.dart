import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CameraAssetItem {
  final String id;
  final String filename;
  final double createdTimestamp;
  final String mediaType;
  final String? localFilePath;
  final int fileSize;

  CameraAssetItem({
    required this.id,
    required this.filename,
    required this.createdTimestamp,
    required this.mediaType,
    this.localFilePath,
    this.fileSize = 0,
  });
}

enum CameraBackupState {
  idle,
  checking,
  syncing,
  upToDate,
  serverStorageFull,
  error,
}

class CameraBackupService {
  static CameraBackupService? _instance;
  static CameraBackupService get instance => _instance ??= CameraBackupService._();

  static const MethodChannel _iosChannel = MethodChannel('net.p2pme/camera_roll');

  final Set<String> _syncedAssetIds = {};
  DateTime? _lastSyncTime;
  CameraBackupState _state = CameraBackupState.idle;
  bool _isServerStorageFull = false;
  String? _lastError;

  // Receiver storage telemetry (populated via pre-flight /api/info probe)
  int? _receiverFreeStorageBytes;
  int? _receiverTotalStorageBytes;

  int _totalDeviceAssets = 0;
  int _pendingAssetsCount = 0;
  int _currentSyncIndex = 0;
  String? _currentSyncingFilename;

  final StreamController<CameraBackupState> _stateController = StreamController<CameraBackupState>.broadcast();
  Stream<CameraBackupState> get stateStream => _stateController.stream;

  CameraBackupState get state => _state;
  bool get isServerStorageFull => _isServerStorageFull;
  int get totalDeviceAssets => _totalDeviceAssets;
  int get pendingAssetsCount => _pendingAssetsCount;
  int get currentSyncIndex => _currentSyncIndex;
  String? get currentSyncingFilename => _currentSyncingFilename;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;

  /// Receiver free storage in bytes – populated before first file of each batch
  int? get receiverFreeStorageBytes => _receiverFreeStorageBytes;
  int? get receiverTotalStorageBytes => _receiverTotalStorageBytes;

  VoidCallback? onNewAssetsDetected;

  CameraBackupService._() {
    _initStorage();
    if (Platform.isIOS) {
      _iosChannel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onCameraRollChanged') {
      debugPrint('[CameraBackup] onCameraRollChanged detected from iOS PhotoKit');
      await scanCameraRoll();
      onNewAssetsDetected?.call();
    }
  }

  Future<File> _getStorageFile() async {
    String baseDir;
    if (Platform.isAndroid) {
      baseDir = '/data/data/net.p2pme.p2pme_app/files';
    } else if (Platform.isIOS) {
      final home = Platform.environment['HOME'];
      baseDir = (home != null && home.isNotEmpty) ? '$home/Documents' : '.';
    } else {
      baseDir = '.';
    }
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final targetFile = File('${dir.path}${Platform.pathSeparator}p2pme_synced_camera_assets.json');

    // Migration helper: If an older index exists in systemTemp on iOS, migrate it to permanent Documents storage
    if (Platform.isIOS && !await targetFile.exists()) {
      try {
        final legacyTempDir = (await Directory.systemTemp.createTemp()).parent;
        final legacyFile = File('${legacyTempDir.path}${Platform.pathSeparator}p2pme_synced_camera_assets.json');
        if (await legacyFile.exists()) {
          await legacyFile.copy(targetFile.path);
          debugPrint('[CameraBackup] Migrated synced assets index from systemTemp to permanent Documents storage');
        }
      } catch (_) {}
    }

    return targetFile;
  }

  Future<void> _initStorage() async {
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final ids = (json['synced_ids'] as List<dynamic>?)?.cast<String>() ?? [];
        _syncedAssetIds.addAll(ids);
        if (json['last_sync'] != null) {
          _lastSyncTime = DateTime.tryParse(json['last_sync'].toString());
        }
      }
    } catch (e) {
      debugPrint('[CameraBackup] Failed to load synced asset index: $e');
    }
  }

  Future<void> _saveStorage() async {
    try {
      final file = await _getStorageFile();
      final data = {
        'synced_ids': _syncedAssetIds.toList(),
        'last_sync': _lastSyncTime?.toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[CameraBackup] Failed to save synced asset index: $e');
    }
  }

  /// Request photo library permissions
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      try {
        final bool granted = await _iosChannel.invokeMethod('requestPermission');
        return granted;
      } catch (e) {
        debugPrint('[CameraBackup] Permission request error: $e');
        return false;
      }
    }
    return true;
  }

  /// Check permission status
  Future<bool> checkPermission() async {
    if (Platform.isIOS) {
      try {
        final bool status = await _iosChannel.invokeMethod('checkPermission');
        return status;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Scan camera roll and return list of unsynced items
  Future<List<CameraAssetItem>> scanCameraRoll({int limit = 0}) async {
    _state = CameraBackupState.checking;
    _stateController.add(_state);

    final List<CameraAssetItem> allAssets = [];

    try {
      if (Platform.isIOS) {
        final int total = await _iosChannel.invokeMethod('getAssetCount') ?? 0;
        _totalDeviceAssets = total;

        final List<dynamic>? rawList = await _iosChannel.invokeMethod('getAssets', {'limit': limit});
        if (rawList != null) {
          for (final item in rawList) {
            final m = Map<String, dynamic>.from(item as Map);
            allAssets.add(CameraAssetItem(
              id: m['id']?.toString() ?? '',
              filename: m['filename']?.toString() ?? 'photo.jpg',
              createdTimestamp: (m['created'] as num?)?.toDouble() ?? 0.0,
              mediaType: m['mediaType']?.toString() ?? 'image',
              fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
            ));
          }
        }
      } else if (Platform.isAndroid) {
        final pathsToTry = [
          '/storage/emulated/0/DCIM/Camera',
          '/storage/emulated/0/DCIM/100ANDRO',
          '/storage/emulated/0/DCIM/100MEDIA',
          '/storage/emulated/0/DCIM',
        ];

        for (final p in pathsToTry) {
          final dir = Directory(p);
          if (await dir.exists()) {
            final list = dir.listSync(recursive: false);
            for (final entity in list) {
              if (entity is File) {
                final name = entity.path.split(Platform.pathSeparator).last;
                final lower = name.toLowerCase();
                if (!name.startsWith('.') &&
                    !name.contains('.trashed') &&
                    !lower.contains('screenshot') &&
                    !entity.path.toLowerCase().contains('screenshot') &&
                    !lower.contains('screen_record') &&
                    !lower.contains('screenrecord') &&
                    !lower.contains('screen-record') &&
                    !entity.path.toLowerCase().contains('screen_record') &&
                    !entity.path.toLowerCase().contains('screenrecord') &&
                    (lower.endsWith('.jpg') ||
                     lower.endsWith('.jpeg') ||
                     lower.endsWith('.png') ||
                     lower.endsWith('.heic') ||
                     lower.endsWith('.webp') ||
                     lower.endsWith('.dng') ||
                     lower.endsWith('.mp4') ||
                     lower.endsWith('.mov'))) {
                  final stat = entity.statSync();
                  allAssets.add(CameraAssetItem(
                    id: entity.path,
                    filename: name,
                    createdTimestamp: stat.modified.millisecondsSinceEpoch.toDouble(),
                    mediaType: lower.endsWith('.mp4') || lower.endsWith('.mov') ? 'video' : 'image',
                    localFilePath: entity.path,
                    fileSize: stat.size,
                  ));
                }
              }
            }
            if (allAssets.isNotEmpty) break;
          }
        }
        _totalDeviceAssets = allAssets.length;
      }
    } catch (e) {
      debugPrint('[CameraBackup] Error scanning camera roll: $e');
    }

    final unsynced = allAssets.where((a) => !_syncedAssetIds.contains(a.id)).toList();
    _pendingAssetsCount = unsynced.length;
    _pendingTotalBytes = unsynced.fold<int>(0, (sum, item) => sum + item.fileSize);

    _state = unsynced.isEmpty ? CameraBackupState.upToDate : CameraBackupState.idle;
    _stateController.add(_state);

    return unsynced;
  }

  bool _isSyncPaused = false;
  bool get isSyncPaused => _isSyncPaused;

  int _pendingTotalBytes = 0;
  int _batchTotalBytes = 0;
  int _batchBytesSent = 0;
  int _currentFileTotalBytes = 0;
  int _currentFileBytesSent = 0;

  int get pendingTotalBytes => _pendingTotalBytes;
  int get batchTotalBytes => _batchTotalBytes;
  int get batchBytesSent => _batchBytesSent;
  int get currentFileTotalBytes => _currentFileTotalBytes;
  int get currentFileBytesSent => _currentFileBytesSent;

  double get overallBatchProgressRatio {
    if (_batchTotalBytes <= 0) return 0.0;
    return (_batchBytesSent / _batchTotalBytes).clamp(0.0, 1.0);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    } else {
      return '$bytes B';
    }
  }

  String get formattedBatchBytes => '${formatBytes(_batchBytesSent)} of ${formatBytes(_batchTotalBytes)}';
  String get formattedPendingBytes => formatBytes(_pendingTotalBytes);

  double _currentSpeedBytesPerSec = 0.0;
  double _currentFileProgressRatio = 0.0;
  double get currentSpeedBytesPerSec => _currentSpeedBytesPerSec;
  double get currentFileProgressRatio => _currentFileProgressRatio;

  String get formattedSpeed {
    if (_currentSpeedBytesPerSec <= 0) return '0.0 MB/s';
    final mb = _currentSpeedBytesPerSec / (1024 * 1024);
    if (mb >= 1.0) {
      return '${mb.toStringAsFixed(1)} MB/s';
    } else {
      final kb = _currentSpeedBytesPerSec / 1024;
      return '${kb.toStringAsFixed(0)} KB/s';
    }
  }

  void pauseSync() {
    _isSyncPaused = true;
    _currentSpeedBytesPerSec = 0.0;
    _currentFileProgressRatio = 0.0;
    _state = CameraBackupState.idle;
    _stateController.add(_state);
  }

  void resumeSync() {
    _isSyncPaused = false;
  }

  /// Automatically upload all unsynced camera photos to connected peer/server
  Future<int> syncPendingToPeer({
    required String peerIp,
    required int peerPort,
    required String token,
    String? wanHost,
    int? wanPort,
    String? senderDeviceName,
    bool wifiOnly = false,
    bool isUsbConnected = false,
    Function(int current, int total, String filename)? onProgress,
  }) async {
    _isSyncPaused = false;
    final pending = await scanCameraRoll();
    if (pending.isEmpty) {
      _state = CameraBackupState.upToDate;
      _stateController.add(_state);
      return 0;
    }

    if (wifiOnly && !isUsbConnected) {
      // If target peer is not a LAN IP and wifi-only is required, abort sync
      final isLan = peerIp.startsWith('192.168.') || peerIp.startsWith('10.') || peerIp.startsWith('172.');
      if (!isLan && (wanHost == null || wanHost.isEmpty || peerIp == wanHost)) {
        debugPrint('[CameraBackup] Wi-Fi Only sync is active. Skipping non-LAN host: $peerIp');
        _lastError = 'Wi-Fi Only sync is enabled. Connect to local Wi-Fi to sync.';
        _state = CameraBackupState.idle;
        _stateController.add(_state);
        return 0;
      }
    }

    _state = CameraBackupState.syncing;
    _stateController.add(_state);
    int transferredCount = 0;

    _batchTotalBytes = pending.fold<int>(0, (sum, item) => sum + item.fileSize);
    _batchBytesSent = 0;
    // Reset receiver storage telemetry for this new batch
    _receiverFreeStorageBytes = null;
    _receiverTotalStorageBytes = null;

    String activeHost = peerIp;
    int activePort = peerPort;

    // Pre-flight: probe receiver's /api/info to get storage telemetry before first file
    try {
      final infoClient = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final infoReq = await infoClient.getUrl(Uri.parse('http://$peerIp:$peerPort/api/info'));
      final infoResp = await infoReq.close();
      if (infoResp.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(infoResp).join();
        final infoJson = jsonDecode(body) as Map<String, dynamic>;
        final storageMap = infoJson['storage'] as Map<String, dynamic>?;
        _receiverFreeStorageBytes = (storageMap?['free_bytes'] as num?)?.toInt();
        _receiverTotalStorageBytes = (storageMap?['total_bytes'] as num?)?.toInt();
        debugPrint('[CameraBackup] Pre-flight: receiver free=$_receiverFreeStorageBytes bytes');
      }
    } catch (e) {
      debugPrint('[CameraBackup] Pre-flight /api/info probe failed (non-fatal): $e');
    }

    // Fast probe to verify if LAN peerIp is directly reachable. If not and wanHost is provided, switch to WAN
    if (wanHost != null && wanHost.isNotEmpty && wanHost != peerIp) {
      if (wifiOnly && !isUsbConnected) {
        debugPrint('[CameraBackup] LAN peer unreachable. Wi-Fi Only sync prevents falling back to WAN.');
      } else {
        try {
          final probeClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);
          final req = await probeClient.getUrl(Uri.parse('http://$peerIp:$peerPort/api/info'));
          final resp = await req.close();
          if (resp.statusCode != HttpStatus.ok) {
            activeHost = wanHost;
            activePort = wanPort ?? peerPort;
          }
        } catch (_) {
          activeHost = wanHost;
          activePort = wanPort ?? peerPort;
        }
      }
    }

    for (int i = 0; i < pending.length; i++) {
      if (_isSyncPaused) {
        debugPrint('[CameraBackup] Backup paused by user.');
        break;
      }
      final item = pending[i];
      _currentSyncIndex = i + 1;
      _currentSyncingFilename = item.filename;
      onProgress?.call(_currentSyncIndex, pending.length, item.filename);

      String? filePathToUpload = item.localFilePath;
      bool isTempExport = false;

      // On iOS, export original uncompressed asset to temp file
      if (Platform.isIOS && (filePathToUpload == null || filePathToUpload.isEmpty)) {
        try {
          final String? exported = await _iosChannel.invokeMethod('exportAsset', {'id': item.id});
          if (exported != null && exported.isNotEmpty) {
            filePathToUpload = exported;
            isTempExport = true;
          }
        } catch (e) {
          debugPrint('[CameraBackup] Failed to export iOS asset ${item.filename}: $e');
          continue;
        }
      }

      if (filePathToUpload == null) continue;

      final uploadFile = File(filePathToUpload);
      if (!await uploadFile.exists()) continue;

      final len = await uploadFile.length();
      _currentFileTotalBytes = len;
      _currentFileBytesSent = 0;
      if (item.fileSize <= 0) {
        _batchTotalBytes += len;
      }

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
          final senderParam = (senderDeviceName != null && senderDeviceName.isNotEmpty) ? '&senderDevice=${Uri.encodeComponent(senderDeviceName)}' : '';
          final url = Uri.parse('http://$activeHost:$activePort/upload?name=${Uri.encodeComponent(item.filename)}&token=$token&fileIndex=${i + 1}&totalFiles=${pending.length}&batchTotal=$_batchTotalBytes&batchSent=$_batchBytesSent$senderParam');
          final req = await client.postUrl(url);

          req.headers.contentLength = len;
          req.headers.contentType = ContentType.binary;
          req.headers.set('X-File-Index', (i + 1).toString());
          req.headers.set('X-Total-Files', pending.length.toString());
          req.headers.set('X-Batch-Total-Bytes', _batchTotalBytes.toString());
          req.headers.set('X-Batch-Bytes-Sent', _batchBytesSent.toString());
          if (senderDeviceName != null && senderDeviceName.isNotEmpty) {
            req.headers.set('X-Sender-Device-Name', senderDeviceName);
          }

          int bytesSentThisFile = 0;
          final Stopwatch sampleWatch = Stopwatch()..start();
          int bytesSinceSample = 0;

          await for (final chunk in uploadFile.openRead()) {
            if (_isSyncPaused) {
              req.abort();
              break;
            }
            req.add(chunk);
            bytesSentThisFile += chunk.length;
            bytesSinceSample += chunk.length;
            _batchBytesSent += chunk.length;
            _currentFileBytesSent = bytesSentThisFile;

            if (sampleWatch.elapsedMilliseconds >= 250) {
              final double seconds = sampleWatch.elapsedMicroseconds / 1000000.0;
              if (seconds > 0) {
                _currentSpeedBytesPerSec = bytesSinceSample / seconds;
              }
              sampleWatch.reset();
              bytesSinceSample = 0;
              _currentFileProgressRatio = len > 0 ? (bytesSentThisFile / len).clamp(0.0, 1.0) : 0.0;
              onProgress?.call(_currentSyncIndex, pending.length, item.filename);
              _stateController.add(_state);
            }
          }

          if (!_isSyncPaused) {
            final resp = await req.close();
            if (resp.statusCode == HttpStatus.ok) {
              _syncedAssetIds.add(item.id);
              transferredCount++;
              _lastSyncTime = DateTime.now();
              await _saveStorage();
              break;
            } else if (resp.statusCode == 507) {
              debugPrint('[CameraBackup] Receiver storage full (HTTP 507). Pausing and awaiting cleanup...');
              _isServerStorageFull = true;
              _receiverFreeStorageBytes = 0;
              _state = CameraBackupState.serverStorageFull;
              _stateController.add(_state);
              _batchBytesSent = (_batchBytesSent - _currentFileBytesSent).clamp(0, _batchTotalBytes);
              _currentFileBytesSent = 0;
              final resumed = await _waitForReceiverStorageAvailable(activeHost, activePort);
              if (!resumed) {
                _lastError = 'Receiver storage wait timed out (5 minutes). Please free up space on receiver.';
                _state = CameraBackupState.serverStorageFull;
                _stateController.add(_state);
                break;
              }
              _isServerStorageFull = false;
              _state = CameraBackupState.syncing;
              _stateController.add(_state);
              i--;
              break;
            } else {
              debugPrint('[CameraBackup] Peer returned status ${resp.statusCode} for ${item.filename}');
            }
          }
        } catch (e) {
          debugPrint('[CameraBackup] Upload attempt ${attempt + 1} failed for ${item.filename} on $activeHost: $e');
          _lastError = e.toString();
          // If retrying, rewind batch bytes sent for this attempt
          _batchBytesSent = (_batchBytesSent - _currentFileBytesSent).clamp(0, _batchTotalBytes);
          _currentFileBytesSent = 0;
          // If LAN failed and WAN is available, switch active endpoint to WAN and retry once if wifiOnly allows
          if (attempt == 0 && wanHost != null && wanHost.isNotEmpty && activeHost != wanHost) {
            if (wifiOnly && !isUsbConnected) {
              debugPrint('[CameraBackup] Wi-Fi Only sync prevents WAN retry.');
            } else {
              activeHost = wanHost;
              activePort = wanPort ?? peerPort;
              continue;
            }
          }
        }
        break;
      }
      _currentFileProgressRatio = 0.0;
      // Clean up temp export on iOS to keep sandbox small
      if (isTempExport) {
        try {
          await uploadFile.delete();
        } catch (_) {}
      }
    }

    _currentSpeedBytesPerSec = 0.0;
    _currentFileProgressRatio = 0.0;
    _pendingAssetsCount = (await scanCameraRoll()).length;
    _state = _pendingAssetsCount == 0 ? CameraBackupState.upToDate : CameraBackupState.idle;
    _stateController.add(_state);

    return transferredCount;
  }

  void markAllCurrentAsSynced(List<CameraAssetItem> assets) {
    for (final a in assets) {
      _syncedAssetIds.add(a.id);
    }
    _lastSyncTime = DateTime.now();
    _saveStorage();
    _pendingAssetsCount = 0;
    _state = CameraBackupState.upToDate;
    _stateController.add(_state);
  }

  Future<bool> _waitForReceiverStorageAvailable(String host, int port) async {
    int attempts = 0;
    const maxAttempts = 60; // 5 minutes max (60 iterations * 5 seconds)
    while (!_isSyncPaused && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 5));
      attempts++;
      if (_isSyncPaused) return false;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await client.getUrl(Uri.parse('http://$host:$port/api/info'));
        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok) {
          final body = await utf8.decoder.bind(resp).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final storage = json['storage'] as Map<String, dynamic>?;
          final freeBytes = (storage?['free_bytes'] as num?)?.toInt() ?? 0;
          _receiverFreeStorageBytes = freeBytes;
          _receiverTotalStorageBytes = (storage?['total_bytes'] as num?)?.toInt();
          _stateController.add(_state);
          if (freeBytes > 200 * 1024 * 1024) { // At least 200 MB free
            debugPrint('[CameraBackup] Receiver storage freed ($freeBytes bytes available). Resuming sync!');
            return true;
          }
        }
      } catch (e) {
        debugPrint('[CameraBackup] Waiting for receiver storage probe error: $e');
      }
    }
    return false;
  }

  Future<String?> getNativeDeviceName() async {
    try {
      if (Platform.isIOS) {
        final res = await _iosChannel.invokeMethod<String>('getDeviceName');
        if (res != null && res.isNotEmpty) return res;
      } else if (Platform.isAndroid) {
        final res = await _bgChannel.invokeMethod<String>('getDeviceName');
        if (res != null && res.isNotEmpty) return res;
      }
    } catch (e) {
      debugPrint('[CameraBackup] Error getting native device name: $e');
    }
    return null;
  }

  Future<bool> openUrl(String url) async {
    if (Platform.isIOS) {
      try {
        final bool res = await _iosChannel.invokeMethod('openUrl', {'url': url}) ?? false;
        return res;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  static const MethodChannel _bgChannel = MethodChannel('net.p2pme/background_sync');

  Future<Map<String, int>> getStorageSpace() async {
    try {
      if (Platform.isIOS) {
        final res = await _iosChannel.invokeMethod('getStorageSpace');
        if (res is Map) {
          return {
            'free_bytes': (res['free_bytes'] as num?)?.toInt() ?? 0,
            'total_bytes': (res['total_bytes'] as num?)?.toInt() ?? 0,
          };
        }
      } else if (Platform.isAndroid) {
        final res = await _bgChannel.invokeMethod('getStorageSpace');
        if (res is Map) {
          return {
            'free_bytes': (res['free_bytes'] as num?)?.toInt() ?? 0,
            'total_bytes': (res['total_bytes'] as num?)?.toInt() ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('[CameraBackup] Error getting storage space: $e');
    }
    return {'free_bytes': 0, 'total_bytes': 0};
  }
}
