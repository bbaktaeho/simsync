import 'package:flutter/widgets.dart';

/// 호버 여부만 상태로 가지는 위젯을 위한 최소 래퍼.
///
/// 이것 하나 때문에 StatefulWidget + State + createState 세 벌을 매번 다시 쓰던
/// 자리를 대신한다. [cursor] 기본값은 [MouseCursor.defer]로, 감싸도 커서 모양은
/// 바뀌지 않는다 — 클릭 커서가 필요한 곳만 명시한다.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}
