import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 오버레이 자식의 배치 방식.
enum EditorOverlayAnchor {
  /// 문자 범위의 세로 밴드를 폭 전체로 꽉 채운다 (인라인 테이블).
  band,

  /// 밴드 세로 중앙에 좌측 정렬, 높이는 [EditorOverlayItem.childHeight]
  /// (인라인 이미지). 중앙 정렬인 이유: 예약 글리프의 밴드 박스는 폰트
  /// 메트릭에 따라 라인 박스와 조금 어긋날 수 있지만(leading 분배), 잉크가
  /// 중앙 분배되므로 밴드 중앙은 항상 예약 줄의 중앙과 일치한다.
  imageBand,

  /// 밴드 왼쪽 끝에 세로 중앙 정렬 (details 접기 chevron).
  leadingChevron,

  /// 문자 범위 박스의 **왼쪽 끝**에 세로 중앙 정렬 (체크박스). 가운데
  /// 정렬하지 않는 이유: 박스가 예상보다 넓게 잡히는 경우(줄바꿈이 걸린
  /// 범위 등) 자식이 그 폭의 절반만큼 오른쪽으로 밀려 엉뚱한 자리에 그려진다.
  /// 왼쪽 정렬은 항상 그 글자가 시작하는 자리다.
  charBox,
}

/// 문자 범위에 고정되는 오버레이 항목 하나. [id]는 같은 레이어 안에서 유일해야
/// 하며 대응하는 [LayoutId]의 id와 일치해야 한다.
@immutable
class EditorOverlayItem {
  const EditorOverlayItem({
    required this.id,
    required this.start,
    required this.end,
    required this.anchor,
    this.childHeight = 0,
  });

  final Object id;

  /// 문자 범위 (컨트롤러 텍스트 오프셋).
  final int start;
  final int end;

  final EditorOverlayAnchor anchor;

  /// [EditorOverlayAnchor.imageBand] 전용: 자식 배치 높이(px).
  final double childHeight;

  @override
  bool operator ==(Object other) =>
      other is EditorOverlayItem &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.anchor == anchor &&
      other.childHeight == childHeight;

  @override
  int get hashCode => Object.hash(id, start, end, anchor, childHeight);
}

/// 에디터 필드의 [RenderEditable]을 레이아웃 시점에 직접 조회해 자식들을 문자
/// 범위 위치에 배치한다.
///
/// 이 레이어는 Stack에서 필드 뒤(자식 순서상 나중)에 오므로, performLayout이
/// 도는 시점에 필드는 이미 이번 프레임의 레이아웃을 마쳤다 — 미러 TextPainter
/// 재구성 없이 실제 배치와 정확히 일치한다. (미러 방식은 스트럿 floor를 없애면
/// RenderEditable과 ~2.3px 발산하는 것이 실측으로 확인되어 폐기했다.)
///
/// [RenderEditable.getBoxesForSelection]의 좌표는 스크롤이 반영된 viewport
/// 좌표다 (실측 확인). 따라서 스크롤 변경도 [relayout] 트리거에 포함해야 한다.
class EditorOverlayLayoutDelegate extends MultiChildLayoutDelegate {
  EditorOverlayLayoutDelegate({
    required this.editable,
    required this.items,
    required Listenable relayout,
    this.leftInset = 0,
  }) : super(relayout: relayout);

  /// 필드의 RenderEditable 조회. 아직 붙지 않았으면 null.
  final RenderEditable? Function() editable;

  final List<EditorOverlayItem> items;

  /// 텍스트 필드가 접기 거터만큼 오른쪽으로 밀려 있을 때의 x 오프셋.
  /// band/imageBand 자식은 이만큼 들여 배치한다 (chevron은 거터 안 = x 0).
  final double leftInset;

  /// 접힌(높이 ~0) 범위나 측정 불가 항목을 치워 두는 위치.
  static const Offset _offscreen = Offset(-1e5, -1e5);

  /// 이 높이 이하의 밴드는 접힌 것으로 보고 자식을 숨긴다.
  static const double _collapsedBandThreshold = 1.0;

  @override
  void performLayout(Size size) {
    final re = editable();
    for (final item in items) {
      Rect? band;
      if (re != null) {
        final boxes = re.getBoxesForSelection(
          TextSelection(baseOffset: item.start, extentOffset: item.end),
        );
        if (boxes.isNotEmpty) {
          var top = double.infinity;
          var bottom = double.negativeInfinity;
          var left = double.infinity;
          var right = double.negativeInfinity;
          for (final b in boxes) {
            top = math.min(top, b.top);
            bottom = math.max(bottom, b.bottom);
            left = math.min(left, b.left);
            right = math.max(right, b.right);
          }
          // 가로 범위는 charBox만 쓴다 (band/imageBand는 폭 전체를 채운다).
          band = Rect.fromLTRB(left, top, right, bottom);
        }
      }

      if (band == null || band.height <= _collapsedBandThreshold) {
        // 접힌 details 본문 안의 테이블/이미지 등: 화면 밖으로 치운다.
        layoutChild(item.id, BoxConstraints.loose(size));
        positionChild(item.id, _offscreen);
        continue;
      }

      final contentWidth = math.max(0.0, size.width - leftInset);
      switch (item.anchor) {
        case EditorOverlayAnchor.band:
          layoutChild(
              item.id, BoxConstraints.tight(Size(contentWidth, band.height)));
          positionChild(item.id, Offset(leftInset, band.top));
        case EditorOverlayAnchor.imageBand:
          final childHeight = math.max(0.0, item.childHeight);
          layoutChild(item.id,
              BoxConstraints.tight(Size(contentWidth, childHeight)));
          positionChild(
            item.id,
            Offset(leftInset, band.top + (band.height - childHeight) / 2),
          );
        case EditorOverlayAnchor.leadingChevron:
          final childSize = layoutChild(item.id, BoxConstraints.loose(size));
          positionChild(
            item.id,
            Offset(0, band.top + (band.height - childSize.height) / 2),
          );
        case EditorOverlayAnchor.charBox:
          final childSize = layoutChild(item.id, BoxConstraints.loose(size));
          positionChild(
            item.id,
            Offset(
              leftInset + band.left,
              band.top + (band.height - childSize.height) / 2,
            ),
          );
      }
    }
  }

  @override
  bool shouldRelayout(covariant EditorOverlayLayoutDelegate oldDelegate) {
    // 밴드 좌표의 원천이 위젯 밖(RenderEditable)에 있어서 items가 같아도
    // 배치가 달라질 수 있다 (예: 콘텐츠 줌으로 필드가 재배치된 직후의 리빌드).
    // 새 델리게이트가 만들어지면 항상 다시 배치한다 — getBoxesForSelection은
    // 이미 레이아웃된 문단 조회라 비용이 낮다.
    return true;
  }
}
