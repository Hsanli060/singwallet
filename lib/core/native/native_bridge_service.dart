import 'dart:async';
import 'package:flutter/services.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';

/// Domain exception for native host bridge failures
class NativeBridgeException implements Exception {
  final String code;
  final String message;
  final Object? details;

  NativeBridgeException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'NativeBridgeException($code): $message';
}

class _NativeCaptureFlutterApiHandler implements NativeCaptureFlutterApi {
  final void Function(CaptureResult capture) onCapture;

  _NativeCaptureFlutterApiHandler(this.onCapture);

  @override
  void onExternalCaptureReceived(CaptureResult capture) {
    onCapture(capture);
  }
}

/// High-level service managing platform-native screenshot ingestion and OCR
class NativeBridgeService {
  final NativeCaptureHostApi _hostApi;
  final StreamController<CaptureResult> _externalCaptureController =
      StreamController<CaptureResult>.broadcast();

  bool _isFlutterBridgeInitialized = false;

  NativeBridgeService({NativeCaptureHostApi? hostApi})
      : _hostApi = hostApi ?? NativeCaptureHostApi();

  /// Stream of captures received from external shares or shortcuts while app is running
  Stream<CaptureResult> get externalCaptures => _externalCaptureController.stream;

  /// Registers NativeCaptureFlutterApi to listen for incoming system share notifications
  void initializeFlutterBridge({BinaryMessenger? binaryMessenger}) {
    if (_isFlutterBridgeInitialized) return;
    NativeCaptureFlutterApi.setUp(
      _NativeCaptureFlutterApiHandler((capture) {
        _externalCaptureController.add(capture);
      }),
      binaryMessenger: binaryMessenger,
    );
    _isFlutterBridgeInitialized = true;
  }

  /// Tear down listeners
  void dispose() {
    _externalCaptureController.close();
    NativeCaptureFlutterApi.setUp(null);
    _isFlutterBridgeInitialized = false;
  }

  /// Pick single image via platform photo picker
  Future<CaptureResult?> pickSingleImage() async {
    try {
      return await _hostApi.pickSingleImage();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to pick single image',
        details: e.details,
      );
    }
  }

  /// Fetch pending external captures from Share sheet / App Group
  Future<List<CaptureResult>> fetchPendingExternalCaptures() async {
    try {
      return await _hostApi.fetchPendingExternalCaptures();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to fetch pending captures',
        details: e.details,
      );
    }
  }

  /// Run native offline OCR (ML Kit on Android / Vision on iOS)
  Future<OcrDocument> recognizeCapture(String captureId) async {
    try {
      return await _hostApi.recognizeCapture(captureId);
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to execute OCR for capture: $captureId',
        details: e.details,
      );
    }
  }

  /// Delete cached screenshot image from private storage
  Future<bool> deleteCaptureImage(String captureId) async {
    try {
      return await _hostApi.deleteCaptureImage(captureId);
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to delete capture: $captureId',
        details: e.details,
      );
    }
  }

  /// Read image from system clipboard
  Future<CaptureResult?> readImageFromClipboard() async {
    try {
      return await _hostApi.readImageFromClipboard();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to read image from clipboard',
        details: e.details,
      );
    }
  }

  /// Android one-shot screen capture (returns null on iOS or user cancel)
  Future<CaptureResult?> startOneShotScreenCapture() async {
    try {
      return await _hostApi.startOneShotScreenCapture();
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return null;
      }
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to execute one-shot screen capture',
        details: e.details,
      );
    }
  }

  /// Derive or retrieve 256-bit AES database key from Keystore/Keychain
  Future<Uint8List> getOrCreateDatabaseKey() async {
    try {
      return await _hostApi.getOrCreateDatabaseKey();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to access hardware database key',
        details: e.details,
      );
    }
  }
}
