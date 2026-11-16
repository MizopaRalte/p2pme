import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  final String title;
  final String prompt;

  const QrScannerScreen({
    super.key,
    this.title = 'Scan Server QR Code',
    this.prompt = 'Point camera at the QR code displayed in Tab 3 (Server)',
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _isHandlingBarcode = false;
  bool _isTorchOn = false;
  bool _isAnalyzingImage = false;

  bool get _isCameraPlatform {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: _isCameraPlatform,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isHandlingBarcode) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue?.trim();
    if (value != null && value.isNotEmpty) {
      _isHandlingBarcode = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(value);
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (_isAnalyzingImage) return;
    setState(() => _isAnalyzingImage = true);

    try {
      final res = await FilePicker.pickFiles(type: FileType.image);
      if (res.isNotEmpty && res.first.path != null) {
        final path = res.first.path!;
        final barcodes = await _controller.analyzeImage(path);
        final found = barcodes?.barcodes.firstOrNull?.rawValue?.trim();
        if (found != null && found.isNotEmpty) {
          if (mounted) {
            HapticFeedback.mediumImpact();
            Navigator.of(context).pop(found);
          }
          return;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No QR code detected in the selected image.'),
                backgroundColor: Color(0xFFD93025),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not scan image: $e'),
            backgroundColor: const Color(0xFFD93025),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isCameraPlatform) ...[
            IconButton(
              icon: Icon(
                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isTorchOn ? const Color(0xFFF9AB00) : Colors.white70,
              ),
              tooltip: 'Toggle Flashlight',
              onPressed: () async {
                try {
                  await _controller.toggleTorch();
                  setState(() => _isTorchOn = !_isTorchOn);
                } catch (_) {}
              },
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white70),
              tooltip: 'Switch Camera',
              onPressed: () => _controller.switchCamera(),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (_isCameraPlatform)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              fit: BoxFit.cover,
              errorBuilder: (ctx, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Card(
                      color: const Color(0xFF202124),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              size: 48,
                              color: Color(0xFFEA4335),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Camera Access Unavailable',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Camera permission might be disabled or unavailable on this device.\n\nError: ${error.errorCode}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                              ),
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text('Pick QR from Photos'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            // Desktop fallback view
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  color: const Color(0xFF202124),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.qr_code_scanner,
                          size: 56,
                          color: Color(0xFF1A73E8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Desktop QR Scanner',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Select a screenshot or image of the Server QR code from disk to pair instantly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A73E8),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: _pickImageFromGallery,
                          icon: const Icon(Icons.file_upload, size: 18),
                          label: const Text('Select QR Image File'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Google Lens / Google Photos Viewfinder Overlay
          if (_isCameraPlatform)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.8),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Corner highlight brackets
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFF1A73E8), width: 4),
                                left: BorderSide(color: Color(0xFF1A73E8), width: 4),
                              ),
                              borderRadius: BorderRadius.only(topLeft: Radius.circular(22)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFF1A73E8), width: 4),
                                right: BorderSide(color: Color(0xFF1A73E8), width: 4),
                              ),
                              borderRadius: BorderRadius.only(topRight: Radius.circular(22)),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFF1A73E8), width: 4),
                                left: BorderSide(color: Color(0xFF1A73E8), width: 4),
                              ),
                              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(22)),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFF1A73E8), width: 4),
                                right: BorderSide(color: Color(0xFF1A73E8), width: 4),
                              ),
                              borderRadius: BorderRadius.only(bottomRight: Radius.circular(22)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.prompt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Action Bar: Pick from Gallery & Manual IP
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _pickImageFromGallery,
                    icon: _isAnalyzingImage
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Pick Image', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 14),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF303134),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop('MANUAL_ENTRY'),
                    child: const Text('Enter Manually', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
