import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/widgets/hover_builder.dart';

void main() {
  testWidgets('마우스가 들어오고 나갈 때 hovered가 뒤집힌다', (tester) async {
    final states = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: HoverBuilder(
          builder: (context, hovered) {
            states.add(hovered);
            return const SizedBox(width: 100, height: 100);
          },
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(states.last, isTrue, reason: '호버 진입');

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(states.last, isFalse, reason: '호버 이탈');
  });
}
