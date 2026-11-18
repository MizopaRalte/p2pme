import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class StunResult {
  final String publicIp;
  final int publicPort;
  final String stunServer;

  const StunResult({
    required this.publicIp,
    required this.publicPort,
    required this.stunServer,
  });

  @override
  String toString() => '$publicIp:$publicPort (via $stunServer)';
}

/// Pure Dart STUN RFC 5389 client for public IP and mapped port discovery
class StunService {
  static const int _magicCookie = 0x2112A442;
  static const int _bindingRequest = 0x0001;
  static const int _bindingResponse = 0x0101;
  static const int _attrMappedAddress = 0x0001;
  static const int _attrXorMappedAddress = 0x0020;

  static const List<String> defaultStunServers = [
    'stun.l.google.com:19302',
    'stun1.l.google.com:19302',
    'stun2.l.google.com:19302',
  ];

  /// Discovers external WAN IP and mapped port using Google STUN
  static Future<StunResult?> discoverPublicEndpoint({
    Duration timeout = const Duration(seconds: 3),
    List<String> servers = defaultStunServers,
  }) async {
    for (final server in servers) {
      try {
        final result = await _probeStunServer(server, timeout);
        if (result != null) return result;
      } catch (_) {
        // Try next fallback STUN server
      }
    }
    return null;
  }

  static Future<StunResult?> _probeStunServer(String serverStr, Duration timeout) async {
    final parts = serverStr.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 19302 : 19302;

    RawDatagramSocket? socket;
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) return null;
      final serverAddress = addresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      // Build 20-byte STUN Binding Request
      final transactionId = Uint8List(12);
      final rng = Random.secure();
      for (int i = 0; i < 12; i++) {
        transactionId[i] = rng.nextInt(256);
      }

      final request = Uint8List(20);
      final byteData = ByteData.sublistView(request);
      byteData.setUint16(0, _bindingRequest); // Message Type
      byteData.setUint16(2, 0); // Message Length
      byteData.setUint32(4, _magicCookie); // Magic Cookie
      request.setRange(8, 20, transactionId);

      socket.send(request, serverAddress, port);

      final completer = Completer<StunResult?>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null && datagram.data.length >= 20) {
            final parsed = _parseStunResponse(datagram.data, transactionId, serverStr);
            if (parsed != null && !completer.isCompleted) {
              timer.cancel();
              completer.complete(parsed);
            }
          }
        }
      });

      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Parses STUN Binding Response packet
  static StunResult? _parseStunResponse(Uint8List data, Uint8List expectedTxId, String stunServer) {
    if (data.length < 20) return null;
    final view = ByteData.sublistView(data);
    final msgType = view.getUint16(0);
    if (msgType != _bindingResponse) return null;

    final cookie = view.getUint32(4);
    if (cookie != _magicCookie) return null;

    // Verify transaction ID
    for (int i = 0; i < 12; i++) {
      if (data[8 + i] != expectedTxId[i]) return null;
    }

    final msgLen = view.getUint16(2);
    int offset = 20;
    final end = min(data.length, 20 + msgLen);

    String? publicIp;
    int? publicPort;

    while (offset + 4 <= end) {
      final attrType = view.getUint16(offset);
      final attrLen = view.getUint16(offset + 2);
      final valOffset = offset + 4;

      if (valOffset + attrLen > data.length) break;

      if (attrType == _attrXorMappedAddress && attrLen >= 8) {
        final family = data[valOffset + 1];
        if (family == 0x01) { // IPv4
          final xorPort = view.getUint16(valOffset + 2);
          publicPort = xorPort ^ (_magicCookie >> 16);

          final xorIp = view.getUint32(valOffset + 4);
          final ipInt = xorIp ^ _magicCookie;
          publicIp = '${(ipInt >> 24) & 0xFF}.${(ipInt >> 16) & 0xFF}.${(ipInt >> 8) & 0xFF}.${ipInt & 0xFF}';
          break;
        }
      } else if (attrType == _attrMappedAddress && attrLen >= 8 && publicIp == null) {
        final family = data[valOffset + 1];
        if (family == 0x01) { // IPv4
          publicPort = view.getUint16(valOffset + 2);
          publicIp = '${data[valOffset + 4]}.${data[valOffset + 5]}.${data[valOffset + 6]}.${data[valOffset + 7]}';
        }
      }

      // Attributes are padded to 4-byte boundaries
      offset = valOffset + attrLen;
      if (attrLen % 4 != 0) {
        offset += (4 - (attrLen % 4));
      }
    }

    if (publicIp != null && publicPort != null) {
      return StunResult(
        publicIp: publicIp,
        publicPort: publicPort,
        stunServer: stunServer,
      );
    }
    return null;
  }
}
