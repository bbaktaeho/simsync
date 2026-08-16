import 'dart:convert';

import 'package:flutter/material.dart';

import '../settings/app_settings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';

/// Views and edits the portable settings as JSON. The same JSON is what syncs to
/// `settings/settings.json`. Applying it parses + validates the document and
/// writes each known field; secrets / device paths are never shown or synced.
class SettingsJsonDialog extends StatefulWidget {
  const SettingsJsonDialog({super.key, required this.controller});

  final AppSettingsController controller;

  static Future<void> show(
    BuildContext context,
    AppSettingsController controller,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsJsonDialog(controller: controller),
    );
  }

  @override
  State<SettingsJsonDialog> createState() => _SettingsJsonDialogState();
}

class _SettingsJsonDialogState extends State<SettingsJsonDialog> {
  late final TextEditingController _text;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.exportSyncJson());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _resetToCurrent() {
    setState(() {
      _text.text = widget.controller.exportSyncJson();
      _error = null;
    });
  }

  Future<void> _apply() async {
    Object? decoded;
    try {
      decoded = jsonDecode(_text.text);
    } on FormatException catch (e) {
      setState(() => _error = 'JSON 형식 오류: ${e.message}');
      return;
    }
    if (decoded is! Map) {
      setState(() => _error = 'JSON 객체(맵)여야 합니다.');
      return;
    }

    // Capture before the async gap so they survive popping this dialog.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _error = null;
      _applying = true;
    });
    final applied = await widget.controller.importSyncJson(
      Map<String, Object?>.from(decoded),
    );
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(applied.isEmpty
            ? '적용할 설정 항목이 없습니다.'
            : '설정 ${applied.length}개 항목을 적용했습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.data_object_rounded, size: 18, color: c.accent),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    '설정 JSON',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                '기기 공통 설정만 포함됩니다. API 키와 로컬 경로는 보안상 제외되며 동기화되지 않습니다. '
                '이 JSON은 settings/settings.json 로 동기화됩니다.',
                style: AppTextStyles.micro
                    .copyWith(color: c.textMuted, height: 1.5),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusStandard),
                    border: Border.all(
                        color: _error != null ? c.error : c.border),
                  ),
                  padding: const EdgeInsets.all(AppDimensions.spacingMd),
                  child: TextField(
                    controller: _text,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: AppTextStyles.codeMonoBlock(1.0)
                        .copyWith(color: c.textPrimary),
                    decoration: bareInputDecoration,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppDimensions.spacingSm),
                Text(_error!,
                    style: AppTextStyles.micro.copyWith(color: c.error)),
              ],
              const SizedBox(height: AppDimensions.spacingLg),
              Row(
                children: [
                  TextButton(
                    onPressed: _resetToCurrent,
                    style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                    child: const Text('현재값 불러오기'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  FilledButton(
                    onPressed: _applying ? null : _apply,
                    child: const Text('적용'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
