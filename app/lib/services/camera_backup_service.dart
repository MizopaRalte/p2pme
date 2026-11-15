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

  CameraAssetItem({
    required this.id,
    required this.filename,
    required this.createdTimestamp,
    required this.mediaType,
    this.localFilePath,
  });
}

enum CameraBackupState {
  idle,
  checking,
  syncing,
  upToDate,
  error,
}

class CameraBackupService {
  static CameraBackupService? _instance;
  static CameraBackupService get instance => _instance ??= CameraBackupService._();

  static const MethodChannel _iosChannel = MethodChannel('net.p2pme/camera_roll');

  final Set<String> _syncedAssetIds = {};
  DateTime? _lastSyncTime;
  CameraBackupState _state = CameraBackupState.idle;
  String? _lastError;

  int _totalDeviceAssets = 0;
  int _pendingAssetsCount = 0;
  int _currentSyncIndex = 0;
  String? _currentSyncingFilename;

  final StreamController<CameraBackupState> _stateController = StreamController<CameraBackupState>.broadcast();
  Stream<CameraBackupState> get stateStream => _stateController.stream;

  CameraBackupState get state => _state;
  int get totalDeviceAssets => _totalDeviceAssets;
  int get pendingAssetsCount => _pendingAssetsCount;
  int get currentSyncIndex => _currentSyncIndex;
  String? get currentSyncingFilename => _currentSyncingFilename;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;

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
    final baseDir = Platform.isAndroid
        ? '/data/data/net.p2pme.p2pme_app/files'
        : (Platform.isIOS ? (await Directory.systemTemp.createTemp()).parent.path : '.');
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}p2pme_synced_camera_assets.json');
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
  Future<List<CameraAssetItem>> scanCameraRoll({int limit = 500}) async {
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

    _state = unsynced.isEmpty ? CameraBackupState.upToDate : CameraBackupState.idle;
    _stateController.add(_state);

    return unsynced;
  }

  /// Automatically upload all unsynced camera photos to connected peer/server
  Future<int> syncPendingToPeer({
    required String peerIp,
    required int peerPort,
    required String token,
    Function(int current, int total, String filename)? onProgress,
  }) async {
    final pending = await scanCameraRoll();
    if (pending.isEmpty) {
      _state = CameraBackupState.upToDate;
      _stateController.add(_state);
      return 0;
    }

    _state = CameraBackupState.syncing;
    _stateController.add(_state);
    int transferredCount = 0;

    for (int i = 0; i < pending.length; i++) {
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

      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        final url = Uri.parse('http://$peerIp:$peerPort/upload?name=${Uri.encodeComponent(item.filename)}&token=$token');
        final req = await client.postUrl(url);

        final len = await uploadFile.length();
        req.headers.contentLength = len;
        req.headers.contentType = ContentType.binary;
        await req.addStream(uploadFile.openRead());
        final resp = await req.close();

        if (resp.statusCode == HttpStatus.ok) {
          _syncedAssetIds.add(item.id);
          transferredCount++;
          _lastSyncTime = DateTime.now();
          await _saveStorage();
        } else {
          debugPrint('[CameraBackup] Peer returned status ${resp.statusCode} for ${item.filename}');
        }
      } catch (e) {
        debugPrint('[CameraBackup] Upload failed for ${item.filename}: $e');
        _lastError = e.toString();
      } finally {
        // Clean up temp export on iOS to keep sandbox small
        if (isTempExport) {
          try {
            await uploadFile.delete();
          } catch (_) {}
        }
      }
    }

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
}
