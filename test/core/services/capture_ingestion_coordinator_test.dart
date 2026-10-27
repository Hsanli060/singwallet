import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/native/native_bridge_service.dart';
import 'package:singwallet/core/services/capture_ingestion_coordinator.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/repositories/draft_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeHostApi implements NativeCaptureHostApi {
  List<CaptureResult> pendingCaptures = [];
  OcrDocument? ocrResult;
  bool shouldFailOcr = false;
  final List<String> deletedCaptureIds = [];

  @override
  // ignore: non_constant_identifier_names
  final BinaryMessenger? pigeonVar_binaryMessenger = null;

  @override
  // ignore: non_constant_identifier_names
  final String pigeonVar_messageChannelSuffix = '';

  @override
  Future<CaptureResult?> pickSingleImage() async => null;

  @override
  Future<List<CaptureResult>> fetchPendingExternalCaptures() async => pendingCaptures;

  @override
  Future<OcrDocument> recognizeCapture(String captureId) async {
    if (shouldFailOcr) {
      throw PlatformException(code: 'OCR_ERROR', message: 'Simulated OCR failure');
    }
    return ocrResult ??
        OcrDocument(
          captureId: captureId,
          lines: [
            OcrTextLine(
              text: '微信支付',
              boundingBox: OcrBoundingBox(left: 0.35, top: 0.10, width: 0.30, height: 0.03),
              confidence: 0.99,
            ),
            OcrTextLine(
              text: '支付成功',
              boundingBox: OcrBoundingBox(left: 0.38, top: 0.14, width: 0.24, height: 0.03),
              confidence: 0.99,
            ),
            OcrTextLine(
              text: '¥36.80',
              boundingBox: OcrBoundingBox(left: 0.30, top: 0.18, width: 0.40, height: 0.05),
              confidence: 0.99,
            ),
            OcrTextLine(
              text: '收款商户',
              boundingBox: OcrBoundingBox(left: 0.08, top: 0.30, width: 0.16, height: 0.02),
              confidence: 0.98,
            ),
            OcrTextLine(
              text: '星巴克咖啡（深圳湾店）',
              boundingBox: OcrBoundingBox(left: 0.35, top: 0.30, width: 0.55, height: 0.02),
              confidence: 0.98,
            ),
            OcrTextLine(
              text: '支付时间',
              boundingBox: OcrBoundingBox(left: 0.08, top: 0.35, width: 0.16, height: 0.02),
              confidence: 0.98,
            ),
            OcrTextLine(
              text: '2026-10-27 12:15:30',
              boundingBox: OcrBoundingBox(left: 0.35, top: 0.35, width: 0.50, height: 0.02),
              confidence: 0.98,
            ),
          ],
          engineIdentifier: 'MLKit_Android_Chinese_v1',
          processTimeMs: 42,
        );
  }

  @override
  Future<bool> deleteCaptureImage(String captureId) async {
    deletedCaptureIds.add(captureId);
    return true;
  }

  @override
  Future<CaptureResult?> readImageFromClipboard() async => null;

  @override
  Future<CaptureResult?> startOneShotScreenCapture() async => null;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async => Uint8List(32);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late _FakeHostApi fakeHostApi;
  late NativeBridgeService bridgeService;
  late CaptureIngestionCoordinator coordinator;
  late DraftRepository draftRepo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await DatabaseSeeder.seedIfNeeded(db);
    fakeHostApi = _FakeHostApi();
    bridgeService = NativeBridgeService(hostApi: fakeHostApi);
    bridgeService.initializeFlutterBridge();
    final pipeline = OcrParsingPipeline(
      dedupEngine: DeduplicationEngine(db),
      classificationEngine: ClassificationRuleEngine(db),
    );
    coordinator = CaptureIngestionCoordinator(
      db: db,
      bridge: bridgeService,
      pipeline: pipeline,
    );
    draftRepo = DraftRepository(db);
  });

  tearDown(() async {
    bridgeService.dispose();
    await db.close();
  });

  test('ingests system Back-Tap screenshot into NEEDS_REVIEW draft', () async {
    final capture = CaptureResult(
      captureId: 'share_backtap_001',
      localFilePath: '/data/user/0/com.singwallet.app/files/pending_captures/share_backtap_001.jpg',
      imageWidth: 1200,
      imageHeight: 2670,
      contentHash: 'sha256_backtap_hash_001',
      sourceKind: ImageSourceKind.systemShare,
    );

    final draft = await coordinator.ingestCapture(capture);
    expect(draft, isNotNull);
    expect(draft!.captureId, equals('share_backtap_001'));

    final fields = jsonDecode(draft.candidateFields) as Map<String, dynamic>;
    expect(fields['amount_minor'], equals(3680));
    expect(fields['payment_channel'], equals('wechat'));
    expect(fields['merchant_raw'], contains('星巴克'));

    final pendingDrafts = await draftRepo.getPendingDrafts();
    expect(pendingDrafts.length, equals(1));
    expect(pendingDrafts.first.id, equals('draft_share_backtap_001'));
  });

  test('deduplicates identical screenshot contentHash and cleans up duplicate file', () async {
    final first = CaptureResult(
      captureId: 'share_backtap_101',
      localFilePath: '/tmp/share_backtap_101.jpg',
      imageWidth: 1200,
      imageHeight: 2670,
      contentHash: 'identical_sha256_hash',
      sourceKind: ImageSourceKind.systemShare,
    );
    final duplicate = CaptureResult(
      captureId: 'share_backtap_102',
      localFilePath: '/tmp/share_backtap_102.jpg',
      imageWidth: 1200,
      imageHeight: 2670,
      contentHash: 'identical_sha256_hash',
      sourceKind: ImageSourceKind.systemShare,
    );

    final d1 = await coordinator.ingestCapture(first);
    final d2 = await coordinator.ingestCapture(duplicate);

    expect(d1, isNotNull);
    expect(d2, isNull);
    expect(fakeHostApi.deletedCaptureIds, contains('share_backtap_102'));

    final pendingDrafts = await draftRepo.getPendingDrafts();
    expect(pendingDrafts.length, equals(1));
  });

  test('marks capture_job as FAILED cleanly when OCR throws exception', () async {
    fakeHostApi.shouldFailOcr = true;
    final capture = CaptureResult(
      captureId: 'share_fail_001',
      localFilePath: '/tmp/share_fail_001.jpg',
      imageWidth: 1080,
      imageHeight: 2400,
      contentHash: 'hash_fail_001',
      sourceKind: ImageSourceKind.systemShare,
    );

    final draft = await coordinator.ingestCapture(capture);
    expect(draft, isNull);

    final jobs = await db.query(
      'capture_jobs',
      where: 'id = ?',
      whereArgs: ['share_fail_001'],
    );
    expect(jobs.length, equals(1));
    expect(jobs.first['state'], equals(CaptureJobState.failed.value));
  });
}
