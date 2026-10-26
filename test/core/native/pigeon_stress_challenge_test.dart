import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/native/native_bridge_service.dart';
import 'native_bridge_test.g.dart';

/// Adversarial Mock HostApi for stress testing boundary conditions and error injection
class AdversarialMockNativeCaptureHostApi implements TestNativeCaptureHostApi {
  // Method handlers or injected exceptions
  CaptureResult? Function()? pickSingleImageHandler;
  List<CaptureResult> Function()? fetchPendingExternalCapturesHandler;
  Future<OcrDocument> Function(String captureId)? recognizeCaptureHandler;
  bool Function(String captureId)? deleteCaptureImageHandler;
  CaptureResult? Function()? readImageFromClipboardHandler;
  Future<CaptureResult?> Function()? startOneShotScreenCaptureHandler;
  Future<Uint8List> Function()? getOrCreateDatabaseKeyHandler;

  @override
  Future<CaptureResult?> pickSingleImage() async {
    if (pickSingleImageHandler != null) {
      return pickSingleImageHandler!();
    }
    return null;
  }

  @override
  List<CaptureResult> fetchPendingExternalCaptures() {
    if (fetchPendingExternalCapturesHandler != null) {
      return fetchPendingExternalCapturesHandler!();
    }
    return <CaptureResult>[];
  }

  @override
  Future<OcrDocument> recognizeCapture(String captureId) async {
    if (recognizeCaptureHandler != null) {
      return recognizeCaptureHandler!(captureId);
    }
    return OcrDocument(
      captureId: captureId,
      lines: <OcrTextLine>[],
      engineIdentifier: 'AdversarialEngine',
      processTimeMs: 1,
    );
  }

  @override
  bool deleteCaptureImage(String captureId) {
    if (deleteCaptureImageHandler != null) {
      return deleteCaptureImageHandler!(captureId);
    }
    return true;
  }

  @override
  CaptureResult? readImageFromClipboard() {
    if (readImageFromClipboardHandler != null) {
      return readImageFromClipboardHandler!();
    }
    return null;
  }

