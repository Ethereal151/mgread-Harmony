import 'package:flutter/material.dart';

import '../api/models.dart';

const String readerDefaultFontFamily = 'MiSans';
const String readerFontPackageName = 'novel_reader_ui';
const String readerPackageFontFamily =
    'packages/$readerFontPackageName/$readerDefaultFontFamily';

@immutable
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.panel,
    required this.divider,
    required this.accent,
    required this.systemBrightness,
  });

  final Color background;
  final Color text;
  final Color secondaryText;
  final Color panel;
  final Color divider;
  final Color accent;
  final Brightness systemBrightness;

  static ReaderPalette fromPreset(ReaderThemePreset preset) {
    return switch (preset) {
      ReaderThemePreset.day => const ReaderPalette(
        background: Color(0xFFF7F4EE),
        text: Color(0xFF292824),
        secondaryText: Color(0xFF666158),
        panel: Color(0xFFFFFCF6),
        divider: Color(0x1F2F2C26),
        accent: Color(0xFFE7683F),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.eyeCare => const ReaderPalette(
        background: Color(0xFFDDE8D5),
        text: Color(0xFF253025),
        secondaryText: Color(0xFF53604F),
        panel: Color(0xFFE8F0E3),
        divider: Color(0x1F263526),
        accent: Color(0xFF4F7857),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.parchment => const ReaderPalette(
        background: Color(0xFFF1E1BF),
        text: Color(0xFF3B3022),
        secondaryText: Color(0xFF69583F),
        panel: Color(0xFFF7E9CB),
        divider: Color(0x263A2F21),
        accent: Color(0xFF9D5F32),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.night => const ReaderPalette(
        // Warm plum: keep night mode soft without collapsing into the
        // blue-black and neutral-charcoal presets below.
        background: Color(0xFF2C2028),
        text: Color(0xFFDED8DF),
        secondaryText: Color(0xFFBDAFBD),
        panel: Color(0xFF3B2D38),
        divider: Color(0x4A9A8397),
        accent: Color(0xFFD58B9A),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.mistBlue => const ReaderPalette(
        background: Color(0xFFDCE7EE),
        text: Color(0xFF27343B),
        secondaryText: Color(0xFF53636B),
        panel: Color(0xFFEAF1F5),
        divider: Color(0x242D3D45),
        accent: Color(0xFF527B91),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.deepNight => const ReaderPalette(
        // Blue-black: deliberately blue enough to remain identifiable in
        // the compact settings swatch and on a dim reading surface.
        background: Color(0xFF101C2C),
        text: Color(0xFFC8D8EA),
        secondaryText: Color(0xFF98B0C9),
        panel: Color(0xFF1B2C43),
        divider: Color(0x507FA7C8),
        accent: Color(0xFF78A9D7),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.charcoal => const ReaderPalette(
        // Neutral charcoal: the lightest dark preset, with a neutral hue so
        // it is visibly different from both warm night and blue deep-night.
        background: Color(0xFF323538),
        text: Color(0xFFE6E7E5),
        secondaryText: Color(0xFFC2C5C5),
        panel: Color(0xFF40454A),
        divider: Color(0x4D9EA3A5),
        accent: Color(0xFFD49B73),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.oled => const ReaderPalette(
        background: Color(0xFF000000),
        text: Color(0xFFFFFFFF),
        secondaryText: Color(0xFFD6D6D6),
        panel: Color(0xFF000000),
        divider: Color(0x66FFFFFF),
        accent: Color(0xFFFFFFFF),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.midnight => const ReaderPalette(
        background: Color(0xFF25143F),
        text: Color(0xFFE4DBFF),
        secondaryText: Color(0xFFBEB0DB),
        panel: Color(0xFF36265A),
        divider: Color(0x70705A9A),
        accent: Color(0xFFB89AFF),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.forestNight => const ReaderPalette(
        background: Color(0xFF123C2B),
        text: Color(0xFFD8F2E3),
        secondaryText: Color(0xFFA4D0B5),
        panel: Color(0xFF21533E),
        divider: Color(0x555A967A),
        accent: Color(0xFF77D0A1),
        systemBrightness: Brightness.dark,
      ),
      ReaderThemePreset.lavenderMist => const ReaderPalette(
        background: Color(0xFFE2D8F2),
        text: Color(0xFF332D4D),
        secondaryText: Color(0xFF6D6487),
        panel: Color(0xFFF8F6FF),
        divider: Color(0x2639305F),
        accent: Color(0xFF8066B8),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.roseTea => const ReaderPalette(
        background: Color(0xFFF7E5E6),
        text: Color(0xFF4B2D34),
        secondaryText: Color(0xFF7B5962),
        panel: Color(0xFFFFF4F4),
        divider: Color(0x264B2D34),
        accent: Color(0xFFB65C73),
        systemBrightness: Brightness.light,
      ),
      ReaderThemePreset.seaGlass => const ReaderPalette(
        background: Color(0xFFC7E6D8),
        text: Color(0xFF203D39),
        secondaryText: Color(0xFF52766F),
        panel: Color(0xFFEFF8F4),
        divider: Color(0x26305D55),
        accent: Color(0xFF3A8C7B),
        systemBrightness: Brightness.light,
      ),
    };
  }
}

/// Builds the Material theme used by reader-owned surfaces and routes.
///
/// Reader routes are sometimes pushed from the state context above the local
/// reader [Theme]. Keeping this factory here lets those routes carry the
/// active reader palette instead of inheriting the host application's theme.
ThemeData readerThemeData(
  ReaderPalette palette, {
  ReaderFontPreset font = ReaderFontPreset.system,
}) {
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: palette.systemBrightness,
      ).copyWith(
        primary: palette.accent,
        surface: palette.panel,
        onSurface: palette.text,
        outline: palette.divider,
      );
  final ThemeData baseTheme = ThemeData(
    useMaterial3: true,
    brightness: palette.systemBrightness,
    colorScheme: scheme,
    fontFamily: font == ReaderFontPreset.system
        ? readerPackageFontFamily
        : readerFontFamily(font),
    fontFamilyFallback: readerFontFallback(font),
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.divider,
  );
  return baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(
      bodyColor: palette.text,
      displayColor: palette.text,
    ),
    iconTheme: IconThemeData(color: palette.text),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size.square(48)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      minTileHeight: 52,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Paints one of the six reader-owned background treatments.
///
/// The same widget is used for the full reading surface and settings previews,
/// so thumbnails never drift away from the actual treatment.
class ReaderBackgroundSurface extends StatelessWidget {
  const ReaderBackgroundSurface({
    super.key,
    required this.preset,
    required this.palette,
    this.child,
  });

  final ReaderBackgroundPreset preset;
  final ReaderPalette palette;
  final Widget? child;

  static const String _assetPackage = readerFontPackageName;

  @override
  Widget build(BuildContext context) {
    final Widget background = switch (preset) {
      ReaderBackgroundPreset.plain => ColoredBox(color: palette.background),
      ReaderBackgroundPreset.softPaper => _RasterReaderBackground(
        asset: 'assets/backgrounds/warm_fiber_paper.webp',
        palette: palette,
        repeat: ImageRepeat.repeat,
      ),
      ReaderBackgroundPreset.ricePaper => _RasterReaderBackground(
        asset: 'assets/backgrounds/ivory_cotton_paper.webp',
        palette: palette,
        repeat: ImageRepeat.repeat,
      ),
      ReaderBackgroundPreset.clouds => CustomPaint(
        painter: _ReaderSceneryPainter(
          palette: palette,
          kind: _ReaderSceneryKind.clouds,
        ),
      ),
      ReaderBackgroundPreset.mistMountains => _RasterReaderBackground(
        asset: 'assets/backgrounds/mist_mountains.webp',
        palette: palette,
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
      ),
      ReaderBackgroundPreset.distantLandscape => CustomPaint(
        painter: _ReaderSceneryPainter(
          palette: palette,
          kind: _ReaderSceneryKind.distantLandscape,
        ),
      ),
    };
    return Stack(fit: StackFit.expand, children: <Widget>[background, ?child]);
  }
}

class _RasterReaderBackground extends StatelessWidget {
  const _RasterReaderBackground({
    required this.asset,
    required this.palette,
    this.fit = BoxFit.none,
    this.repeat = ImageRepeat.noRepeat,
    this.alignment = Alignment.center,
  });

  final String asset;
  final ReaderPalette palette;
  final BoxFit fit;
  final ImageRepeat repeat;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final bool dark = palette.systemBrightness == Brightness.dark;
    return ColoredBox(
      color: palette.background,
      child: Opacity(
        opacity: dark ? .14 : .84,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            palette.background.withValues(alpha: dark ? .18 : .1),
            BlendMode.srcOver,
          ),
          child: Image.asset(
            asset,
            package: ReaderBackgroundSurface._assetPackage,
            fit: fit,
            repeat: repeat,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, Object error, StackTrace? stackTrace) {
              debugPrint(
                'novel_reader_ui background asset failed: '
                '$asset ($error)\n$stackTrace',
              );
              return ColoredBox(color: palette.background);
            },
          ),
        ),
      ),
    );
  }
}

enum _ReaderSceneryKind { clouds, distantLandscape }

class _ReaderSceneryPainter extends CustomPainter {
  const _ReaderSceneryPainter({required this.palette, required this.kind});

  final ReaderPalette palette;
  final _ReaderSceneryKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final bool dark = palette.systemBrightness == Brightness.dark;
    final Rect bounds = Offset.zero & size;
    final Color tint = dark
        ? Color.lerp(palette.background, palette.secondaryText, .2)!
        : Color.lerp(palette.background, const Color(0xFFB8C8CF), .35)!;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(palette.background, palette.panel, .5)!,
            palette.background,
            Color.lerp(palette.background, tint, .22)!,
          ],
        ).createShader(bounds),
    );
    if (kind == _ReaderSceneryKind.clouds) {
      _paintClouds(canvas, size, tint);
    } else {
      _paintLandscape(canvas, size, tint);
    }
  }

  void _paintClouds(Canvas canvas, Size size, Color tint) {
    final Paint cloud = Paint()..style = PaintingStyle.fill;
    final List<(double, double, double, double)> layers =
        <(double, double, double, double)>[
          (-.18, .15, 1.15, .26),
          (.36, .37, .9, .20),
          (-.25, .64, 1.0, .19),
        ];
    for (int index = 0; index < layers.length; index++) {
      final (double x, double y, double width, double height) = layers[index];
      cloud.color = Color.lerp(
        tint,
        palette.panel,
        index.isEven ? .58 : .76,
      )!.withValues(alpha: .24 + index * .035);
      final Rect rect = Rect.fromLTWH(
        x * size.width,
        y * size.height,
        width * size.width,
        height * size.height,
      );
      final Path path = Path()
        ..moveTo(rect.left, rect.center.dy)
        ..cubicTo(
          rect.left + rect.width * .18,
          rect.top,
          rect.left + rect.width * .31,
          rect.bottom,
          rect.left + rect.width * .49,
          rect.center.dy,
        )
        ..cubicTo(
          rect.left + rect.width * .67,
          rect.top,
          rect.left + rect.width * .82,
          rect.bottom,
          rect.right,
          rect.center.dy,
        )
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(path, cloud);
    }
  }

  void _paintLandscape(Canvas canvas, Size size, Color tint) {
    final List<double> baselines = <double>[.58, .72, .84, .93];
    for (int index = 0; index < baselines.length; index++) {
      final double baseline = baselines[index] * size.height;
      final double amplitude = size.height * (.075 + index * .018);
      final Path ridge = Path()..moveTo(0, size.height);
      ridge
        ..lineTo(0, baseline)
        ..cubicTo(
          size.width * .14,
          baseline - amplitude,
          size.width * .26,
          baseline + amplitude * .25,
          size.width * .42,
          baseline - amplitude * .52,
        )
        ..cubicTo(
          size.width * .58,
          baseline + amplitude * .18,
          size.width * .77,
          baseline - amplitude * .64,
          size.width,
          baseline,
        )
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        ridge,
        Paint()
          ..color = Color.lerp(
            tint,
            palette.background,
            index * .13,
          )!.withValues(alpha: .17 + index * .055),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReaderSceneryPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.kind != kind;
}

String? readerFontFamily(ReaderFontPreset preset) {
  return switch (preset) {
    ReaderFontPreset.system => readerDefaultFontFamily,
    ReaderFontPreset.sansSerif => 'sans-serif',
    ReaderFontPreset.serif => 'serif',
  };
}

String? readerFontPackageFor(ReaderFontPreset preset) {
  return preset == ReaderFontPreset.system ? readerFontPackageName : null;
}

List<String> readerFontFallback(ReaderFontPreset preset) {
  return switch (preset) {
    ReaderFontPreset.system => const <String>[
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'PingFang SC',
    ],
    ReaderFontPreset.sansSerif => const <String>[
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'PingFang SC',
    ],
    ReaderFontPreset.serif => const <String>[
      'Noto Serif CJK SC',
      'SimSun',
      'Songti SC',
    ],
  };
}
