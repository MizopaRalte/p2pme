import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _P2PInitNative = Pointer<Void> Function(Pointer<Utf8> dbDir, Uint16 port);
typedef _P2PInitDart = Pointer<Void> Function(Pointer<Utf8> dbDir, int port);

typedef _P2PGetNodeIdNative = Pointer<Utf8> Function(Pointer<Void> ctx);
typedef _P2PGetNodeIdDart = Pointer<Utf8> Function(Pointer<Void> ctx);

typedef _P2PGetPortNative = Uint16 Function(Pointer<Void> ctx);
typedef _P2PGetPortDart = int Function(Pointer<Void> ctx);

typedef _P2PShareFolderNative = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderPath,
  Pointer<Utf8> folderName,
  Bool isRo,
  Uint8 syncMode,
);
typedef _P2PShareFolderDart = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderPath,
  Pointer<Utf8> folderName,
  bool isRo,
  int syncMode,
);

typedef _P2PSyncTicketNative = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Utf8> ticketStr,
  Pointer<Utf8> destination,
);
typedef _P2PSyncTicketDart = int Function(
  Pointer<Void> ctx,
  Pointer<Utf8> ticketStr,
  Pointer<Utf8> destination,
);

typedef _P2PCreateDropNative = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> filesJson,
);
typedef _P2PCreateDropDart = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> filesJson,
);

typedef _P2PReceiveDropNative = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> ticketPayload,
  Pointer<Utf8> pinCode,
  Pointer<Utf8> destination,
);
typedef _P2PReceiveDropDart = Pointer<Utf8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> ticketPayload,
  Pointer<Utf8> pinCode,
  Pointer<Utf8> destination,
);

typedef _P2PStartWatcherNative = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderPath,
  Pointer<Utf8> folderId,
);
typedef _P2PStartWatcherDart = int Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderPath,
  Pointer<Utf8> folderId,
);

typedef _P2PStopWatcherNative = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderId,
);
typedef _P2PStopWatcherDart = int Function(
  Pointer<Void> ctx,
  Pointer<Utf8> folderId,
);

typedef _P2PFreeStringNative = Void Function(Pointer<Utf8> s);
typedef _P2PFreeStringDart = void Function(Pointer<Utf8> s);

typedef _P2PDestroyNative = Void Function(Pointer<Void> ctx);
typedef _P2PDestroyDart = void Function(Pointer<Void> ctx);

class P2PBridge {
  static P2PBridge? _instance;
  static P2PBridge get instance => _instance ??= P2PBridge._();

  DynamicLibrary? _lib;
  Pointer<Void>? _ctx;

  late final _P2PInitDart _init;
  late final _P2PGetNodeIdDart _getNodeId;
  late final _P2PGetPortDart _getPort;
  late final _P2PShareFolderDart _shareFolder;
  late final _P2PSyncTicketDart _syncTicket;
  late final _P2PCreateDropDart _createDrop;
  late final _P2PReceiveDropDart _receiveDrop;
  late final _P2PStartWatcherDart _startWatcher;
  late final _P2PStopWatcherDart _stopWatcher;
  late final _P2PFreeStringDart _freeString;
  late final _P2PDestroyDart _destroy;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized && _ctx != null && _ctx != nullptr;

  P2PBridge._() {
    _loadLibrary();
  }

