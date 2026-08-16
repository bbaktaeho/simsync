import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// 에디터의 숨겨진 `<img>` 마크다운 줄 위에 겹쳐 그려지는 인라인 이미지.
/// InlineTableView와 같은 오버레이 패턴. 활성(클릭/캐럿) 상태에서 우상단
/// 삭제 버튼과 우하단 리사이즈 핸들을 보여준다. 리사이즈는 비율 고정이며
/// 드롭 시 [onResized]로 width/height를 마크다운에 재기록한다.
///
/// 표시 크기는 태그의 width/height 속성 그대로를 따른다 — 컨트롤러의 줄 높이
/// 예약과 오버레이 밴드가 같은 원본 속성을 쓰므로 여기서 클램프하면 어긋난다.
/// [minWidth]..[maxWidth] 클램프는 리사이즈 결과(드래그 미리보기와 드롭 시
/// 재기록 값)에만 적용된다.
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

  /// 리사이즈 높이 한계. 줄 높이 예약은 이 높이를 그대로 글리프 fontSize로
  /// 환산하므로(markdown_editing_controller._imageLineSpans), 세로로 긴 이미지를
  /// 폭 한계까지 늘리면 fontSize가 수천까지 치솟는다 — 실측으로 200x1000 이미지가
  /// 1200x6000(fontSize ~4600)까지 커지는 것을 확인했다. 표시상으로도 의미가 없어
  /// 여기서 잘라 그 영역을 아예 만들지 않는다.
  static const int maxHeight = 1200;

  @override
  State<InlineImageView> createState() => _InlineImageViewState();
}

class _InlineImageViewState extends State<InlineImageView> {
  late Future<Uint8List?> _bytesFuture;

  /// 드래그 중 폭 누적기 (소수점 유지). 매 프레임 정수로 반올림한 값만 들고
  /// 있으면 1px 미만의 delta가 계속 버려져 느린 드래그가 아예 먹지 않는다.
  /// null이면 드래그 중이 아니다.
  double? _dragWidth;

  /// 드래그 시작 시점의 종횡비. 드래그 중에는 width/height가 매 프레임 정수로
  /// 재기록되므로, 그 값으로 비율을 다시 계산하면 반올림 오차가 누적돼 비율이
  /// 서서히 틀어진다.
  double? _dragAspect;

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

  /// 손상된 태그(width/height가 0 이하)는 비율 1로 다룬다. 0으로 나누면
  /// [_applyDrag]의 새 높이 계산이 Infinity가 되고 `round()`가 던진다.
  ///
  /// width가 0인 태그는 폭 0짜리 Stack이 되어 리사이즈 핸들이 hit test 영역
  /// 밖으로 나가므로 지금은 드래그 자체가 시작되지 않는다 — 그래서 이 가드에는
  /// 대응하는 테스트가 없다. 손으로 고친 마크다운이나 다른 클라이언트가 쓴
  /// 태그로 0이 들어올 수 있어 한 줄 방어만 남긴다.
  double get _aspect {
    if (widget.width <= 0 || widget.height <= 0) return 1;
    return widget.width / widget.height;
  }

  /// 드래그 델타를 마크다운 태그에 **즉시** 반영한다.
  ///
  /// 미리보기를 이 위젯 안에만 들고 있으면 줄 높이 예약(컨트롤러가 태그의
  /// width/height로 계산)이 그대로라, 늘릴 때 아래 본문이 밀리지 않다가 드롭
  /// 시점에야 한 번에 밀린다. 태그를 바로 갱신하면 예약과 표시가 항상 같은
  /// 값에서 나오므로 드래그 내내 어긋나지 않는다.
  void _applyDrag(double dx) {
    final aspect = _dragAspect ??= _aspect;
    final acc = (_dragWidth ?? widget.width.toDouble()) + dx / widget.scale;
    _dragWidth = acc;

    var w =
        acc.round().clamp(InlineImageView.minWidth, InlineImageView.maxWidth);
    var h = (w / aspect).round();
    if (h > InlineImageView.maxHeight) {
      h = InlineImageView.maxHeight;
      w = (h * aspect)
          .round()
          .clamp(InlineImageView.minWidth, InlineImageView.maxWidth);
    }
    if (h < 1) h = 1;
    if (w == widget.width && h == widget.height) return;
    widget.onResized(w, h);
  }

  void _resetDrag() {
    _dragWidth = null;
    _dragAspect = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 표시 크기는 항상 태그 속성 그대로 — 드래그 중에도 태그가 실시간으로
    // 갱신되므로, 컨트롤러의 줄 높이 예약과 같은 값에서 나온다.
    final displayW = widget.width * widget.scale;
    final displayH = widget.height * widget.scale;

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
                borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
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
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
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
                    onPanUpdate: (d) => _applyDrag(d.delta.dx),
                    onPanEnd: (_) => _resetDrag(),
                    onPanCancel: _resetDrag,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppDimensions.radiusMicro),
                          bottomRight: Radius.circular(AppDimensions.radiusMicro),
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
