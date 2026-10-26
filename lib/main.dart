// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/database/app_database.dart';
import 'data/database/state_machine.dart';
import 'data/seeder/database_seeder.dart';
import 'presentation/navigation/app_scaffold.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize SQLite FFI on desktop platforms
  AppDatabase.initializeFfi();

  // 2. Open primary database connection
  final db = await AppDatabase.instance.database;

  // 3. Self-healing startup recovery for lingering ingestion jobs
  await CaptureJobStateMachine.recoverLingeringJobs(db);

  // 4. Seed default categories, accounts, and projects idempotently
  await DatabaseSeeder.seedIfNeeded(db);

  // 5. Launch application wrapped in ProviderScope with database override
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: const SingWalletApp(),
    ),
  );
}

/// Root Application Widget for SingWallet.
class SingWalletApp extends StatelessWidget {
  final List<Override> overrides;

  const SingWalletApp({
    super.key,
    this.overrides = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        title: 'SingWallet',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const AppScaffold(),
      ),
    );
  }
}