  void _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libp2pme_ffi.so');
      } else if (Platform.isWindows) {
        _lib = DynamicLibrary.open('p2pme_ffi.dll');
      } else if (Platform.isLinux) {
        _lib = DynamicLibrary.open('libp2pme_ffi.so');
      } else if (Platform.isMacOS) {
        _lib = DynamicLibrary.open('libp2pme_ffi.dylib');
      } else {
        _lib = DynamicLibrary.process();
      }

      _init = _lib!.lookupFunction<_P2PInitNative, _P2PInitDart>('p2pme_init');
      _getNodeId = _lib!.lookupFunction<_P2PGetNodeIdNative, _P2PGetNodeIdDart>('p2pme_get_node_id');
      _getPort = _lib!.lookupFunction<_P2PGetPortNative, _P2PGetPortDart>('p2pme_get_port');
      _shareFolder = _lib!.lookupFunction<_P2PShareFolderNative, _P2PShareFolderDart>('p2pme_share_folder');
      _syncTicket = _lib!.lookupFunction<_P2PSyncTicketNative, _P2PSyncTicketDart>('p2pme_sync_ticket');
      _createDrop = _lib!.lookupFunction<_P2PCreateDropNative, _P2PCreateDropDart>('p2pme_create_drop');
      _receiveDrop = _lib!.lookupFunction<_P2PReceiveDropNative, _P2PReceiveDropDart>('p2pme_receive_drop');
      _startWatcher = _lib!.lookupFunction<_P2PStartWatcherNative, _P2PStartWatcherDart>('p2pme_start_watcher');
      _stopWatcher = _lib!.lookupFunction<_P2PStopWatcherNative, _P2PStopWatcherDart>('p2pme_stop_watcher');
      _freeString = _lib!.lookupFunction<_P2PFreeStringNative, _P2PFreeStringDart>('p2pme_free_string');
      _destroy = _lib!.lookupFunction<_P2PDestroyNative, _P2PDestroyDart>('p2pme_destroy');
    } catch (_) {
      _lib = null;
    }
  }

  bool initNode(String dbDir, {int port = 0}) {
    if (_lib == null) return false;
    final dbDirPtr = dbDir.toNativeUtf8();
    try {
      _ctx = _init(dbDirPtr, port);
      _isInitialized = _ctx != null && _ctx != nullptr;
      return _isInitialized;
    } finally {
      calloc.free(dbDirPtr);
    }
  }

  String? getNodeId() {
    if (!isInitialized) return null;
    final ptr = _getNodeId(_ctx!);
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  int getPort() {
    if (!isInitialized) return 0;
    return _getPort(_ctx!);
  }

  String? shareFolder(
    String folderPath,
    String folderName, {
    bool readOnly = false,
    int syncMode = 0, // 0 = TwoWay, 1 = CameraBackup, 2 = Archive
  }) {
    if (!isInitialized) return null;
    final pathPtr = folderPath.toNativeUtf8();
    final namePtr = folderName.toNativeUtf8();
    try {
      final ticketPtr = _shareFolder(_ctx!, pathPtr, namePtr, readOnly, syncMode);
      if (ticketPtr == nullptr) return null;
      try {
        return ticketPtr.toDartString();
      } finally {
        _freeString(ticketPtr);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(namePtr);
    }
  }

  int syncTicket(String ticketStr, String destination) {
    if (!isInitialized) return -1;
    final ticketPtr = ticketStr.toNativeUtf8();
    final destPtr = destination.toNativeUtf8();
    try {
      return _syncTicket(_ctx!, ticketPtr, destPtr);
    } finally {
      calloc.free(ticketPtr);
      calloc.free(destPtr);
    }
  }

  Map<String, dynamic>? createDrop(List<String> filePaths) {
    if (!isInitialized) return null;
    final jsonStr = jsonEncode(filePaths);
    final jsonPtr = jsonStr.toNativeUtf8();
    try {
      final resPtr = _createDrop(_ctx!, jsonPtr);
      if (resPtr == nullptr) return null;
      try {
        final resStr = resPtr.toDartString();
        return jsonDecode(resStr) as Map<String, dynamic>;
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(jsonPtr);
    }
  }

  Map<String, dynamic>? receiveDrop(
    String ticketPayload, {
    String? pinCode,
    required String destination,
  }) {
    if (!isInitialized) return null;
    final ticketPtr = ticketPayload.toNativeUtf8();
    final pinPtr = pinCode != null ? pinCode.toNativeUtf8() : nullptr;
    final destPtr = destination.toNativeUtf8();
    try {
      final resPtr = _receiveDrop(_ctx!, ticketPtr, pinPtr, destPtr);
      if (resPtr == nullptr) return null;
      try {
        final resStr = resPtr.toDartString();
        return jsonDecode(resStr) as Map<String, dynamic>;
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(ticketPtr);
      if (pinPtr != nullptr) calloc.free(pinPtr);
      calloc.free(destPtr);
    }
  }

  int startWatcher(String folderPath, String folderId) {
    if (!isInitialized) return -1;
    final pathPtr = folderPath.toNativeUtf8();
    final idPtr = folderId.toNativeUtf8();
    try {
      return _startWatcher(_ctx!, pathPtr, idPtr);
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
    }
  }

  int stopWatcher(String folderId) {
    if (!isInitialized) return -1;
    final idPtr = folderId.toNativeUtf8();
    try {
      return _stopWatcher(_ctx!, idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  void dispose() {
    if (isInitialized) {
      _destroy(_ctx!);
      _ctx = null;
      _isInitialized = false;
    }
  }
}
