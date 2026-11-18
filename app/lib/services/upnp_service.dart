import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class UpnpResult {
  final bool isSuccess;
  final String? externalIp;
  final int externalPort;
  final String? routerModel;
  final String? serviceType;
  final String? controlUrl;
  final String? errorMessage;

  const UpnpResult({
    required this.isSuccess,
    this.externalIp,
    required this.externalPort,
    this.routerModel,
    this.serviceType,
    this.controlUrl,
    this.errorMessage,
  });

  @override
  String toString() => isSuccess
      ? 'UPnP Mapped: $externalIp:$externalPort ($routerModel)'
      : 'UPnP Failed: $errorMessage';
}

/// Pure Dart UPnP & NAT-PMP IGD Service for Automated Router Port Forwarding
class UpnpService {
  static const String _ssdpMulticastAddress = '239.255.255.250';
  static const int _ssdpPort = 1900;

  static const List<String> _targetServiceTypes = [
    'urn:schemas-upnp-org:service:WANIPConnection:1',
    'urn:schemas-upnp-org:service:WANPPPConnection:1',
    'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
  ];

  /// Discover router IGD and map port for incoming Server Hub connections
  static Future<UpnpResult> mapPort({
    required int port,
    required String localIp,
    Duration timeout = const Duration(seconds: 4),
    String description = 'P2Pme Server Hub',
  }) async {
    try {
      final igdLocations = await _discoverIgdLocations(timeout);
      if (igdLocations.isEmpty) {
        // Fallback: try NAT-PMP directly against the default gateway
        final natPmpRes = await _tryNatPmp(port, localIp);
        if (natPmpRes != null && natPmpRes.isSuccess) {
          return natPmpRes;
        }
        return UpnpResult(
          isSuccess: false,
          externalPort: port,
          errorMessage: 'No UPnP IGD router or NAT-PMP gateway discovered on local network.',
        );
      }

      for (final location in igdLocations) {
        try {
          final controlInfo = await _parseControlUrl(location);
          if (controlInfo == null) continue;

          final serviceType = controlInfo['serviceType']!;
          final controlUrl = controlInfo['controlUrl']!;
          final routerModel = controlInfo['modelName'] ?? 'Wi-Fi Router';

          // 1. Request router's external public IP address
          final externalIp = await _getExternalIp(controlUrl, serviceType);

          // 2. Request port mapping on the router
          final addOk = await _addPortMapping(
            controlUrl: controlUrl,
            serviceType: serviceType,
            externalPort: port,
            internalPort: port,
            localIp: localIp,
            description: description,
          );

          if (addOk) {
            return UpnpResult(
              isSuccess: true,
              externalIp: externalIp,
              externalPort: port,
              routerModel: routerModel,
              serviceType: serviceType,
              controlUrl: controlUrl,
            );
          }
        } catch (_) {
          continue;
        }
      }

      return UpnpResult(
        isSuccess: false,
        externalPort: port,
        errorMessage: 'Router discovered, but rejected AddPortMapping request.',
      );
    } catch (e) {
      return UpnpResult(
        isSuccess: false,
        externalPort: port,
        errorMessage: e.toString(),
      );
    }
  }

