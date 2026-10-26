/// Global system constants and thresholds for SingWallet
class AppConstants {
  AppConstants._();

  static const String appName = 'SingWallet';
  static const String databaseName = 'singwallet.db';
  static const int databaseVersion = 1;

  // OCR Normalization limits & cutoffs
  static const double statusBarMaxTop = 0.075; // Status bar area cutoff
  static const double homeIndicatorMinTop = 0.95; // Home bar area cutoff

  // Deduplication time window
  static const Duration fuzzyDedupWindow = Duration(hours: 24);

  // Supported image extensions
  static const List<String> supportedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
}
