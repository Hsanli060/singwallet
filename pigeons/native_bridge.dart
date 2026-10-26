// pigeons/native_bridge.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/native/native_bridge.g.dart',
  dartTestOut: 'test/core/native/native_bridge_test.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/singwallet/app/bridge/NativeBridge.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.singwallet.app.bridge'),
  swiftOut: 'ios/Runner/Plugins/NativeBridge.g.swift',
  swiftOptions: SwiftOptions(),
))

/// 截图来源类型枚举
enum ImageSourceKind {
  systemShare,       // 系统分享 (Android Send Intent / iOS Share Extension)
  photoPicker,       // 应用内相册选择 (Photo Picker)
  shortcutsAction,   // 快捷指令 / 桌面快捷方式 / 动作按钮
  clipboard,         // 剪贴板提取
  quickSettingsTile, // 快捷设置磁贴采集 (Android P1)
}

/// 截图或图片导入结果
class CaptureResult {
  final String captureId;
  final String localFilePath;
  final int imageWidth;
  final int imageHeight;
  final String contentHash; // 图片 SHA-256 哈希值
  final ImageSourceKind sourceKind;

  CaptureResult({
    required this.captureId,
    required this.localFilePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.contentHash,
    required this.sourceKind,
  });
}

/// OCR 文本包围盒归一化坐标 [0.0, 1.0]，原点位于图片【左上角】
class OcrBoundingBox {
  final double left;
  final double top;
  final double width;
  final double height;

  OcrBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// OCR 识别单行文本
class OcrTextLine {
  final String text;
  final OcrBoundingBox boundingBox;
  final double? confidence; // 0.0 - 1.0，引擎未提供时为空

  OcrTextLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });
}

/// OCR 完整文档识别结果
class OcrDocument {
  final String captureId;
  final List<OcrTextLine> lines;
  final String engineIdentifier; // 如 "MLKit_Android_v2" 或 "AppleVision_iOS_17"
  final int processTimeMs;

  OcrDocument({
    required this.captureId,
    required this.lines,
    required this.engineIdentifier,
    required this.processTimeMs,
  });
}

/// 原生能力主机接口（Flutter -> 原生宿主）
@HostApi(dartHostTestHandler: 'TestNativeCaptureHostApi')
abstract class NativeCaptureHostApi {
  /// 打开系统原生图片选择器，选取单张图片
  @async
  CaptureResult? pickSingleImage();

  /// 扫描系统扩展存入的待处理导入任务 (针对 iOS App Group 或 Android 离线清单)
  List<CaptureResult> fetchPendingExternalCaptures();

  /// 调用原生平台最高效的离线 OCR 引擎进行识别
  @async
  OcrDocument recognizeCapture(String captureId);

  /// 清除 App 私有暂存目录下的图片原件
  bool deleteCaptureImage(String captureId);

  /// 从剪贴板读取单张图片（由用户显式触发）
  CaptureResult? readImageFromClipboard();

  /// Android P1: 触发单次屏幕采集并截取一帧；在 iOS 端调用返回 null 或抛出 UNSUPPORTED
  @async
  CaptureResult? startOneShotScreenCapture();

  /// 从安全硬件 (Keystore / Keychain) 异步获取或初始化 256 位数据库加密主密钥
  @async
  Uint8List getOrCreateDatabaseKey();
}

/// 原生向 Flutter 通信接口（原生宿主 -> Flutter 业务层）
@FlutterApi()
abstract class NativeCaptureFlutterApi {
  /// 当应用在前台或后台激活时，原生宿主接收到外部新分享或快捷指令导入时的实时回调通知
  void onExternalCaptureReceived(CaptureResult capture);
}
