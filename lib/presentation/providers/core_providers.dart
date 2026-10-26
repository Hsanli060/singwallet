// lib/presentation/providers/core_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/native/native_bridge.g.dart';
import '../../core/native/native_bridge_service.dart';
import '../../data/database/app_database.dart';
import '../../data/database/transaction_manager.dart';
import '../../data/repositories/draft_repository.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/rule_repository.dart';
import '../../features/classification/rule_engine.dart';
import '../../features/deduplication/deduplication_engine.dart';
import '../../features/recognition/ocr_pipeline.dart';

/// Database provider. Overridden with real/in-memory SQLite Database in ProviderScope.
final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in ProviderScope');
});

/// TransactionManager provider for atomic draft commits and soft-deletes.
final transactionManagerProvider = Provider<TransactionManager>((ref) {
  return TransactionManager(AppDatabase.instance);
});

/// DeduplicationEngine provider.
final deduplicationEngineProvider = Provider<DeduplicationEngine>((ref) {
  final db = ref.watch(databaseProvider);
  return DeduplicationEngine(db);
});

/// Alias for deduplication engine provider.
final dedupEngineProvider = Provider<DeduplicationEngine>((ref) {
  return ref.watch(deduplicationEngineProvider);
});

/// ClassificationRuleEngine provider.
final classificationRuleEngineProvider = Provider<ClassificationRuleEngine>((ref) {
  final db = ref.watch(databaseProvider);
  return ClassificationRuleEngine(db);
});

/// OcrParsingPipeline provider combining deduplication and classification engines.
final ocrPipelineProvider = Provider<OcrParsingPipeline>((ref) {
  final dedup = ref.watch(deduplicationEngineProvider);
  final ruleEngine = ref.watch(classificationRuleEngineProvider);
  return OcrParsingPipeline(
    dedupEngine: dedup,
    classificationEngine: ruleEngine,
  );
});

/// Ledger repository provider.
final ledgerRepositoryProvider = Provider<ILedgerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final txManager = ref.watch(transactionManagerProvider);
  return LedgerRepository(db, txManager: txManager);
});

/// Draft repository provider.
final draftRepositoryProvider = Provider<IDraftRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final txManager = ref.watch(transactionManagerProvider);
  return DraftRepository(db, txManager: txManager);
});

/// Classification rule repository provider.
final ruleRepositoryProvider = Provider<IRuleRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return RuleRepository(db);
});

/// Native bridge service provider for hardware keys and OCR capture.
final nativeBridgeServiceProvider = Provider<NativeBridgeService>((ref) {
  final service = NativeBridgeService();
  service.initializeFlutterBridge();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream of incoming captures from external shares or shortcuts.
final externalCapturesStreamProvider = StreamProvider<CaptureResult>((ref) {
  final bridge = ref.watch(nativeBridgeServiceProvider);
  return bridge.externalCaptures;
});
