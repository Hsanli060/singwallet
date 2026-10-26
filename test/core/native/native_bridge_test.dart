import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/native/native_bridge_service.dart';
import 'native_bridge_test.g.dart';

class MockNativeCaptureHostApi implements TestNativeCaptureHostApi {
  CaptureResult? mockPickResult;
  List<CaptureResult> mockPendingCaptures = <CaptureResult>[];
  OcrDocument? mockOcrDocument;
  bool mockDeleteResult = true;
  CaptureResult? mockClipboardResult;
  CaptureResult? mockScreenCaptureResult;
  Uint8List? mockDbKey;

  String? lastRecognizedCaptureId;
  String? lastDeletedCaptureId;
  int pickCallCount = 0;
  int fetchCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<CaptureResult?> pickSingleImage() async {
    pickCallCount++;
    return mockPickResult;
  }

  @override
  List<CaptureResult> fetchPendingExternalCaptures() {
    fetchCallCount++;
    return mockPendingCaptures;
  }

  @override
  Future<OcrDocument> recognizeCapture(String captureId) async {
    lastRecognizedCaptureId = captureId;
    return mockOcrDocument ??
        OcrDocument(
          captureId: captureId,
          lines: <OcrTextLine>[],
          engineIdentifier: 'MockEngine',
          processTimeMs: 42,
        );
  }

  @override
  bool deleteCaptureImage(String captureId) {
    deleteCallCount++;
    lastDeletedCaptureId = captureId;
    return mockDeleteResult;
  }

  @override
  CaptureResult? readImageFromClipboard() {
    return mockClipboardResult;
  }

  @override
  Future<CaptureResult?> startOneShotScreenCapture() async {
    return mockScreenCaptureResult;
  }

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async {
    return mockDbKey ?? Uint8List(32);
  }
}

class _TestFlutterApiReceiver implements NativeCaptureFlutterApi {
  final void Function(CaptureResult capture) onReceived;
  _TestFlutterApiReceiver(this.onReceived);

