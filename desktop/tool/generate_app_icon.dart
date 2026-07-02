// Generates every SimSync launcher icon from the one shared painter
// (lib/widgets/app_logo_mark.dart) so desktop and mobile always match. Needs the
// Flutter engine for Picture.toImage, so it runs under the test harness:
//
//   cd desktop && flutter test tool/generate_app_icon.dart
//
// Writes: macOS AppIcon (rounded squircle), iOS AppIcon (full-bleed — iOS masks
// the corners), and Android legacy ic_launcher + adaptive-icon foreground.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/widgets/app_logo_mark.dart';

Future<void> _render(
  String path,
  int size,
  void Function(Canvas, double) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  image.dispose();
}

void main() {
  test('generate SimSync launcher icons (desktop + mobile)', () async {
    // macOS — rounded squircle with transparent corners.
    const macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      await _render('$macDir/app_icon_$size.png', size,
          (c, s) => paintSyncIcon(c, s));
    }

    // macOS menu bar — flat black *template* mark on transparent (the system
    // recolors it for light/dark). One 44px asset; tray_manager scales it down
    // to the menu bar height (iconSize).
    Directory('assets/tray').createSync(recursive: true);
    await _render('assets/tray/menu_bar_icon.png', 44,
        (c, s) => paintMenuBarMark(c, s));

    // iOS — full-bleed (iOS applies its own corner mask).
    const iosDir = '../mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const ios = <String, int>{
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final entry in ios.entries) {
      await _render('$iosDir/${entry.key}', entry.value,
          (c, s) => paintSyncIcon(c, s, fullBleed: true));
    }

    // Android — legacy ic_launcher (full-bleed) + adaptive foreground (mark on
    // transparent; the gradient lives in drawable/ic_launcher_background.xml).
    const andRes = '../mobile/android/app/src/main/res';
    const legacy = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    const foreground = <String, int>{
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    for (final entry in legacy.entries) {
      await _render('$andRes/mipmap-${entry.key}/ic_launcher.png', entry.value,
          (c, s) => paintSyncIcon(c, s, fullBleed: true));
    }
    for (final entry in foreground.entries) {
      await _render(
          '$andRes/mipmap-${entry.key}/ic_launcher_foreground.png', entry.value,
          (c, s) => paintSyncForeground(c, s));
    }

    expect(File('$macDir/app_icon_1024.png').existsSync(), isTrue);
    expect(File('assets/tray/menu_bar_icon.png').existsSync(), isTrue);
    expect(File('$iosDir/Icon-App-1024x1024@1x.png').existsSync(), isTrue);
    expect(
        File('$andRes/mipmap-xxxhdpi/ic_launcher_foreground.png').existsSync(),
        isTrue);
  });
}
