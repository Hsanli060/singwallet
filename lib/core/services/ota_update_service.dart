// lib/core/services/ota_update_service.dart

/// Release and update information model for OTA checking.
class OtaReleaseInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String changelog;
  final String downloadUrl;
  final int apkSize;
  final bool preserveDataGuaranteed;

  const OtaReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.changelog,
    required this.downloadUrl,
    required this.apkSize,
    this.preserveDataGuaranteed = true,
  });

  factory OtaReleaseInfo.fromJson(Map<String, dynamic> json) {
    return OtaReleaseInfo(
      currentVersion: json['currentVersion'] as String? ?? '1.0.0',
      latestVersion: json['latestVersion'] as String? ?? '1.0.0',
      hasUpdate: json['hasUpdate'] as bool? ?? false,
      changelog: json['changelog'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      apkSize: (json['apkSize'] as num?)?.toInt() ?? 0,
      preserveDataGuaranteed: json['preserveDataGuaranteed'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentVersion': currentVersion,
      'latestVersion': latestVersion,
      'hasUpdate': hasUpdate,
      'changelog': changelog,
      'downloadUrl': downloadUrl,
      'apkSize': apkSize,
      'preserveDataGuaranteed': preserveDataGuaranteed,
    };
  }

  @override
  String toString() =>
      'OtaReleaseInfo(current: $currentVersion, latest: $latestVersion, hasUpdate: $hasUpdate, size: $apkSize, preserveData: $preserveDataGuaranteed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OtaReleaseInfo &&
          runtimeType == other.runtimeType &&
          currentVersion == other.currentVersion &&
          latestVersion == other.latestVersion &&
          hasUpdate == other.hasUpdate &&
          changelog == other.changelog &&
          downloadUrl == other.downloadUrl &&
          apkSize == other.apkSize &&
          preserveDataGuaranteed == other.preserveDataGuaranteed;

  @override
  int get hashCode => Object.hash(
        currentVersion,
        latestVersion,
        hasUpdate,
        changelog,
        downloadUrl,
        apkSize,
        preserveDataGuaranteed,
      );
}

/// Service handling App-internal Over-The-Air (OTA) update checking and manifest parsing.
///
/// Implements standard semantic version comparison and supports both GitHub Releases
/// API responses and custom static `version.json` endpoints.
class OtaUpdateService {
  OtaUpdateService._();

  /// Semantic version comparison pure function.
  ///
  /// Normalizes versions (stripping leading 'v'/'V', whitespace, and splitting build/prerelease).
  ///
  /// Returns:
  /// - Negative integer (`< 0`) if [v1] is older than [v2] (update available)
  /// - `0` if [v1] equals [v2]
  /// - Positive integer (`> 0`) if [v1] is newer than [v2]
  static int compareVersions(String v1, String v2) {
    final norm1 = _normalizeVersionString(v1);
    final norm2 = _normalizeVersionString(v2);

    final parts1 = norm1.coreNumbers;
    final parts2 = norm2.coreNumbers;

    final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) {
        return p1.compareTo(p2);
      }
    }

    // If core versions match, check prerelease tags
    // e.g., 1.0.0-beta < 1.0.0
    if (norm1.prerelease != null && norm2.prerelease == null) {
      return -1; // prerelease is older than release
    }
    if (norm1.prerelease == null && norm2.prerelease != null) {
      return 1;
    }
    if (norm1.prerelease != null && norm2.prerelease != null) {
      final preComp = norm1.prerelease!.compareTo(norm2.prerelease!);
      if (preComp != 0) return preComp;
    }

    // Check build number e.g., +1 vs +2
    final b1 = norm1.buildNumber ?? 0;
    final b2 = norm2.buildNumber ?? 0;
    return b1.compareTo(b2);
  }

  /// Parses an OTA manifest Map, seamlessly supporting:
  /// 1) GitHub Releases API JSON (`tag_name`, `assets`, `body`)
  /// 2) Custom static `version.json` (`version`, `downloadUrl`, `changelog`)
  ///
  /// Computes `hasUpdate` by comparing [currentVersion] against the manifest's target version.
  static OtaReleaseInfo parseReleaseManifest(
    Map<String, dynamic> json, {
    required String currentVersion,
  }) {
    String latestVersion = '1.0.0';
    String changelog = '';
    String downloadUrl = '';
    int apkSize = 0;
    bool preserveDataGuaranteed = true;

    // Detection Strategy 1: GitHub Releases API JSON
    if (json.containsKey('tag_name') || json.containsKey('assets')) {
      final rawTag = (json['tag_name'] as String?) ?? (json['name'] as String?) ?? '1.0.0';
      latestVersion = _stripVPrefix(rawTag);
      changelog = (json['body'] as String?) ?? '';

      final assets = json['assets'];
      if (assets is List) {
        // Look for .apk asset
        Map<String, dynamic>? apkAsset;
        for (final item in assets) {
          if (item is Map<String, dynamic>) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            if (name.endsWith('.apk')) {
              apkAsset = item;
              break;
            }
          }
        }

        // Fallback to first asset if no explicit .apk extension found
        apkAsset ??= assets.isNotEmpty && assets.first is Map<String, dynamic>
            ? assets.first as Map<String, dynamic>
            : null;

        if (apkAsset != null) {
          downloadUrl = (apkAsset['browser_download_url'] as String?) ?? '';
          apkSize = (apkAsset['size'] as num?)?.toInt() ?? 0;
        }
      }

      if (json.containsKey('preserveDataGuaranteed')) {
        preserveDataGuaranteed = json['preserveDataGuaranteed'] as bool? ?? true;
      }
    }
    // Detection Strategy 2: Custom version.json
    else {
      final rawVer = (json['version'] as String?) ??
          (json['latestVersion'] as String?) ??
          (json['tagName'] as String?) ??
          '1.0.0';
      latestVersion = _stripVPrefix(rawVer);
      changelog = (json['changelog'] as String?) ?? (json['description'] as String?) ?? '';
      downloadUrl = (json['downloadUrl'] as String?) ?? (json['url'] as String?) ?? '';
      apkSize = (json['apkSize'] as num?)?.toInt() ?? (json['size'] as num?)?.toInt() ?? 0;
      preserveDataGuaranteed = json['preserveDataGuaranteed'] as bool? ?? true;
    }

    final hasUpdate = compareVersions(currentVersion, latestVersion) < 0;

    return OtaReleaseInfo(
      currentVersion: _stripVPrefix(currentVersion),
      latestVersion: latestVersion,
      hasUpdate: hasUpdate,
      changelog: changelog,
      downloadUrl: downloadUrl,
      apkSize: apkSize,
      preserveDataGuaranteed: preserveDataGuaranteed,
    );
  }

  /// Strips leading 'v' or 'V' and trims whitespace
  static String _stripVPrefix(String version) {
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    return v;
  }

  /// Internal helper to normalize and parse version strings into components
  static _ParsedVersion _normalizeVersionString(String input) {
    var raw = _stripVPrefix(input);

    int? buildNumber;
    // Check for build metadata like +1 or +42
    if (raw.contains('+')) {
      final plusIndex = raw.indexOf('+');
      final buildStr = raw.substring(plusIndex + 1);
      buildNumber = int.tryParse(buildStr);
      raw = raw.substring(0, plusIndex);
    }

    String? prerelease;
    // Check for prerelease tags like -beta or -rc.1
    if (raw.contains('-')) {
      final dashIndex = raw.indexOf('-');
      prerelease = raw.substring(dashIndex + 1);
      raw = raw.substring(0, dashIndex);
    }

    final segments = raw.split('.');
    final numbers = <int>[];
    for (final seg in segments) {
      final cleaned = seg.replaceAll(RegExp(r'[^0-9]'), '');
      numbers.add(int.tryParse(cleaned) ?? 0);
    }

    while (numbers.length < 3) {
      numbers.add(0);
    }

    return _ParsedVersion(
      coreNumbers: numbers,
      prerelease: prerelease,
      buildNumber: buildNumber,
    );
  }

  /// Helper to format raw byte count into human-readable MB string
  static String formatApkSize(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _ParsedVersion {
  final List<int> coreNumbers;
  final String? prerelease;
  final int? buildNumber;

  const _ParsedVersion({
    required this.coreNumbers,
    this.prerelease,
    this.buildNumber,
  });
}
