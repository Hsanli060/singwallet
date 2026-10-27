// lib/presentation/screens/drafts/widgets/ocr_bounding_box_overlay.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/native/native_bridge.g.dart';

/// Normalized bounding box item for OCR visualization and interaction.
class OcrBoundingBoxItem {
  final String text;
  final OcrBoundingBox boundingBox;
  final double? confidence;
  final String? fieldKey;
  final Color? color;

  const OcrBoundingBoxItem({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.fieldKey,
    this.color,
  });

  factory OcrBoundingBoxItem.fromTextLine(
    OcrTextLine line, {
    String? fieldKey,
    Color? color,
  }) {
    return OcrBoundingBoxItem(
      text: line.text,
      boundingBox: line.boundingBox,
      confidence: line.confidence,
      fieldKey: fieldKey,
      color: color,
    );
  }
}

/// Utility for mapping normalized OCR coordinates [0.0, 1.0] to viewport coordinates.
///
/// Implements letterbox/pillarbox AspectRatio calculation to preserve geometry
/// without distortion or clipping.
class BoundingBoxMapper {
  BoundingBoxMapper._();

  static Rect mapNormalizedToViewport({
    required OcrBoundingBox box,
    required Size imageSize,
    required Size viewportSize,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return Rect.zero;
    }

    final double scale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    final double renderedWidth = imageSize.width * scale;
    final double renderedHeight = imageSize.height * scale;
    final double offsetX = (viewportSize.width - renderedWidth) / 2.0;
    final double offsetY = (viewportSize.height - renderedHeight) / 2.0;

    return Rect.fromLTWH(
      offsetX + (box.left * renderedWidth),
      offsetY + (box.top * renderedHeight),
      box.width * renderedWidth,
      box.height * renderedHeight,
    );
  }
}

/// Interactive OCR BoundingBox Overlay Widget.
///
/// Features:
/// 1. Accurate AspectRatio letterbox/pillarbox coordinate mapping.
/// 2. Renders semi-transparent highlight boxes with borders and text badges.
/// 3. Interactive touch-to-fill: Tapping bounding box invokes callbacks.
/// 4. Graceful fallback placeholder canvas when local screenshot file is absent.
class OcrBoundingBoxOverlay extends StatefulWidget {
  final String? imagePath;
  final Size originalImageSize;
  final List<OcrBoundingBoxItem> items;
  final ValueChanged<String>? onBoxTapped;
  final void Function(String text, String targetField)? onFillField;
  final double? height;

  const OcrBoundingBoxOverlay({
    super.key,
    this.imagePath,
    this.originalImageSize = const Size(1080, 1920),
    required this.items,
    this.onBoxTapped,
    this.onFillField,
    this.height = 280,
  });

  @override
  State<OcrBoundingBoxOverlay> createState() => _OcrBoundingBoxOverlayState();
}

class _OcrBoundingBoxOverlayState extends State<OcrBoundingBoxOverlay> {
  int? _selectedBoxIndex;

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    if (widget.items.isEmpty) return;

    int? tappedIndex;
    double smallestArea = double.infinity;

    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final rect = BoundingBoxMapper.mapNormalizedToViewport(
        box: item.boundingBox,
        imageSize: widget.originalImageSize,
        viewportSize: viewportSize,
      );

      // Expand tap target slightly for touch ergonomics
      final tapTarget = rect.inflate(4.0);
      if (tapTarget.contains(details.localPosition)) {
        final area = rect.width * rect.height;
        if (area < smallestArea) {
          smallestArea = area;
          tappedIndex = i;
        }
      }
    }

    if (tappedIndex != null) {
      final selectedItem = widget.items[tappedIndex];
      setState(() {
        _selectedBoxIndex = tappedIndex;
      });

      widget.onBoxTapped?.call(selectedItem.text);

      if (widget.onFillField != null) {
        _showFillFieldOptions(context, selectedItem.text);
      }
    } else {
      setState(() {
        _selectedBoxIndex = null;
      });
    }
  }

  void _showFillFieldOptions(BuildContext context, String text) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.touch_app, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '快速回填: "$text"',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('填入商户名称'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onFillField?.call(text, 'merchant');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_money_outlined),
                  title: const Text('填入交易金额'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onFillField?.call(text, 'amount');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = widget.height ?? 280.0;
        final viewportSize = Size(viewportWidth, viewportHeight);

        final bool hasValidLocalImage = widget.imagePath != null &&
            widget.imagePath!.isNotEmpty &&
            File(widget.imagePath!).existsSync();

        return Container(
          width: viewportWidth,
          height: viewportHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, viewportSize),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Layer 1: Background image or fallback evidence canvas
                if (hasValidLocalImage)
                  Image.file(
                    File(widget.imagePath!),
                    fit: BoxFit.contain,
                  )
                else
                  _buildEvidenceCanvas(theme, viewportSize),

                // Layer 2: Bounding box highlight rectangles
                CustomPaint(
                  size: viewportSize,
                  painter: _BoundingBoxPainter(
                    items: widget.items,
                    imageSize: widget.originalImageSize,
                    viewportSize: viewportSize,
                    selectedIndex: _selectedBoxIndex,
                    primaryColor: theme.colorScheme.primary,
                    secondaryColor: theme.colorScheme.tertiary,
                  ),
                ),

                // Layer 3: Interactive hint overlay badge
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withAlpha(200),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withAlpha(100),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '点击文本框快速回填',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEvidenceCanvas(ThemeData theme, Size viewportSize) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: theme.colorScheme.primary.withAlpha(160),
          ),
          const SizedBox(height: 8),
          Text(
            'OCR 证据快照预览',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.items.length} 个文本证据锚点就绪',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  final List<OcrBoundingBoxItem> items;
  final Size imageSize;
  final Size viewportSize;
  final int? selectedIndex;
  final Color primaryColor;
  final Color secondaryColor;

  _BoundingBoxPainter({
    required this.items,
    required this.imageSize,
    required this.viewportSize,
    required this.selectedIndex,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final rect = BoundingBoxMapper.mapNormalizedToViewport(
        box: item.boundingBox,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      final isSelected = selectedIndex == i;
      final baseColor = item.color ?? (isSelected ? secondaryColor : primaryColor);

      // Semi-transparent fill
      final fillPaint = Paint()
        ..color = baseColor.withAlpha(isSelected ? 90 : 45)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );

      // Border stroke
      final strokePaint = Paint()
        ..color = baseColor.withAlpha(isSelected ? 255 : 180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        strokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.items != items ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.viewportSize != viewportSize;
  }
}
