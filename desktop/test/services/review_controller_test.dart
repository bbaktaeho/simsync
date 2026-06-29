import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_controller.dart';

void main() {
  final monday = DateTime(2026, 6, 1);

  test('untouched week is idle', () {
    expect(ReviewController().weekly(monday).phase, ReviewPhase.idle);
  });

  test('generateWeekly: idle -> generating -> done, content set, persisted',
      () async {
    final controller = ReviewController();
    final persisted = <String>[];
    final gen = Completer<String>();
    final phases = <ReviewPhase>[];
    controller.addListener(() => phases.add(controller.weekly(monday).phase));

    final future = controller.generateWeekly(
      monday,
      generate: () => gen.future,
      persist: (c) async => persisted.add(c),
    );

    // While the generator is pending the week is generating (and survives —
    // nothing here is tied to a widget lifecycle).
    expect(controller.weekly(monday).phase, ReviewPhase.generating);

    gen.complete('# Weekly Review');
    await future;

    expect(controller.weekly(monday).phase, ReviewPhase.done);
    expect(controller.weekly(monday).content, '# Weekly Review');
    expect(persisted, ['# Weekly Review']);
    expect(phases, containsAllInOrder([ReviewPhase.generating, ReviewPhase.done]));
  });

  test('a second generate while one is in flight is a no-op', () async {
    final controller = ReviewController();
    var generateCalls = 0;
    final gen = Completer<String>();

    final first = controller.generateWeekly(
      monday,
      generate: () {
        generateCalls++;
        return gen.future;
      },
      persist: (_) async {},
    );
    // Second call should not start another generation.
    await controller.generateWeekly(
      monday,
      generate: () async {
        generateCalls++;
        return 'other';
      },
      persist: (_) async {},
    );

    expect(generateCalls, 1);
    gen.complete('# Done');
    await first;
    expect(controller.weekly(monday).content, '# Done');
  });

  test('generate failure -> error phase with message', () async {
    final controller = ReviewController();
    await controller.generateWeekly(
      monday,
      generate: () async => throw Exception('boom'),
      persist: (_) async {},
    );
    expect(controller.weekly(monday).phase, ReviewPhase.error);
    expect(controller.weekly(monday).error, contains('boom'));
  });

  test('persist failure keeps the generated result (still done)', () async {
    final controller = ReviewController();
    await controller.generateWeekly(
      monday,
      generate: () async => '# R',
      persist: (_) async => throw Exception('save failed'),
    );
    expect(controller.weekly(monday).phase, ReviewPhase.done);
    expect(controller.weekly(monday).content, '# R');
  });

  test('setLoadedWeekly seeds done with content; null on an untouched week is idle',
      () {
    final controller = ReviewController();
    controller.setLoadedWeekly(monday, '# Saved');
    expect(controller.weekly(monday).phase, ReviewPhase.done);
    expect(controller.weekly(monday).content, '# Saved');

    // A null load for a different, untouched week resolves to idle.
    final other = DateTime(2026, 7, 6);
    controller.setLoadedWeekly(other, null);
    expect(controller.weekly(other).phase, ReviewPhase.idle);
  });

  test('setLoadedWeekly(null) does not clobber an already-done review',
      () async {
    final controller = ReviewController();
    await controller.generateWeekly(
      monday,
      generate: () async => '# Generated',
      persist: (_) async {},
    );
    expect(controller.weekly(monday).phase, ReviewPhase.done);

    // A later empty load (save not yet visible at the read source) must keep
    // the generated result rather than reset it to idle.
    controller.setLoadedWeekly(monday, null);
    expect(controller.weekly(monday).phase, ReviewPhase.done);
    expect(controller.weekly(monday).content, '# Generated');

    // A non-null load still updates the shown content.
    controller.setLoadedWeekly(monday, '# Loaded');
    expect(controller.weekly(monday).content, '# Loaded');
  });

  test('setLoadedWeekly does not clobber an in-flight generation', () async {
    final controller = ReviewController();
    final gen = Completer<String>();
    final future = controller.generateWeekly(
      monday,
      generate: () => gen.future,
      persist: (_) async {},
    );
    expect(controller.weekly(monday).phase, ReviewPhase.generating);

    // A late load result must not overwrite the running generation.
    controller.setLoadedWeekly(monday, '# Stale');
    expect(controller.weekly(monday).phase, ReviewPhase.generating);

    gen.complete('# Fresh');
    await future;
    expect(controller.weekly(monday).content, '# Fresh');
  });
}
