import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../services/review_paths.dart';
import '../services/review_service.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import '../widgets/markdown_preview.dart';

/// 데스크탑에서 만든 위클리·먼슬리 리뷰를 읽는 화면.
///
/// 모바일은 뷰어만이다 — 생성(AI 호출)은 데스크탑에만 있다. 리뷰는 동기화
/// 스토리지의 마크다운 파일이라(`notes/{YYYY-MM}/{N}주차/weekly-review.md`,
/// `notes/{YYYY-MM}/monthly-review.md`) 여기서는 읽어서 렌더만 한다.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.storage,
    this.localStorage,
    this.refreshSignal,
  });

  final NoteStorage storage;

  /// 로컬 미러. 동기화 스토리지 읽기가 실패하면 여기서 읽는다.
  final NoteStorage? localStorage;

  /// 원격 변경 신호. 바뀌면 현재 보고 있는 달을 다시 읽는다.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final ReviewService _service = ReviewService(
    storage: widget.storage,
    localStorage: widget.localStorage,
  );

  static final DateFormat _monthFmt = DateFormat('yyyy년 M월', 'ko');

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _monthly;
  final Map<DateTime, String> _weekly = {};

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final month = _month;

    final monthly = await _service.loadMonthly(month);
    final weekly = <DateTime, String>{};
    for (final weekStart in weekStartsForMonth(month.year, month.month)) {
      final content = await _service.loadWeekly(weekStart);
      if (content != null && content.trim().isNotEmpty) {
        weekly[weekStart] = content;
      }
    }

    // 읽는 동안 달을 바꿨으면 늦게 도착한 결과는 버린다.
    if (!mounted || month != _month) return;
    setState(() {
      _monthly = monthly;
      _weekly
        ..clear()
        ..addAll(weekly);
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '리뷰',
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: c.textPrimary,
              ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: c.textSecondary,
            onPressed: () => _shiftMonth(-1),
          ),
          Center(
            child: Text(
              _monthFmt.format(_month),
              style: AppTextStyles.captionSemibold.copyWith(
                color: c.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: c.textSecondary,
            onPressed: () => _shiftMonth(1),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(c),
      ),
    );
  }

  Widget _buildBody(AppColorsExtension c) {
    final hasMonthly = _monthly != null && _monthly!.trim().isNotEmpty;
    if (!hasMonthly && _weekly.isEmpty) {
      // 스크롤이 가능해야 당겨서 새로고침이 된다.
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Icon(Icons.auto_awesome_outlined, size: 40, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            '이 달의 리뷰가 없습니다',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            '리뷰는 데스크탑에서 만들고, 여기서는 읽기만 합니다',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ],
      );
    }

    final weeks = _weekly.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      children: [
        if (hasMonthly) ...[
          _ReviewCard(title: '먼슬리 리뷰', content: _monthly!),
          const SizedBox(height: AppDimensions.spacingLg),
        ],
        for (final week in weeks) ...[
          _ReviewCard(
            title: '${weekLabel(week)} (${DateFormat('M/d').format(week)}~)',
            content: _weekly[week]!,
          ),
          const SizedBox(height: AppDimensions.spacingLg),
        ],
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: buildMarkdownStyleSheet(context),
          ),
        ],
      ),
    );
  }
}