  @override
  void onExternalCaptureReceived(CaptureResult capture) {
    onReceived(capture);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNativeCaptureHostApi mockApi;
  late NativeCaptureHostApi hostApi;
  late NativeBridgeService service;

  setUp(() {
    mockApi = MockNativeCaptureHostApi();
    TestNativeCaptureHostApi.setUp(mockApi);
    hostApi = NativeCaptureHostApi();
    service = NativeBridgeService(hostApi: hostApi);
  });

  tearDown(() {
    TestNativeCaptureHostApi.setUp(null);
  });

  group('Pigeon NativeCaptureHostApi & Codec Verification', () {
    test('pickSingleImage serializes and returns CaptureResult with valid fields', () async {
      mockApi.mockPickResult = CaptureResult(
        captureId: 'cap_test_001',
        localFilePath: '/data/user/0/com.singwallet.app/files/pending_captures/cap_test_001.jpg',
        imageWidth: 1080,
        imageHeight: 2400,
        contentHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        sourceKind: ImageSourceKind.photoPicker,
      );

      final result = await hostApi.pickSingleImage();

      expect(mockApi.pickCallCount, 1);
      expect(result, isNotNull);
      expect(result!.captureId, 'cap_test_001');
      expect(result.localFilePath, contains('cap_test_001.jpg'));
      expect(result.imageWidth, 1080);
      expect(result.imageHeight, 2400);
      expect(result.sourceKind, ImageSourceKind.photoPicker);
      expect(result.contentHash, contains('e3b0c442'));
    });

    test('pickSingleImage returns null when user cancels selection', () async {
      mockApi.mockPickResult = null;

      final result = await hostApi.pickSingleImage();

      expect(mockApi.pickCallCount, 1);
      expect(result, isNull);
    });

    test('fetchPendingExternalCaptures returns list of pending captures', () async {
      mockApi.mockPendingCaptures = <CaptureResult>[
        CaptureResult(
          captureId: 'cap_share_01',
          localFilePath: '/path/01.jpg',
          imageWidth: 1170,
          imageHeight: 2532,
          contentHash: 'hash01',
          sourceKind: ImageSourceKind.systemShare,
        ),
        CaptureResult(
          captureId: 'cap_share_02',
          localFilePath: '/path/02.jpg',
          imageWidth: 1170,
          imageHeight: 2532,
          contentHash: 'hash02',
          sourceKind: ImageSourceKind.systemShare,
        ),
      ];

      final results = await hostApi.fetchPendingExternalCaptures();

      expect(mockApi.fetchCallCount, 1);
      expect(results.length, 2);
      expect(results[0].captureId, 'cap_share_01');
      expect(results[0].sourceKind, ImageSourceKind.systemShare);
      expect(results[1].captureId, 'cap_share_02');
    });

    test('recognizeCapture returns structured OcrDocument with normalized coordinates', () async {
      final sampleBox = OcrBoundingBox(
        left: 0.1250,
        top: 0.3500,
        width: 0.7500,
        height: 0.0450,
      );

      mockApi.mockOcrDocument = OcrDocument(
        captureId: 'cap_ocr_99',
        lines: <OcrTextLine>[
          OcrTextLine(
            text: '微信支付凭证',
            boundingBox: sampleBox,
            confidence: 0.98,
          ),
          OcrTextLine(
            text: '实付金额 ¥28.90',
            boundingBox: OcrBoundingBox(
              left: 0.2000,
              top: 0.4200,
              width: 0.6000,
              height: 0.0800,
            ),
            confidence: 0.99,
          ),
        ],
        engineIdentifier: 'AppleVision_iOS_17',
        processTimeMs: 185,
      );

      final doc = await hostApi.recognizeCapture('cap_ocr_99');

      expect(mockApi.lastRecognizedCaptureId, 'cap_ocr_99');
      expect(doc.captureId, 'cap_ocr_99');
      expect(doc.lines.length, 2);
      expect(doc.lines[0].text, '微信支付凭证');
      expect(doc.lines[0].boundingBox.left, closeTo(0.1250, 1e-4));
      expect(doc.lines[0].boundingBox.top, closeTo(0.3500, 1e-4));
      expect(doc.lines[0].confidence, closeTo(0.98, 1e-2));
      expect(doc.lines[1].text, '实付金额 ¥28.90');
      expect(doc.engineIdentifier, 'AppleVision_iOS_17');
      expect(doc.processTimeMs, 185);
    });

    test('deleteCaptureImage routes captureId and returns success boolean', () async {
      mockApi.mockDeleteResult = true;

      final success = await hostApi.deleteCaptureImage('cap_to_delete');

      expect(mockApi.deleteCallCount, 1);
      expect(mockApi.lastDeletedCaptureId, 'cap_to_delete');
      expect(success, isTrue);
    });

    test('readImageFromClipboard returns CaptureResult from clipboard', () async {
      mockApi.mockClipboardResult = CaptureResult(
        captureId: 'clip_123',
        localFilePath: '/path/clip.jpg',
        imageWidth: 800,
        imageHeight: 600,
        contentHash: 'clip_hash',
        sourceKind: ImageSourceKind.clipboard,
      );

      final result = await hostApi.readImageFromClipboard();
      expect(result, isNotNull);
      expect(result!.sourceKind, ImageSourceKind.clipboard);
      expect(result.captureId, 'clip_123');
    });

    test('startOneShotScreenCapture returns null on unsupported platforms', () async {
      mockApi.mockScreenCaptureResult = null;

      final result = await hostApi.startOneShotScreenCapture();
      expect(result, isNull);
    });

    test('getOrCreateDatabaseKey returns exact 32-byte Uint8List encryption key', () async {
      final key = Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + 3) % 256));
      mockApi.mockDbKey = key;

      final retrieved = await hostApi.getOrCreateDatabaseKey();

      expect(retrieved.length, 32);
      expect(retrieved, equals(key));
    });
  });

  group('NativeCaptureFlutterApi Verification', () {
    test('receives external capture event via mock dispatch', () async {
      CaptureResult? capturedEvent;
      final receiver = _TestFlutterApiReceiver((CaptureResult capture) {
        capturedEvent = capture;
      });

      NativeCaptureFlutterApi.setUp(receiver);

      final testCapture = CaptureResult(
        captureId: 'event_external_001',
        localFilePath: '/path/event.jpg',
        imageWidth: 1080,
        imageHeight: 1920,
        contentHash: 'hash_ext',
        sourceKind: ImageSourceKind.systemShare,
      );

      receiver.onExternalCaptureReceived(testCapture);

      expect(capturedEvent, isNotNull);
      expect(capturedEvent!.captureId, 'event_external_001');
      expect(capturedEvent!.sourceKind, ImageSourceKind.systemShare);

      NativeCaptureFlutterApi.setUp(null);
    });
  });

  group('NativeBridgeService Wrapper Verification', () {
    test('service delegates pickSingleImage successfully', () async {
      mockApi.mockPickResult = CaptureResult(
        captureId: 'cap_srv_01',
        localFilePath: '/path/img.png',
        imageWidth: 500,
        imageHeight: 500,
        contentHash: 'hash_srv',
        sourceKind: ImageSourceKind.photoPicker,
      );

      final res = await service.pickSingleImage();
      expect(res, isNotNull);
      expect(res!.captureId, 'cap_srv_01');
    });

    test('service delegates getOrCreateDatabaseKey successfully', () async {
      final key = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      mockApi.mockDbKey = key;

      final retrieved = await service.getOrCreateDatabaseKey();
      expect(retrieved.length, 32);
      expect(retrieved, equals(key));
    });

    test('service delegates recognizeCapture successfully', () async {
      final doc = await service.recognizeCapture('cap_srv_ocr');
      expect(doc.captureId, 'cap_srv_ocr');
      expect(doc.engineIdentifier, 'MockEngine');
    });

    test('service delegates deleteCaptureImage successfully', () async {
      final deleted = await service.deleteCaptureImage('cap_srv_del');
      expect(deleted, isTrue);
    });

    test('service delegates fetchPendingExternalCaptures successfully', () async {
      final list = await service.fetchPendingExternalCaptures();
      expect(list, isEmpty);
    });
  });
}
