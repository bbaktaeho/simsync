---
title: Typography & Font
description: Inter 적용, TextTheme + AppTextStyles 정의, 화면 적용 전략
type: plan
created: 2026-05-01
status: draft
related:
  - DESIGN.md
  - .agent/plan/001-2026-05-01-design-system-refresh/02-token-mapping.md
---

# Typography & Font

## Font: Inter (via google_fonts)

`google_fonts: ^8.0.2` 가 이미 desktop/mobile pubspec 양쪽에 있음. **새 의존성 불필요**, 폰트 파일 번들 불필요.

```dart
// app_theme.dart
import 'package:google_fonts/google_fonts.dart';

final baseTextTheme = GoogleFonts.interTextTheme(base.textTheme);
```

기존: `GoogleFonts.manropeTextTheme` → 변경: `GoogleFonts.interTextTheme`.

### Fallback 정책

`google_fonts`는 런타임에 Google Fonts CDN에서 받아오며 캐싱한다. 오프라인/CDN 차단 환경에서 fallback이 필요. PR1에서:

```dart
// pubspec.yaml 에 Inter 정적 자산 번들도 함께 추가 (옵션)
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

> Inter는 OFL-1.1 라이선스로 자유 번들 가능. PR1 단계에서 번들 결정 여부 확정.
> CDN-only 의존을 받아들이면 위 단계 생략 가능. **추천: 번들** (오프라인 안정성).

### NotionInter vs Inter 차이

DESIGN.md는 NotionInter (Inter modified)를 명시하지만 라이선스 미확보. Inter로 대체 시 차이:
- glyph metric 미세 차이 (대부분 사용자가 인지 어려움)
- letter-spacing 값은 동일 적용 가능
- OpenType `lnum`/`locl` feature는 Inter도 지원 → `TextStyle.fontFeatures` 사용 시 적용 가능

→ **시각 차이 무시 가능**. DESIGN.md letter-spacing/weight 수치는 그대로 적용.

## Hierarchy → Flutter TextTheme + AppTextStyles

DESIGN.md hierarchy(16개)를 Flutter `TextTheme` 13개 슬롯에 매핑하면 일부 누락. 따라서 **`TextTheme`은 일반 매핑 + `AppTextStyles` 클래스로 누락분 보완**.

### TextTheme 매핑

| Flutter slot | DESIGN.md role | size | weight | letter-spacing | line-height |
|--------------|---------------|------|--------|---------------|-------------|
| displayLarge | Display Hero | 64 | 700 | -2.125 | 1.00 |
| displayMedium | Display Secondary | 54 | 700 | -1.875 | 1.04 |
| displaySmall | Section Heading | 48 | 700 | -1.5 | 1.00 |
| headlineLarge | Sub-heading Large | 40 | 700 | normal | 1.50 |
| headlineMedium | Sub-heading | 26 | 700 | -0.625 | 1.23 |
| headlineSmall | Card Title | 22 | 700 | -0.25 | 1.27 |
| titleLarge | Body Large | 20 | 600 | -0.125 | 1.40 |
| titleMedium | Nav / Button | 15 | 600 | normal | 1.33 |
| titleSmall | Caption (emphasis) | 14 | 500 | normal | 1.43 |
| bodyLarge | Body Medium | 16 | 500 | normal | 1.50 |
| bodyMedium | Body | 16 | 400 | normal | 1.50 |
| bodySmall | Caption Light | 14 | 400 | normal | 1.43 |
| labelLarge | Body Semibold | 16 | 600 | normal | 1.50 |
| labelMedium | Badge | 12 | 600 | 0.125 | 1.33 |
| labelSmall | Micro Label | 12 | 400 | 0.125 | 1.33 |

### `AppTextStyles` 신설 (TextTheme 부족분)

```dart
// theme/app_text_styles.dart
abstract final class AppTextStyles {
  static const _family = 'Inter';

  static const bodyBold = TextStyle(
    fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w700,
    height: 1.50,
  );
  // 기타 누락 role...
}
```

> 우선 `TextTheme`만 정의하고, PR2 진행 중 부족 발견 시 `AppTextStyles`로 추가하는 방식 추천.

## 적용 패턴 (PR2 마이그레이션 가이드)

### Before
```dart
Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))
```

### After (선호)
```dart
Text('Settings', style: Theme.of(context).textTheme.headlineSmall)
```

### After (대안 — Theme 미적용 위젯)
```dart
Text('Settings', style: AppTextStyles.cardTitle)
```

PR2에서는 화면별로 인라인 `TextStyle(fontSize:..., fontWeight:...)`를 위 두 패턴 중 하나로 일괄 교체.

## Risk

- `google_fonts` 런타임 다운로드 실패 → 시스템 fallback (SF Pro/Roboto)으로 표시. DESIGN.md letter-spacing은 적용되지만 폰트 모양은 다름.
- → 정적 번들 권장 (위 fallback 정책 참고).
