import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader_ui/src/api/models.dart';
import 'package:novel_reader_ui/src/ui/reader_theme.dart';

void main() {
  test('keeps dark reader palettes visually distinguishable', () {
    final List<ReaderPalette> palettes = <ReaderPalette>[
      ReaderPalette.fromPreset(ReaderThemePreset.night),
      ReaderPalette.fromPreset(ReaderThemePreset.deepNight),
      ReaderPalette.fromPreset(ReaderThemePreset.charcoal),
    ];

    for (int index = 0; index < palettes.length; index++) {
      final ReaderPalette palette = palettes[index];
      expect(_contrastRatio(palette.text, palette.background), greaterThan(7));
      expect(
        _contrastRatio(palette.panel, palette.background),
        greaterThan(1.15),
      );
      for (
        int otherIndex = index + 1;
        otherIndex < palettes.length;
        otherIndex++
      ) {
        expect(
          _colorDistance(palette.background, palettes[otherIndex].background),
          greaterThan(24),
        );
      }
    }
  });
}

double _colorDistance(Color first, Color second) {
  final int red = _channel(first.r) - _channel(second.r);
  final int green = _channel(first.g) - _channel(second.g);
  final int blue = _channel(first.b) - _channel(second.b);
  return math.sqrt((red * red + green * green + blue * blue).toDouble());
}

double _contrastRatio(Color first, Color second) {
  final double firstLuminance = _relativeLuminance(first);
  final double secondLuminance = _relativeLuminance(second);
  final double lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final double darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}

double _relativeLuminance(Color color) {
  double channel(int value) {
    final double normalized = value / 255;
    return normalized <= .03928
        ? normalized / 12.92
        : math.pow((normalized + .055) / 1.055, 2.4).toDouble();
  }

  return channel(_channel(color.r)) * .2126 +
      channel(_channel(color.g)) * .7152 +
      channel(_channel(color.b)) * .0722;
}

int _channel(double value) => (value * 255).round().clamp(0, 255);
