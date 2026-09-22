/// 数据源内容详情使用的轻量展示基础组件。
///
/// 职责：
/// - 提供详情各区块共享、无业务状态的排版组件。
///
/// 注意：
/// - 不持有加载状态，不发起 IO，也不处理领域动作。
part of 'source_content_detail_sheet.dart';

class _AdaptiveSingleLineText extends StatelessWidget {
  const _AdaptiveSingleLineText({
    required this.text,
    required this.style,
    required this.minFontSize,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final TextAlign? textAlign;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseFontSize = style.fontSize ?? 16;
        final minScale = minFontSize / baseFontSize;
        if (constraints.maxWidth <= 0) {
          return Text(
            text,
            style: style.copyWith(fontSize: baseFontSize * minScale),
            maxLines: maxLines,
            overflow: overflow,
            softWrap: false,
            textAlign: textAlign,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: double.infinity);

        final neededScale = painter.width <= 0 ? 1 : constraints.maxWidth / painter.width;
        final effectiveScale = neededScale.clamp(minScale, 1.0);
        return Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: false,
          style: style.copyWith(fontSize: baseFontSize * effectiveScale),
        );
      },
    );
  }
}