  /// Remove UPnP port mapping when Server Hub mode stops
  static Future<bool> unmapPort({
    required int port,
    required String controlUrl,
    required String serviceType,
  }) async {
    try {
      final soapBody = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:DeletePortMapping xmlns:u="$serviceType">
      <NewRemoteHost></NewRemoteHost>
      <NewExternalPort>$port</NewExternalPort>
      <NewProtocol>TCP</NewProtocol>
    </u:DeletePortMapping>
  </s:Body>
</s:Envelope>''';

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse(controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPAction', '"$serviceType#DeletePortMapping"');
      req.write(soapBody);
      final resp = await req.close();
      return resp.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------
  // Private SSDP & SOAP Helpers
  // -------------------------------------------------------------

  static Future<List<String>> _discoverIgdLocations(Duration timeout) async {
    RawDatagramSocket? socket;
    final locations = <String>{};

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      for (final st in _targetServiceTypes) {
        final ssdpMsg = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: $st\r\n'
            '\r\n';

        socket.send(
          utf8.encode(ssdpMsg),
          InternetAddress(_ssdpMulticastAddress),
          _ssdpPort,
        );
      }

      final completer = Completer<List<String>>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(locations.toList());
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final text = utf8.decode(datagram.data, allowMalformed: true);
            for (final line in text.split('\r\n')) {
              if (line.toLowerCase().startsWith('location:')) {
                final loc = line.substring(9).trim();
                if (loc.startsWith('http://') || loc.startsWith('https://')) {
                  locations.add(loc);
                }
              }
            }
          }
        }
      });

      return await completer.future;
    } catch (_) {
      return [];
    } finally {
      socket?.close();
    }
  }

  static Future<Map<String, String>?> _parseControlUrl(String locationUrl) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse(locationUrl));
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return null;

      final xml = await utf8.decoder.bind(resp).join();
      final baseUri = Uri.parse(locationUrl);

      // Extract modelName
      String? modelName;
      final modelMatch = RegExp(r'<modelName>(.*?)</modelName>', caseSensitive: false).firstMatch(xml);
      if (modelMatch != null) modelName = modelMatch.group(1);

      // Search for WANIPConnection or WANPPPConnection service
      for (final targetService in ['urn:schemas-upnp-org:service:WANIPConnection:1', 'urn:schemas-upnp-org:service:WANPPPConnection:1']) {
        if (xml.contains(targetService)) {
          final serviceIdx = xml.indexOf(targetService);
          final serviceBlock = xml.substring(serviceIdx, (serviceIdx + 1200).clamp(0, xml.length));
          final controlMatch = RegExp(r'<controlURL>(.*?)</controlURL>', caseSensitive: false).firstMatch(serviceBlock);
          if (controlMatch != null) {
            var rawControl = controlMatch.group(1)!.trim();
            final resolvedControlUrl = baseUri.resolve(rawControl).toString();
            return {
              'serviceType': targetService,
              'controlUrl': resolvedControlUrl,
              'modelName': modelName ?? 'Home Router',
            };
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _getExternalIp(String controlUrl, String serviceType) async {
    try {
      final soapBody = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetExternalIPAddress xmlns:u="$serviceType" />
  </s:Body>
</s:Envelope>''';

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse(controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPAction', '"$serviceType#GetExternalIPAddress"');
      req.write(soapBody);
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return null;

      final respXml = await utf8.decoder.bind(resp).join();
      final match = RegExp(r'<NewExternalIPAddress>(.*?)</NewExternalIPAddress>', caseSensitive: false).firstMatch(respXml);
      return match?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _addPortMapping({
    required String controlUrl,
    required String serviceType,
    required int externalPort,
    required int internalPort,
    required String localIp,
    required String description,
  }) async {
    try {
      final soapBody = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:AddPortMapping xmlns:u="$serviceType">
      <NewRemoteHost></NewRemoteHost>
      <NewExternalPort>$externalPort</NewExternalPort>
      <NewProtocol>TCP</NewProtocol>
      <NewInternalPort>$internalPort</NewInternalPort>
      <NewInternalClient>$localIp</NewInternalClient>
      <NewEnabled>1</NewEnabled>
      <NewPortMappingDescription>$description</NewPortMappingDescription>
      <NewLeaseDuration>0</NewLeaseDuration>
    </u:AddPortMapping>
  </s:Body>
</s:Envelope>''';

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.postUrl(Uri.parse(controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPAction', '"$serviceType#AddPortMapping"');
      req.write(soapBody);
      final resp = await req.close();
      return resp.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  /// NAT-PMP (RFC 6886) UDP fallback for Apple AirPort / OpenWrt gateways
  static Future<UpnpResult?> _tryNatPmp(int port, String localIp) async {
    RawDatagramSocket? socket;
    try {
      final parts = localIp.split('.');
      if (parts.length != 4) return null;
      final gatewayIp = '${parts[0]}.${parts[1]}.${parts[2]}.1';

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      // NAT-PMP TCP Port Mapping Request (12 bytes)
      // Vers: 0, Opcode: 2 (TCP), Reserved: 0, Internal Port: port, External Port: port, Lifetime: 3600
      final packet = Uint8List(12);
      final bd = ByteData.sublistView(packet);
      bd.setUint8(0, 0); // Version 0
      bd.setUint8(1, 2); // Opcode 2 = TCP
      bd.setUint16(2, 0); // Reserved
      bd.setUint16(4, port); // Internal Port
      bd.setUint16(6, port); // Suggested External Port
      bd.setUint32(8, 3600); // Lifetime in seconds

      socket.send(packet, InternetAddress(gatewayIp), 5351);

      final completer = Completer<UpnpResult?>();
      Timer(const Duration(seconds: 1), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg != null && dg.data.length >= 16) {
            final respView = ByteData.sublistView(dg.data);
            final respCode = respView.getUint16(2);
            if (respCode == 0) { // Success
              final mappedExtPort = respView.getUint16(10);
              completer.complete(UpnpResult(
                isSuccess: true,
                externalPort: mappedExtPort,
                routerModel: 'NAT-PMP Gateway ($gatewayIp)',
                serviceType: 'NAT-PMP',
              ));
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
}
