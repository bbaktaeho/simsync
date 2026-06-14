import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTextStyles {
  static const _family = 'Inter';

  // 24px — page/screen title (login, settings section heading)
  static const pageTitle = TextStyle(
    fontFamily: _family, fontSize: 24, fontWeight: FontWeight.w700, height: 1.25,
  );

  // 18px — subsection heading
  static const sectionHeading = TextStyle(
    fontFamily: _family, fontSize: 18, fontWeight: FontWeight.w700, height: 1.33,
  );
  static const sectionHeadingSemibold = TextStyle(
    fontFamily: _family, fontSize: 18, fontWeight: FontWeight.w600, height: 1.33,
  );

  // 17px — note list item title
  static const noteTitle = TextStyle(
    fontFamily: _family, fontSize: 17, fontWeight: FontWeight.w600, height: 1.35,
  );

  // 13px — caption scale (between bodySmall 14 and labelSmall 12)
  static const caption = TextStyle(
    fontFamily: _family, fontSize: 13, fontWeight: FontWeight.w400, height: 1.38,
  );
  static const captionMedium = TextStyle(
    fontFamily: _family, fontSize: 13, fontWeight: FontWeight.w500, height: 1.38,
  );
  static const captionSemibold = TextStyle(
    fontFamily: _family, fontSize: 13, fontWeight: FontWeight.w600, height: 1.38,
  );
  static const captionBold = TextStyle(
    fontFamily: _family, fontSize: 13, fontWeight: FontWeight.w700, height: 1.38,
  );

  // 12.5px — hairline caption (document status bar)
  static const captionThin = TextStyle(
    fontFamily: _family, fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.40,
  );

  // 11px — micro label scale
  static const micro = TextStyle(
    fontFamily: _family, fontSize: 11, fontWeight: FontWeight.w400, height: 1.36,
  );
  static const microMedium = TextStyle(
    fontFamily: _family, fontSize: 11, fontWeight: FontWeight.w500, height: 1.36,
  );
  static const microSemibold = TextStyle(
    fontFamily: _family, fontSize: 11, fontWeight: FontWeight.w600, height: 1.36,
  );
  static const microBold = TextStyle(
    fontFamily: _family, fontSize: 11, fontWeight: FontWeight.w700, height: 1.36,
  );

  // 10px — nano label (note counts, calendar dots)
  static const nano = TextStyle(
    fontFamily: _family, fontSize: 10, fontWeight: FontWeight.w400, height: 1.40,
  );
  static const nanoMedium = TextStyle(
    fontFamily: _family, fontSize: 10, fontWeight: FontWeight.w500, height: 1.40,
  );
  static const nanoSemibold = TextStyle(
    fontFamily: _family, fontSize: 10, fontWeight: FontWeight.w600, height: 1.40,
  );

  // 9px — atto label (calendar overflow indicators)
  static const atto = TextStyle(
    fontFamily: _family, fontSize: 9, fontWeight: FontWeight.w400, height: 1.44,
  );
  static const attoBold = TextStyle(
    fontFamily: _family, fontSize: 9, fontWeight: FontWeight.w700, height: 1.44,
  );

  // Scale-aware styles for zoom preview widgets
  static TextStyle scaledHeadline(double scale) => TextStyle(
    fontFamily: _family, fontSize: 22 * scale, fontWeight: FontWeight.w700,
    height: 1.27, letterSpacing: -0.25,
  );
  static TextStyle scaledCaption(double scale) => TextStyle(
    fontFamily: _family, fontSize: 13 * scale, fontWeight: FontWeight.w400,
    height: 1.6,
  );
  static TextStyle scaledH1(double scale) => TextStyle(
    fontFamily: _family, fontSize: 24 * scale, fontWeight: FontWeight.w700,
    height: 1.25,
  );

  // Markdown preview scaled styles (h1..h6, body, table, code)
  static TextStyle mdH1(double scale) => TextStyle(
    fontFamily: _family, fontSize: 26 * scale, fontWeight: FontWeight.w700,
    height: 1.4,
  );
  static TextStyle mdH2(double scale) => TextStyle(
    fontFamily: _family, fontSize: 21 * scale, fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle mdH3(double scale) => TextStyle(
    fontFamily: _family, fontSize: 17 * scale, fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle mdH4(double scale) => TextStyle(
    fontFamily: _family, fontSize: 15 * scale, fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle mdH5(double scale) => TextStyle(
    fontFamily: _family, fontSize: 14 * scale, fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle mdH6(double scale) => TextStyle(
    fontFamily: _family, fontSize: 13 * scale, fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle mdBody(double scale) => TextStyle(
    fontFamily: _family, fontSize: 14 * scale, fontWeight: FontWeight.w400,
    height: 1.7,
  );
  static TextStyle mdTableHead(double scale) => TextStyle(
    fontFamily: _family, fontSize: 13 * scale, fontWeight: FontWeight.w600,
  );
  static TextStyle mdTableBody(double scale) => TextStyle(
    fontFamily: _family, fontSize: 13 * scale, fontWeight: FontWeight.w400,
  );

  // Code-mono (JetBrains Mono) — parameterized for ad-hoc sizes/weights.
  // Use this anywhere a monospace style is needed; centralizes font registration.
  static TextStyle codeMono({
    double size = 13,
    double? height,
    FontWeight? weight,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        height: height,
        fontWeight: weight,
      );

  // Code-mono scaled (for editor + markdown preview content/code blocks).
  static TextStyle codeMonoBody(double scale) =>
      GoogleFonts.jetBrainsMono(fontSize: 14 * scale, height: 1.7);
  static TextStyle codeMonoBlock(double scale) =>
      GoogleFonts.jetBrainsMono(fontSize: 13 * scale);
}
