import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 에디터의 숨겨진 `<img>` 마크다운 줄 위에 겹쳐 그려지는 인라인 이미지.
/// InlineTableView와 같은 오버레이 패턴. 활성(클릭/캐럿) 상태에서 우상단
/// 삭제 버튼과 우하단 리사이즈 핸들을 보여준다. 리사이즈는 비율 고정이며
/// 드롭 시 [onResized]로 width/height를 마크다운에 재기록한다.
class InlineImageView extends StatefulWidget {
  const InlineImageView({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    required this.scale,
    required this.active,
    required this.readOnly,
    required this.loadImage,
    required this.onActivate,
    required this.onResized,
    required this.onRemove,
  });

  final String src;

  /// 마크다운 속성 기준 크기 (px). 표시 크기 = width * scale.
  final int width;
  final int height;

  /// 에디터 콘텐츠 줌 배율.
  final double scale;

  final bool active;
  final bool readOnly;
  final Future<Uint8List?> Function(String src) loadImage;
  final VoidCallback onActivate;
  final void Function(int width, int height) onResized;
  final VoidCallback onRemove;

  /// 리사이즈 폭 한계 (마크다운 속성 기준 px).
  static const int minWidth = 48;
  static const int maxWidth = 1200;

  @override
  State<InlineImageView> createState() => _InlineImageViewState();
}

class _InlineImageViewState extends State<InlineImageView> {
  late Future<Uint8List?> _bytesFuture;

  /// 드래그 중 미리보기 폭 (마크다운 속성 기준 px). null이면 드래그 중 아님.
  double? _dragWidth;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.loadImage(widget.src);
  }

  @override
  void didUpdateWidget(InlineImageView old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _bytesFuture = widget.loadImage(widget.src);
    }
  }

  double get _aspect =>
      widget.height <= 0 ? 1 : widget.width / widget.height;

  void _endDrag() {
    final w = _dragWidth;
    if (w == null) return;
    setState(() => _dragWidth = null);
    final newW =
        w.round().clamp(InlineImageView.minWidth, InlineImageView.maxWidth);
    widget.onResized(newW, (newW / _aspect).round());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final attrW = (_dragWidth ?? widget.width.toDouble()).clamp(
        InlineImageView.minWidth.toDouble(),
        InlineImageView.maxWidth.toDouble());
    final displayW = attrW * widget.scale;
    final displayH = attrW / _aspect * widget.scale;

    return Align(
      alignment: Alignment.topLeft,
      child: GestureDetector(
        onTap: widget.onActivate,
        child: Stack(
          children: [
            Container(
              width: displayW,
              height: displayH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.active ? c.accent : c.border,
                  width: widget.active ? 1.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Uint8List?>(
                future: _bytesFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.accent),
                      ),
                    );
                  }
                  final bytes = snap.data;
                  if (bytes == null) {
                    return Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 20, color: c.textMuted),
                    );
                  }
                  return Image.memory(bytes,
                      fit: BoxFit.fill, gaplessPlayback: true);
                },
              ),
            ),
            if (widget.active && !widget.readOnly) ...[
              Positioned(
                top: 4,
                right: 4,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child:
                          Icon(Icons.close_rounded, size: 14, color: c.textSecondary),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(() {
                      _dragWidth = (_dragWidth ?? widget.width.toDouble()) +
                          d.delta.dx / widget.scale;
                    }),
                    onPanEnd: (_) => _endDrag(),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomRight: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
