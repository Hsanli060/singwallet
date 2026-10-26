import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/native/native_bridge_service.dart';

class MockNativeCaptureHostApi implements NativeCaptureHostApi {
  CaptureResult? pickedImageResult;
  List<CaptureResult> pendingCaptures = [];
  OcrDocument? ocrDocResult;
  bool deleteResult = true;
  CaptureResult? clipboardResult;
  CaptureResult? oneShotResult;
  Uint8List dbKeyResult = Uint8List.fromList(List.generate(32, (i) => i));

  @override
  // ignore: non_constant_identifier_names
  final BinaryMessenger? pigeonVar_binaryMessenger = null;

  @override
  // ignore: non_constant_identifier_names
  final String pigeonVar_messageChannelSuffix = '';

  @override
  Future<CaptureResult?> pickSingleImage() async => pickedImageResult;

  @override
  Future<List<CaptureResult>> fetchPendingExternalCaptures() async => pendingCaptures;

  @override
  Future<OcrDocument> recognizeCapture(String captureId) async {
    return ocrDocResult ??
        OcrDocument(
          captureId: captureId,
          lines: [],
          engineIdentifier: 'MockEngine',
          processTimeMs: 10,
        );
  }

  @override
  Future<bool> deleteCaptureImage(String captureId) async => deleteResult;

  @override
  Future<CaptureResult?> readImageFromClipboard() async => clipboardResult;

  @override
  Future<CaptureResult?> startOneShotScreenCapture() async => oneShotResult;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async => dbKeyResult;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeBridgeService Tests', () {
    late MockNativeCaptureHostApi mockApi;
    late NativeBridgeService service;

    setUp(() {
      mockApi = MockNativeCaptureHostApi();
      service = NativeBridgeService(hostApi: mockApi);
      service.initializeFlutterBridge();
    });

    tearDown(() {
      service.dispose();
    });

    test('pickSingleImage forwards call to hostApi', () async {
      final sample = CaptureResult(
        captureId: 'cap_001',
        localFilePath: '/path/to/img.jpg',
        imageWidth: 1080,
        imageHeight: 2400,
        contentHash: 'hash123',
        sourceKind: ImageSourceKind.photoPicker,
      );
      mockApi.pickedImageResult = sample;

      final res = await service.pickSingleImage();
      expect(res, isNotNull);
      expect(res!.captureId, 'cap_001');
      expect(res.sourceKind, ImageSourceKind.photoPicker);
    });

    test('fetchPendingExternalCaptures forwards call and returns list', () async {
      mockApi.pendingCaptures = [
        CaptureResult(
          captureId: 'share_1',
          localFilePath: '/path/1.jpg',
          imageWidth: 800,
          imageHeight: 1200,
          contentHash: 'hash1',
          sourceKind: ImageSourceKind.systemShare,
        ),
      ];

      final list = await service.fetchPendingExternalCaptures();
      expect(list.length, 1);
      expect(list.first.captureId, 'share_1');
      expect(list.first.sourceKind, ImageSourceKind.systemShare);
    });

    test('recognizeCapture returns structured OcrDocument', () async {
      mockApi.ocrDocResult = OcrDocument(
        captureId: 'cap_ocr_1',
        lines: [
          OcrTextLine(
            text: '¥88.50',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.05),
            confidence: 0.99,
          ),
        ],
        engineIdentifier: 'MLKit_Android_Chinese_v1',
        processTimeMs: 45,
      );

      final doc = await service.recognizeCapture('cap_ocr_1');
      expect(doc.captureId, 'cap_ocr_1');
      expect(doc.lines.length, 1);
      expect(doc.lines.first.text, '¥88.50');
      expect(doc.lines.first.confidence, 0.99);
      expect(doc.engineIdentifier, 'MLKit_Android_Chinese_v1');
    });

    test('readImageFromClipboard and deleteCaptureImage behave as expected', () async {
      final clip = CaptureResult(
        captureId: 'clip_01',
        localFilePath: '/tmp/clip.jpg',
        imageWidth: 500,
        imageHeight: 500,
        contentHash: 'cliphash',
        sourceKind: ImageSourceKind.clipboard,
      );
      mockApi.clipboardResult = clip;

      final clipRes = await service.readImageFromClipboard();
      expect(clipRes?.captureId, 'clip_01');

      final deleted = await service.deleteCaptureImage('clip_01');
      expect(deleted, isTrue);
    });

    test('getOrCreateDatabaseKey returns 32 bytes AES master key', () async {
      final key = await service.getOrCreateDatabaseKey();
      expect(key.length, 32);
    });

    test('externalCaptures stream emits incoming share notifications', () async {
      final testCapture = CaptureResult(
        captureId: 'wechat_share_999',
        localFilePath: '/data/user/0/com.singwallet.app/files/pending_captures/wechat_share_999.jpg',
        imageWidth: 1080,
        imageHeight: 2400,
        contentHash: 'wechat_sha256_hash',
        sourceKind: ImageSourceKind.systemShare,
      );

      final expectation = expectLater(
        service.externalCaptures,
        emits(predicate<CaptureResult>((cap) => cap.captureId == 'wechat_share_999')),
      );

      // Simulate incoming Pigeon callback from native Android/iOS
      const channelName = 'dev.flutter.pigeon.singwallet.NativeCaptureFlutterApi.onExternalCaptureReceived';
      const codec = NativeCaptureFlutterApi.pigeonChannelCodec;
      final encoded = codec.encodeMessage([testCapture]);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        encoded,
        (ByteData? reply) {
          // ack received
        },
      );

      await expectation;
    });
  });
}
