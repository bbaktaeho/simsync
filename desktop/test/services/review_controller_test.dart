import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_controller.dart';

void main() {
  final monday = DateTime(2026, 6, 1);

  test('untouched week is idle in both stages', () {
    final entry = ReviewController().weekly(monday);
    expect(entry.outline.phase, ReviewPhase.idle);
    expect(entry.review.phase, ReviewPhase.idle);
  });

  group('weekly outline (stage 1)', () {
    test('idle -> generating -> done, content set, persisted', () async {
      final controller = ReviewController();
      final persisted = <String>[];
      final gen = Completer<String>();
      final phases = <ReviewPhase>[];
      controller.addListener(
          () => phases.add(controller.weekly(monday).outline.phase));

      final future = controller.generateWeeklyOutline(
        monday,
        generate: () => gen.future,
        persist: (c) async => persisted.add(c),
      );

      expect(controller.weekly(monday).outline.phase, ReviewPhase.generating);

      gen.complete('- [ ] item');
      await future;

      expect(controller.weekly(monday).outline.phase, ReviewPhase.done);
      expect(controller.weekly(monday).outline.content, '- [ ] item');
      expect(persisted, ['- [ ] item']);
      expect(phases,
          containsAllInOrder([ReviewPhase.generating, ReviewPhase.done]));
    });

    test('a second generate while one is in flight is a no-op', () async {
      final controller = ReviewController();
      var calls = 0;
      final gen = Completer<String>();

      final first = controller.generateWeeklyOutline(
        monday,
        generate: () {
          calls++;
          return gen.future;
        },
        persist: (_) async {},
      );
      await controller.generateWeeklyOutline(
        monday,
        generate: () async {
          calls++;
          return 'other';
        },
        persist: (_) async {},
      );

      expect(calls, 1);
      gen.complete('- [ ] done');
      await first;
      expect(controller.weekly(monday).outline.content, '- [ ] done');
    });

    test('failure -> error phase with message', () async {
      final controller = ReviewController();
      await controller.generateWeeklyOutline(
        monday,
        generate: () async => throw Exception('boom'),
        persist: (_) async {},
      );
      expect(controller.weekly(monday).outline.phase, ReviewPhase.error);
      expect(controller.weekly(monday).outline.error, contains('boom'));
    });

    test('persist failure keeps the generated result (still done)', () async {
      final controller = ReviewController();
      await controller.generateWeeklyOutline(
        monday,
        generate: () async => '- [ ] r',
        persist: (_) async => throw Exception('save failed'),
      );
      expect(controller.weekly(monday).outline.phase, ReviewPhase.done);
      expect(controller.weekly(monday).outline.content, '- [ ] r');
    });

    test('setWeeklyOutlineContent replaces content in place (checkbox toggle)',
        () async {
      final controller = ReviewController();
      await controller.generateWeeklyOutline(
        monday,
        generate: () async => '- [ ] a\n- [ ] b',
        persist: (_) async {},
      );
      controller.setWeeklyOutlineContent(monday, '- [x] a\n- [ ] b');
      expect(controller.weekly(monday).outline.content, '- [x] a\n- [ ] b');
      expect(controller.weekly(monday).outline.phase, ReviewPhase.done);
    });
  });

  group('weekly review (stage 2)', () {
    test('generates independently of the outline stage', () async {
      final controller = ReviewController();
      // Seed an outline so the entry already has stage-1 content.
      controller.setLoadedWeeklyOutline(monday, '- [x] a');
      await controller.generateWeeklyReview(
        monday,
        generate: () async => '# Final',
        persist: (_) async {},
      );
      expect(controller.weekly(monday).review.phase, ReviewPhase.done);
      expect(controller.weekly(monday).review.content, '# Final');
      // The outline stage is untouched.
      expect(controller.weekly(monday).outline.content, '- [x] a');
    });

    test('failure -> error on the review stage only', () async {
      final controller = ReviewController();
      await controller.generateWeeklyReview(
        monday,
        generate: () async => throw Exception('boom'),
        persist: (_) async {},
      );
      expect(controller.weekly(monday).review.phase, ReviewPhase.error);
      expect(controller.weekly(monday).outline.phase, ReviewPhase.idle);
    });
  });

  group('seeding saved weekly results', () {
    test('setLoadedWeeklyOutline seeds done; null on an untouched week is idle',
        () {
      final controller = ReviewController();
      controller.setLoadedWeeklyOutline(monday, '- [ ] saved');
      expect(controller.weekly(monday).outline.phase, ReviewPhase.done);
      expect(controller.weekly(monday).outline.content, '- [ ] saved');

      final other = DateTime(2026, 7, 6);
      controller.setLoadedWeeklyOutline(other, null);
      expect(controller.weekly(other).outline.phase, ReviewPhase.idle);
    });

    test('setLoadedWeeklyReview(null) does not clobber an already-done review',
        () async {
      final controller = ReviewController();
      controller.setLoadedWeeklyOutline(monday, '- [x] a');
      await controller.generateWeeklyReview(
        monday,
        generate: () async => '# Generated',
        persist: (_) async {},
      );
      expect(controller.weekly(monday).review.phase, ReviewPhase.done);

      controller.setLoadedWeeklyReview(monday, null);
      expect(controller.weekly(monday).review.phase, ReviewPhase.done);
      expect(controller.weekly(monday).review.content, '# Generated');

      controller.setLoadedWeeklyReview(monday, '# Loaded');
      expect(controller.weekly(monday).review.content, '# Loaded');
    });

    test('setLoaded does not clobber an in-flight outline generation', () async {
      final controller = ReviewController();
      final gen = Completer<String>();
      final future = controller.generateWeeklyOutline(
        monday,
        generate: () => gen.future,
        persist: (_) async {},
      );
      expect(controller.weekly(monday).outline.phase, ReviewPhase.generating);

      controller.setLoadedWeeklyOutline(monday, '- [ ] stale');
      expect(controller.weekly(monday).outline.phase, ReviewPhase.generating);

      gen.complete('- [ ] fresh');
      await future;
      expect(controller.weekly(monday).outline.content, '- [ ] fresh');
    });
  });

  group('monthly (mirrors weekly, two independent stages)', () {
    final month = DateTime(2026, 6, 1);

    test('outline: generating -> done, content, persisted', () async {
      final controller = ReviewController();
      final persisted = <String>[];
      await controller.generateMonthlyOutline(
        month,
        generate: () async => '- [ ] m',
        persist: (c) async => persisted.add(c),
      );
      expect(controller.monthly(month).outline.phase, ReviewPhase.done);
      expect(controller.monthly(month).outline.content, '- [ ] m');
      expect(persisted, ['- [ ] m']);
    });

    test('review generates from the outline stage', () async {
      final controller = ReviewController();
      controller.setLoadedMonthlyOutline(month, '- [x] m');
      await controller.generateMonthlyReview(
        month,
        generate: () async => '# Monthly',
        persist: (_) async {},
      );
      expect(controller.monthly(month).review.content, '# Monthly');
    });

    test('setMonthlyOutlineContent toggles in place', () {
      final controller = ReviewController();
      controller.setLoadedMonthlyOutline(month, '- [ ] m');
      controller.setMonthlyOutlineContent(month, '- [x] m');
      expect(controller.monthly(month).outline.content, '- [x] m');
    });

    test('setLoadedMonthlyReview keeps done against a null load', () {
      final controller = ReviewController();
      controller.setLoadedMonthlyReview(month, '# Saved');
      expect(controller.monthly(month).review.content, '# Saved');
      controller.setLoadedMonthlyReview(month, null);
      expect(controller.monthly(month).review.content, '# Saved');
    });
  });
}