  @override
  Future<CaptureResult?> startOneShotScreenCapture() async {
    if (startOneShotScreenCaptureHandler != null) {
      return startOneShotScreenCaptureHandler!();
    }
    return null;
  }

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async {
    if (getOrCreateDatabaseKeyHandler != null) {
      return getOrCreateDatabaseKeyHandler!();
    }
    return Uint8List(32);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MessageCodec<Object?> codec = NativeCaptureHostApi.pigeonChannelCodec;

  late AdversarialMockNativeCaptureHostApi mockApi;
  late NativeCaptureHostApi hostApi;
  late NativeBridgeService service;

  setUp(() {
    mockApi = AdversarialMockNativeCaptureHostApi();
    TestNativeCaptureHostApi.setUp(mockApi);
    hostApi = NativeCaptureHostApi();
    service = NativeBridgeService(hostApi: hostApi);
  });

  tearDown(() {
    TestNativeCaptureHostApi.setUp(null);
  });

  group('1. Pigeon Codec Serialization Fidelity & Boundary Stress', () {
    test('ImageSourceKind: roundtrip all enum values', () {
      for (final kind in ImageSourceKind.values) {
        final ByteData? data = codec.encodeMessage(kind);
        expect(data, isNotNull);
        final Object? decoded = codec.decodeMessage(data);
        expect(decoded, equals(kind));
        expect((decoded as ImageSourceKind).index, equals(kind.index));
      }
    });

    test('OcrBoundingBox: standard normalized coordinates roundtrip fidelity', () {
      final box = OcrBoundingBox(
        left: 0.12345678901234567,
        top: 0.9876543210987654,
        width: 0.5555555555555556,
        height: 0.4444444444444444,
      );

      final ByteData? data = codec.encodeMessage(box);
      expect(data, isNotNull);
      final decoded = codec.decodeMessage(data) as OcrBoundingBox;

      // IEEE 754 double precision preservation
      expect(decoded.left, equals(box.left));
      expect(decoded.top, equals(box.top));
      expect(decoded.width, equals(box.width));
      expect(decoded.height, equals(box.height));
    });

    test('OcrBoundingBox: boundary inputs (0.0, 1.0, extreme values, infinity, NaN)', () {
      final boundaryBoxes = <OcrBoundingBox>[
        OcrBoundingBox(left: 0.0, top: 0.0, width: 0.0, height: 0.0),
        OcrBoundingBox(left: 1.0, top: 1.0, width: 1.0, height: 1.0),
        // Coordinates outside [0, 1] - codec must preserve raw values without crashing or clipping
        OcrBoundingBox(left: -100.5, top: -999.0, width: 5000.25, height: 10000.75),
        // Extreme finite IEEE-754 doubles
        OcrBoundingBox(
          left: double.maxFinite,
          top: -double.maxFinite,
          width: double.minPositive,
          height: -double.minPositive,
        ),
        // Infinities
        OcrBoundingBox(
          left: double.infinity,
          top: -double.infinity,
          width: double.infinity,
          height: -double.infinity,
        ),
        // NaN
        OcrBoundingBox(
          left: double.nan,
          top: double.nan,
          width: double.nan,
          height: double.nan,
        ),
      ];

      for (final box in boundaryBoxes) {
        final data = codec.encodeMessage(box);
        expect(data, isNotNull);
        final decoded = codec.decodeMessage(data) as OcrBoundingBox;

        if (box.left.isNaN) {
          expect(decoded.left.isNaN, isTrue);
          expect(decoded.top.isNaN, isTrue);
          expect(decoded.width.isNaN, isTrue);
          expect(decoded.height.isNaN, isTrue);
        } else {
          expect(decoded.left, equals(box.left));
          expect(decoded.top, equals(box.top));
          expect(decoded.width, equals(box.width));
          expect(decoded.height, equals(box.height));
        }
      }
    });

    test('CaptureResult: boundary inputs (empty strings, huge strings, int64 limits, unicode)', () {
      final hugeString = 'X' * 65536; // 64KB string
      const unicodeEmojiString = '💸 微信支付 \u{1F4B3} 支付宝 \u0000 NULL_BYTE \t\r\n 汉字测试';

      final testCases = <CaptureResult>[
        // Minimal / empty fields
        CaptureResult(
          captureId: '',
          localFilePath: '',
          imageWidth: 0,
          imageHeight: 0,
          contentHash: '',
          sourceKind: ImageSourceKind.systemShare,
        ),
        // Negative dimensions & extreme 64-bit integer values
        CaptureResult(
          captureId: 'extreme_int_id',
          localFilePath: '/path/extreme.jpg',
          imageWidth: -1,
          imageHeight: -9223372036854775808, // min int64
          contentHash: 'hash_neg',
          sourceKind: ImageSourceKind.quickSettingsTile,
        ),
        CaptureResult(
          captureId: 'max_int_id',
          localFilePath: '/path/max.jpg',
          imageWidth: 9223372036854775807, // max int64
          imageHeight: 2147483647, // max int32
          contentHash: 'hash_max',
          sourceKind: ImageSourceKind.photoPicker,
        ),
        // Huge payload & unicode preservation
        CaptureResult(
          captureId: hugeString,
          localFilePath: unicodeEmojiString,
          imageWidth: 1080,
          imageHeight: 2400,
          contentHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          sourceKind: ImageSourceKind.clipboard,
        ),
      ];

      for (final item in testCases) {
        final data = codec.encodeMessage(item);
        expect(data, isNotNull);
        final decoded = codec.decodeMessage(data) as CaptureResult;

        expect(decoded.captureId, equals(item.captureId));
        expect(decoded.localFilePath, equals(item.localFilePath));
        expect(decoded.imageWidth, equals(item.imageWidth));
        expect(decoded.imageHeight, equals(item.imageHeight));
        expect(decoded.contentHash, equals(item.contentHash));
        expect(decoded.sourceKind, equals(item.sourceKind));
      }
    });

    test('OcrTextLine: nullable confidence handling and extreme text strings', () {
      final cases = <OcrTextLine>[
        OcrTextLine(
          text: '',
          boundingBox: OcrBoundingBox(left: 0, top: 0, width: 0, height: 0),
          confidence: null,
        ),
        OcrTextLine(
          text: 'Null confidence line',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.8, height: 0.05),
          confidence: null,
        ),
        OcrTextLine(
          text: 'Zero confidence line',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.8, height: 0.05),
          confidence: 0.0,
        ),
        OcrTextLine(
          text: 'Max confidence line',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.8, height: 0.05),
          confidence: 1.0,
        ),
        OcrTextLine(
          text: 'Out-of-range confidence line',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.8, height: 0.05),
          confidence: -99.9,
        ),
        OcrTextLine(
          text: 'Complex unicode / RTL text: العربية 🇨🇳 ¥12,345.67',
          boundingBox: OcrBoundingBox(left: 0.05, top: 0.5, width: 0.9, height: 0.1),
          confidence: 0.99999,
        ),
      ];

      for (final line in cases) {
        final data = codec.encodeMessage(line);
        expect(data, isNotNull);
        final decoded = codec.decodeMessage(data) as OcrTextLine;

        expect(decoded.text, equals(line.text));
        expect(decoded.boundingBox.left, equals(line.boundingBox.left));
        expect(decoded.confidence, equals(line.confidence));
      }
    });

    test('OcrDocument: empty lines and massive document stress test (1,000 lines)', () {
      // Empty document
      final emptyDoc = OcrDocument(
        captureId: 'doc_empty',
        lines: <OcrTextLine>[],
        engineIdentifier: 'TestEngine_v0',
        processTimeMs: 0,
      );

      final emptyData = codec.encodeMessage(emptyDoc);
      expect(emptyData, isNotNull);
      final decodedEmpty = codec.decodeMessage(emptyData) as OcrDocument;
      expect(decodedEmpty.lines, isEmpty);
      expect(decodedEmpty.captureId, 'doc_empty');
      expect(decodedEmpty.processTimeMs, 0);

      // Massive document: 1,000 OCR lines
      final largeLines = List<OcrTextLine>.generate(1000, (int index) {
        return OcrTextLine(
          text: 'Line #$index: 消费详情测试 ¥${(index * 12.34).toStringAsFixed(2)}',
          boundingBox: OcrBoundingBox(
            left: (index % 10) * 0.1,
            top: (index / 1000.0),
            width: 0.09,
            height: 0.001,
          ),
          confidence: (index % 100) / 100.0,
        );
      });

      final bigDoc = OcrDocument(
        captureId: 'doc_big_1000',
        lines: largeLines,
        engineIdentifier: 'AppleVision_iOS_17_Massive',
        processTimeMs: 987654321,
      );

      final bigData = codec.encodeMessage(bigDoc);
      expect(bigData, isNotNull);
      final decodedBig = codec.decodeMessage(bigData) as OcrDocument;

      expect(decodedBig.lines.length, 1000);
      expect(decodedBig.captureId, 'doc_big_1000');
      expect(decodedBig.engineIdentifier, 'AppleVision_iOS_17_Massive');
      expect(decodedBig.processTimeMs, 987654321);
      expect(decodedBig.lines[500].text, contains('Line #500:'));
      expect(decodedBig.lines[999].confidence, closeTo(99 / 100.0, 1e-6));
    });

    test('Uint8List: database master key byte sizes (0, 32, 64, 1MB buffer)', () {
      final keySizes = [0, 32, 64, 1024, 65536];

      for (final size in keySizes) {
        final randomBytes = Uint8List(size);
        for (int i = 0; i < size; i++) {
          randomBytes[i] = (i * 31 + 17) % 256;
        }

        final data = codec.encodeMessage(randomBytes);
        expect(data, isNotNull);
        final decoded = codec.decodeMessage(data) as Uint8List;

        expect(decoded.length, size);
        expect(decoded, equals(randomBytes));
      }
    });
  });

  group('2. HostApi Error Paths & NativeBridgeException Mappings', () {
    test('pickSingleImage: PlatformException wraps into NativeBridgeException', () async {
      mockApi.pickSingleImageHandler = () {
        throw PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'Read storage permission was permanently denied',
          details: {'permission': 'READ_EXTERNAL_STORAGE'},
        );
      };

      expect(
        () async => await service.pickSingleImage(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'PERMISSION_DENIED')
            .having((e) => e.message, 'message', contains('permanently denied'))
            .having((e) => e.details, 'details', isNotNull)),
      );
    });

    test('fetchPendingExternalCaptures: PlatformException wraps into NativeBridgeException', () async {
      mockApi.fetchPendingExternalCapturesHandler = () {
        throw PlatformException(
          code: 'APP_GROUP_UNAVAILABLE',
          message: 'Cannot access shared container',
        );
      };

      expect(
        () async => await service.fetchPendingExternalCaptures(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'APP_GROUP_UNAVAILABLE')
            .having((e) => e.message, 'message', contains('Cannot access shared container'))),
      );
    });

    test('recognizeCapture: PlatformException with FILE_NOT_FOUND', () async {
      mockApi.recognizeCaptureHandler = (String id) async {
        throw PlatformException(
          code: 'FILE_NOT_FOUND',
          message: 'Capture image not found for id: $id',
        );
      };

      expect(
        () async => await service.recognizeCapture('non_existent_id'),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'FILE_NOT_FOUND')
            .having((e) => e.message, 'message', contains('non_existent_id'))),
      );
    });

    test('deleteCaptureImage: PlatformException wraps into NativeBridgeException', () async {
      mockApi.deleteCaptureImageHandler = (String id) {
        throw PlatformException(
          code: 'FILE_LOCKED',
          message: 'Cannot delete active file: $id',
        );
      };

      expect(
        () async => await service.deleteCaptureImage('locked_file_id'),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'FILE_LOCKED')),
      );
    });

    test('readImageFromClipboard: PlatformException wraps into NativeBridgeException', () async {
      mockApi.readImageFromClipboardHandler = () {
        throw PlatformException(
          code: 'CLIPBOARD_EMPTY',
          message: 'No image or URI in clipboard',
        );
      };

      expect(
        () async => await service.readImageFromClipboard(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'CLIPBOARD_EMPTY')),
      );
    });

    test('startOneShotScreenCapture: UNSUPPORTED gracefully returns null without throwing', () async {
      mockApi.startOneShotScreenCaptureHandler = () async {
        throw PlatformException(
          code: 'UNSUPPORTED',
          message: 'One-shot screen capture is unsupported on iOS',
        );
      };

      // Service contract explicitly states: UNSUPPORTED returns null
      final result = await service.startOneShotScreenCapture();
      expect(result, isNull);
    });

    test('startOneShotScreenCapture: other PlatformException throws NativeBridgeException', () async {
      mockApi.startOneShotScreenCaptureHandler = () async {
        throw PlatformException(
          code: 'MEDIA_PROJECTION_DENIED',
          message: 'User denied screen projection prompt',
        );
      };

      expect(
        () async => await service.startOneShotScreenCapture(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'MEDIA_PROJECTION_DENIED')),
      );
    });

    test('getOrCreateDatabaseKey: PlatformException from KeyStore wraps into NativeBridgeException', () async {
      mockApi.getOrCreateDatabaseKeyHandler = () async {
        throw PlatformException(
          code: 'KEYSTORE_FAILED',
          message: 'Hardware Keystore is locked or uninitialized',
        );
      };

      expect(
        () async => await service.getOrCreateDatabaseKey(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'KEYSTORE_FAILED')
            .having((e) => e.message, 'message', contains('Hardware Keystore is locked'))),
      );
    });
  });

  group('3. FlutterApi Native->Flutter Invocations & Error Resilience', () {
    test('NativeCaptureFlutterApi handles incoming event and catches exceptions gracefully', () async {
      bool handlerInvoked = false;
      CaptureResult? receivedPayload;

      final testHandler = _AdversarialFlutterApiHandler(
        onReceive: (CaptureResult capture) {
          handlerInvoked = true;
          receivedPayload = capture;
        },
      );

      NativeCaptureFlutterApi.setUp(testHandler);

      const String channelName = 'dev.flutter.pigeon.singwallet.NativeCaptureFlutterApi.onExternalCaptureReceived';

      final sampleCapture = CaptureResult(
        captureId: 'ext_event_adversarial_01',
        localFilePath: '/shared/ext.png',
        imageWidth: 1080,
        imageHeight: 2340,
        contentHash: 'hash_adv',
        sourceKind: ImageSourceKind.shortcutsAction,
      );

      final ByteData? encodedMessage = NativeCaptureFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[sampleCapture]);
      expect(encodedMessage, isNotNull);

      ByteData? replyData;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        encodedMessage,
        (ByteData? data) {
          replyData = data;
        },
      );

      expect(handlerInvoked, isTrue);
      expect(receivedPayload, isNotNull);
      expect(receivedPayload!.captureId, 'ext_event_adversarial_01');
      expect(receivedPayload!.sourceKind, ImageSourceKind.shortcutsAction);
      expect(replyData, isNotNull);
      final decodedReply = NativeCaptureFlutterApi.pigeonChannelCodec.decodeMessage(replyData);
      expect(decodedReply, isA<List<Object?>>());
      expect((decodedReply as List<Object?>).isEmpty, isTrue);

      NativeCaptureFlutterApi.setUp(null);
    });

    test('NativeCaptureFlutterApi error propagation when Flutter callback throws', () async {
      final crashingHandler = _AdversarialFlutterApiHandler(
        onReceive: (CaptureResult capture) {
          throw FormatException('Corrupt capture image format: ${capture.captureId}');
        },
      );

      NativeCaptureFlutterApi.setUp(crashingHandler);

      const String channelName = 'dev.flutter.pigeon.singwallet.NativeCaptureFlutterApi.onExternalCaptureReceived';

      final sampleCapture = CaptureResult(
        captureId: 'crash_capture',
        localFilePath: '/shared/bad.png',
        imageWidth: 0,
        imageHeight: 0,
        contentHash: 'bad_hash',
        sourceKind: ImageSourceKind.systemShare,
      );

      final ByteData? encodedMessage = NativeCaptureFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[sampleCapture]);
      ByteData? replyData;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        encodedMessage,
        (ByteData? data) {
          replyData = data;
        },
      );

      expect(replyData, isNotNull);
      final decodedReply = NativeCaptureFlutterApi.pigeonChannelCodec.decodeMessage(replyData);
      expect(decodedReply, isA<List<Object?>>());
      final replyList = decodedReply as List<Object?>;
      expect(replyList.length, 3);
      expect(replyList[0], 'error');
      expect(replyList[1].toString(), contains('FormatException: Corrupt capture image format'));

      NativeCaptureFlutterApi.setUp(null);
    });

    test('NativeCaptureFlutterApi error propagation when Flutter callback throws PlatformException', () async {
      final platformExHandler = _AdversarialFlutterApiHandler(
        onReceive: (CaptureResult capture) {
          throw PlatformException(
            code: 'STORAGE_FULL',
            message: 'Disk space exhausted on incoming share',
            details: 101,
          );
        },
      );

      NativeCaptureFlutterApi.setUp(platformExHandler);

      const String channelName = 'dev.flutter.pigeon.singwallet.NativeCaptureFlutterApi.onExternalCaptureReceived';

      final sampleCapture = CaptureResult(
        captureId: 'storage_full_capture',
        localFilePath: '/shared/full.png',
        imageWidth: 100,
        imageHeight: 100,
        contentHash: 'hash_full',
        sourceKind: ImageSourceKind.systemShare,
      );

      final ByteData? encodedMessage = NativeCaptureFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[sampleCapture]);
      ByteData? replyData;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        encodedMessage,
        (ByteData? data) {
          replyData = data;
        },
      );

      expect(replyData, isNotNull);
      final decodedReply = NativeCaptureFlutterApi.pigeonChannelCodec.decodeMessage(replyData);
      expect(decodedReply, isA<List<Object?>>());
      final replyList = decodedReply as List<Object?>;
      expect(replyList.length, 3);
      expect(replyList[0], 'STORAGE_FULL');
      expect(replyList[1], 'Disk space exhausted on incoming share');
      expect(replyList[2], 101);

      NativeCaptureFlutterApi.setUp(null);
    });
  });

  group('4. Coordinate Normalization Mathematical Equivalence & Clamp Invariance', () {
    test('Vision coordinate mapping top clamp invariance: 1.0 - y - height', () {
      // Vision coordinate (origin bottom-left, y upwards) -> Flutter top-left
      // Formula: flutterTop = max(0.0, min(1.0, 1.0 - visionY - visionHeight))
      double visionToFlutterTop(double y, double height) {
        return max(0.0, min(1.0, 1.0 - y - height));
      }

      // Element at very bottom of screen in Vision (y=0, h=0.1) -> Flutter top=0.9
      expect(visionToFlutterTop(0.0, 0.1), closeTo(0.9, 1e-9));

      // Element at very top of screen in Vision (y=0.9, h=0.1) -> Flutter top=0.0
      expect(visionToFlutterTop(0.9, 0.1), closeTo(0.0, 1e-9));

      // Element covering whole screen (y=0, h=1.0) -> Flutter top=0.0
      expect(visionToFlutterTop(0.0, 1.0), closeTo(0.0, 1e-9));

      // Out of bounds: y + height > 1.0 (clamped to 0.0)
      expect(visionToFlutterTop(0.95, 0.2), equals(0.0));

      // Negative origin (clamped to 1.0 max)
      expect(visionToFlutterTop(-0.5, 0.1), equals(1.0));
    });

    test('Android ML Kit pixel normalization to Flutter top-left [0.0, 1.0]', () {
      OcrBoundingBox mlKitToNormalized({
        required int imgW,
        required int imgH,
        required int left,
        required int top,
        required int right,
        required int bottom,
      }) {
        final w = right - left;
        final h = bottom - top;
        return OcrBoundingBox(
          left: max(0.0, min(1.0, left / imgW)),
          top: max(0.0, min(1.0, top / imgH)),
          width: max(0.0, min(1.0, w / imgW)),
          height: max(0.0, min(1.0, h / imgH)),
        );
      }

      final box = mlKitToNormalized(
        imgW: 1080,
        imgH: 2400,
        left: 108,
        top: 480,
        right: 972,
        bottom: 720,
      );

      expect(box.left, closeTo(0.10, 1e-4));
      expect(box.top, closeTo(0.20, 1e-4));
      expect(box.width, closeTo(0.80, 1e-4));
      expect(box.height, closeTo(0.10, 1e-4));
    });
  });

  group('5. Payload Corruption Failsafe & Fast-Fail Verification', () {
    test('CaptureResult.decode fails fast on truncated or null-injected list', () {
      // Missing fields (truncated)
      expect(() => CaptureResult.decode(<Object?>['cap_1', '/path']), throwsA(isA<RangeError>()));

      // Type mismatch (passing int where String is expected)
      expect(() => CaptureResult.decode(<Object?>[12345, '/path', 100, 100, 'hash', ImageSourceKind.photoPicker]), throwsA(isA<TypeError>()));

      // Null injection into required non-nullable field
      expect(() => CaptureResult.decode(<Object?>[null, '/path', 100, 100, 'hash', ImageSourceKind.photoPicker]), throwsA(isA<TypeError>()));
    });

    test('OcrBoundingBox.decode fails fast on non-double or missing coordinate fields', () {
      // Missing field
      expect(() => OcrBoundingBox.decode(<Object?>[0.1, 0.2, 0.3]), throwsA(isA<RangeError>()));

      // Null field
      expect(() => OcrBoundingBox.decode(<Object?>[null, 0.2, 0.3, 0.4]), throwsA(isA<TypeError>()));

      // Passing integer instead of double fails fast via Dart strong mode type safety
      expect(() => OcrBoundingBox.decode(<Object?>[0, 0, 1, 1]), throwsA(isA<TypeError>()));
    });

    test('OcrDocument.decode fails fast when lines list contains malformed elements', () {
      // Passing non-OcrTextLine in lines list
      final malformedList = <Object?>[
        'doc_bad',
        <Object?>['not_a_text_line'],
        'Engine',
        100,
      ];
      // Note: Dart's .cast<OcrTextLine>() creates a lazy CastList.
      // Accessing elements eagerly triggers the TypeError upon inspection.
      final doc = OcrDocument.decode(malformedList);
      expect(() => doc.lines.first, throwsA(isA<TypeError>()));
    });
  });

  group('6. Disconnected Channel & Connection Error Paths', () {
    test('HostApi throws PlatformException(code: channel-error) when no host is registered', () async {
      // Unregister host API
      TestNativeCaptureHostApi.setUp(null);

      // Directly calling hostApi should now fail with connection error
      expect(
        () async => await hostApi.pickSingleImage(),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'channel-error')
            .having((e) => e.message, 'message', contains('Unable to establish connection'))),
      );

      // NativeBridgeService should wrap channel-error into NativeBridgeException
      expect(
        () async => await service.pickSingleImage(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'channel-error')
            .having((e) => e.message, 'message', contains('Unable to establish connection'))),
      );
    });
  });
}

class _AdversarialFlutterApiHandler implements NativeCaptureFlutterApi {
  final void Function(CaptureResult capture) onReceive;
  _AdversarialFlutterApiHandler({required this.onReceive});

  @override
  void onExternalCaptureReceived(CaptureResult capture) {
    onReceive(capture);
  }
}
