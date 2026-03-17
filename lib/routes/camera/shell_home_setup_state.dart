part of 'shell_home_page.dart';

class _RelaySetupCard extends StatelessWidget {
  const _RelaySetupCard({
    required this.onScan,
    required this.metrics,
    required this.palette,
  });

  final VoidCallback onScan;
  final _ShellSetupMetrics metrics;
  final _ShellSetupPalette palette;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8BB3EE);
    return SizedBox(
      height: metrics.relayCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.relayCardColor,
          borderRadius: BorderRadius.circular(metrics.scaled(16)),
          border: Border.all(color: palette.flowCardBorderColor),
          boxShadow:
              palette.relayCardShadow == null
                  ? null
                  : [palette.relayCardShadow!],
        ),
        child: CustomPaint(
          foregroundPainter: ShellTopAccentBorderPainter(
            color: accent,
            strokeWidth: metrics.scaled(palette.relayTopBorderWidth),
            radius: metrics.scaled(16),
            revealHeight: metrics.scaled(15),
          ),
          child: Stack(
            children: [
              Positioned(
                left: metrics.scaled(20),
                top: metrics.scaled(20),
                width: metrics.scaled(58),
                height: metrics.scaled(59),
                child: _RelayQrGraphic(
                  metrics: metrics,
                  dotColor: palette.qrDotColor,
                ),
              ),
              Positioned(
                left: metrics.scaled(28),
                top: metrics.scaled(47.25),
                child: Container(
                  width: metrics.scaled(42),
                  height: metrics.scaled(1.5),
                  color: accent.withValues(alpha: 0.5),
                ),
              ),
              Positioned(
                left: metrics.scaled(92),
                top: metrics.scaled(22),
                child: Text(
                  'Connect your relay',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.relayCardTitleColor,
                    fontSize: metrics.scaled(14),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    height: 21 / 14,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(92),
                top: metrics.scaled(49),
                child: SizedBox(
                  width: metrics.scaled(136.14),
                  child: Text(
                    'Scan the QR code to your\nSecluso relay to create an\nencrypted link.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.relayCardBodyColor,
                      fontSize: metrics.scaled(11),
                      height: 17.88 / 11,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(20),
                right: metrics.scaled(20),
                top: metrics.scaled(120.62),
                child: Material(
                  color: palette.relayButtonColor,
                  borderRadius: BorderRadius.circular(metrics.scaled(12)),
                  child: InkWell(
                    onTap: onScan,
                    borderRadius: BorderRadius.circular(metrics.scaled(12)),
                    child: SizedBox(
                      height: metrics.scaled(47.5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'SCAN QR CODE',
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color: palette.relayButtonTextColor,
                              fontSize: metrics.scaled(11),
                              fontWeight: FontWeight.w500,
                              letterSpacing: metrics.scaled(1.65),
                            ),
                          ),
                          SizedBox(width: metrics.scaled(11)),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: metrics.scaled(13),
                            color: palette.relayButtonArrowColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelayFlowCard extends StatefulWidget {
  const _RelayFlowCard({required this.metrics, required this.palette});

  final _ShellSetupMetrics metrics;
  final _ShellSetupPalette palette;

  @override
  State<_RelayFlowCard> createState() => _RelayFlowCardState();
}

class _RelayFlowCardState extends State<_RelayFlowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final palette = widget.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeGreen =
        isDark ? const Color(0xFF34D399) : const Color(0xFF22C55E);
    final activeGreenText =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: metrics.flowCardHeight,
          decoration: BoxDecoration(
            color: palette.flowCardColor,
            borderRadius: BorderRadius.circular(metrics.scaled(12)),
            border: Border.all(color: palette.flowCardBorderColor),
          ),
          child: Stack(
            children: [
              Positioned(
                left: metrics.scaled(44),
                top: metrics.scaled(49),
                width: metrics.scaled(160),
                child: _AnimatedTunnelLine(
                  metrics: metrics,
                  progress: _controller.value,
                  activeColor: activeGreen,
                  trackColor: activeGreen.withValues(
                    alpha: isDark ? 0.06 : 0.1,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(16),
                top: metrics.scaled(23),
                child: _FlowNodeSurface(
                  metrics: metrics,
                  childWidth: metrics.scaled(16),
                  childHeight: metrics.scaled(16),
                  borderColor:
                      isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE5E7EB),
                  backgroundColor:
                      isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  shadowColor:
                      isDark
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.05),
                  child: _CameraGlyph(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF6B7280),
                    metrics: metrics,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(44),
                top: metrics.scaled(53),
                child: _NodeStatusBadge(
                  metrics: metrics,
                  fillColor: const Color(0xFF10B981),
                  shadowColor: const Color(0xFF22C55E).withValues(alpha: 0.4),
                  icon: _MiniLockGlyph(color: Colors.white, metrics: metrics),
                ),
              ),
              Positioned(
                left: metrics.scaled(17.41),
                top: metrics.scaled(69),
                width: metrics.scaled(37.507),
                child: Text(
                  'CAMERA',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: activeGreenText.withValues(alpha: isDark ? 0.7 : 1),
                    fontSize: metrics.scaled(8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: metrics.scaled(0.4),
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(104),
                top: metrics.scaled(23),
                child: _FlowNodeSurface(
                  metrics: metrics,
                  childWidth: metrics.scaled(18),
                  childHeight: metrics.scaled(18),
                  borderColor:
                      isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE5E7EB),
                  backgroundColor:
                      isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  shadowColor: Colors.transparent,
                  child: _RelayGlyph(
                    color: palette.flowInactiveIconColor,
                    metrics: metrics,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(132),
                top: metrics.scaled(53),
                child: _NodeStatusBadge(
                  metrics: metrics,
                  fillColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  borderColor:
                      isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE5E7EB),
                  icon: _BlindGlyph(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : const Color(0xFF9CA3AF),
                    metrics: metrics,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(96.26),
                top: metrics.scaled(69),
                width: metrics.scaled(55.859),
                child: Text(
                  'BLIND RELAY',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.flowInactiveLabelColor.withValues(
                      alpha: isDark ? 0.56 : 1,
                    ),
                    fontSize: metrics.scaled(8),
                    fontWeight: FontWeight.w500,
                    letterSpacing: metrics.scaled(0.4),
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(192),
                top: metrics.scaled(23),
                child: _FlowNodeSurface(
                  metrics: metrics,
                  childWidth: metrics.scaled(16),
                  childHeight: metrics.scaled(16),
                  borderColor:
                      isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE5E7EB),
                  backgroundColor:
                      isDark ? const Color(0xFF0A0A0A) : Colors.white,
                  shadowColor:
                      isDark
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.05),
                  child: _PhoneGlyph(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF6B7280),
                    metrics: metrics,
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(220),
                top: metrics.scaled(53),
                child: _NodeStatusBadge(
                  metrics: metrics,
                  fillColor: const Color(0xFF10B981),
                  shadowColor: const Color(0xFF22C55E).withValues(alpha: 0.4),
                  icon: _MiniLockGlyph(color: Colors.white, metrics: metrics),
                ),
              ),
              Positioned(
                left: metrics.scaled(196.9),
                top: metrics.scaled(69),
                width: metrics.scaled(30.589),
                child: Text(
                  'PHONE',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: activeGreenText.withValues(alpha: isDark ? 0.7 : 1),
                    fontSize: metrics.scaled(8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: metrics.scaled(0.4),
                  ),
                ),
              ),
              Positioned(
                left: metrics.scaled(24.6),
                top: metrics.scaled(100),
                width: metrics.scaled(200.771),
                child: Text(
                  'Your relay routes encrypted data it cannot read',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.flowMetaColor.withValues(
                      alpha: isDark ? 1 : 1,
                    ),
                    fontSize: metrics.scaled(9),
                    height: 14.63 / 9,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FlowNodeSurface extends StatelessWidget {
  const _FlowNodeSurface({
    required this.metrics,
    required this.childWidth,
    required this.childHeight,
    required this.borderColor,
    required this.backgroundColor,
    required this.shadowColor,
    required this.child,
  });

  final _ShellSetupMetrics metrics;
  final double childWidth;
  final double childHeight;
  final Color borderColor;
  final Color backgroundColor;
  final Color shadowColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: metrics.scaled(40),
      height: metrics.scaled(40),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(metrics.scaled(12)),
        border: Border.all(color: borderColor),
        boxShadow:
            shadowColor == Colors.transparent
                ? null
                : [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: metrics.scaled(2),
                    offset: Offset(0, metrics.scaled(1)),
                  ),
                ],
      ),
      child: Center(
        child: SizedBox(width: childWidth, height: childHeight, child: child),
      ),
    );
  }
}

class _NodeStatusBadge extends StatelessWidget {
  const _NodeStatusBadge({
    required this.metrics,
    required this.fillColor,
    required this.icon,
    this.borderColor = Colors.transparent,
    this.shadowColor = Colors.transparent,
  });

  final _ShellSetupMetrics metrics;
  final Color fillColor;
  final Widget icon;
  final Color borderColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: metrics.scaled(16),
      height: metrics.scaled(16),
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
        boxShadow:
            shadowColor == Colors.transparent
                ? null
                : [
                  BoxShadow(color: shadowColor, blurRadius: metrics.scaled(5)),
                ],
      ),
      child: Center(
        child: SizedBox(
          width: metrics.scaled(8),
          height: metrics.scaled(8),
          child: icon,
        ),
      ),
    );
  }
}

class _PhoneGlyph extends StatelessWidget {
  const _PhoneGlyph({required this.color, required this.metrics});

  final Color color;
  final _ShellSetupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PhoneGlyphPainter(color),
      size: Size.square(metrics.scaled(15)),
    );
  }
}

class _RelayGlyph extends StatelessWidget {
  const _RelayGlyph({required this.color, required this.metrics});

  final Color color;
  final _ShellSetupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RelayGlyphPainter(color),
      size: Size.square(metrics.scaled(15)),
    );
  }
}

class _CameraGlyph extends StatelessWidget {
  const _CameraGlyph({required this.color, required this.metrics});

  final Color color;
  final _ShellSetupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CameraGlyphPainter(color),
      size: Size.square(metrics.scaled(15)),
    );
  }
}

class _MiniLockGlyph extends StatelessWidget {
  const _MiniLockGlyph({required this.color, required this.metrics});

  final Color color;
  final _ShellSetupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniLockGlyphPainter(color),
      size: Size.square(metrics.scaled(8)),
    );
  }
}

class _BlindGlyph extends StatelessWidget {
  const _BlindGlyph({required this.color, required this.metrics});

  final Color color;
  final _ShellSetupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BlindGlyphPainter(color),
      size: Size.square(metrics.scaled(8)),
    );
  }
}

class _PhoneGlyphPainter extends CustomPainter {
  const _PhoneGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * (1 / 16);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (3.33333 / 16),
        size.height * (1.33333 / 16),
        size.width * (9.33334 / 16),
        size.height * (13.33334 / 16),
      ),
      Radius.circular(size.width * (1.33333 / 16)),
    );
    canvas.drawRRect(body, paint);
    canvas.drawCircle(
      Offset(size.width * (8 / 16), size.height * (12 / 16)),
      size.width * (0.35 / 16),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _PhoneGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RelayGlyphPainter extends CustomPainter {
  const _RelayGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * (1.125 / 18);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final path =
        Path()
          ..moveTo(size.width * (13.5 / 18), size.height * (7.5 / 18))
          ..lineTo(size.width * (12.555 / 18), size.height * (7.5 / 18))
          ..cubicTo(
            size.width * (12.2744 / 18),
            size.height * (6.41325 / 18),
            size.width * (11.6946 / 18),
            size.height * (5.42699 / 18),
            size.width * (10.8815 / 18),
            size.height * (4.6533 / 18),
          )
          ..cubicTo(
            size.width * (10.0684 / 18),
            size.height * (3.8796 / 18),
            size.width * (9.05454 / 18),
            size.height * (3.34949 / 18),
            size.width * (7.95519 / 18),
            size.height * (3.12321 / 18),
          )
          ..cubicTo(
            size.width * (6.85585 / 18),
            size.height * (2.89692 / 18),
            size.width * (5.71507 / 18),
            size.height * (2.98353 / 18),
            size.width * (4.66249 / 18),
            size.height * (3.37319 / 18),
          )
          ..cubicTo(
            size.width * (3.60991 / 18),
            size.height * (3.76286 / 18),
            size.width * (2.68773 / 18),
            size.height * (4.43995 / 18),
            size.width * (2.00074 / 18),
            size.height * (5.32754 / 18),
          )
          ..cubicTo(
            size.width * (1.31375 / 18),
            size.height * (6.21512 / 18),
            size.width * (0.889492 / 18),
            size.height * (7.27761 / 18),
            size.width * (0.77618 / 18),
            size.height * (8.39427 / 18),
          )
          ..cubicTo(
            size.width * (0.662868 / 18),
            size.height * (9.51092 / 18),
            size.width * (0.865043 / 18),
            size.height * (10.637 / 18),
            size.width * (1.35973 / 18),
            size.height * (11.6445 / 18),
          )
          ..cubicTo(
            size.width * (1.85442 / 18),
            size.height * (12.652 / 18),
            size.width * (2.62179 / 18),
            size.height * (13.5005 / 18),
            size.width * (3.57464 / 18),
            size.height * (14.0937 / 18),
          )
          ..cubicTo(
            size.width * (4.52748 / 18),
            size.height * (14.6868 / 18),
            size.width * (5.62761 / 18),
            size.height * (15.0008 / 18),
            size.width * (6.75 / 18),
            size.height * (15 / 18),
          )
          ..lineTo(size.width * (13.5 / 18), size.height * (15 / 18))
          ..cubicTo(
            size.width * (14.4946 / 18),
            size.height * (15 / 18),
            size.width * (15.4484 / 18),
            size.height * (14.6049 / 18),
            size.width * (16.1517 / 18),
            size.height * (13.9017 / 18),
          )
          ..cubicTo(
            size.width * (16.8549 / 18),
            size.height * (13.1984 / 18),
            size.width * (17.25 / 18),
            size.height * (12.2446 / 18),
            size.width * (17.25 / 18),
            size.height * (11.25 / 18),
          )
          ..cubicTo(
            size.width * (17.25 / 18),
            size.height * (10.2554 / 18),
            size.width * (16.8549 / 18),
            size.height * (9.30161 / 18),
            size.width * (16.1517 / 18),
            size.height * (8.59835 / 18),
          )
          ..cubicTo(
            size.width * (15.4484 / 18),
            size.height * (7.89509 / 18),
            size.width * (14.4946 / 18),
            size.height * (7.5 / 18),
            size.width * (13.5 / 18),
            size.height * (7.5 / 18),
          );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RelayGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CameraGlyphPainter extends CustomPainter {
  const _CameraGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * (1 / 16);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (0.666666 / 16),
        size.height * (4 / 16),
        size.width * (14.666634 / 16),
        size.height * (10 / 16),
      ),
      Radius.circular(size.width * (1.333333 / 16)),
    );
    canvas.drawRRect(body, paint);
    canvas.drawCircle(
      Offset(size.width * (8 / 16), size.height * (8.66667 / 16)),
      size.width * (2.66667 / 16),
      paint,
    );
    final topStroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * (4.66667 / 16), size.height * (4 / 16)),
      Offset(size.width * (6 / 16), size.height * (4 / 16)),
      topStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _MiniLockGlyphPainter extends CustomPainter {
  const _MiniLockGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * (1 / 8);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1 / 8),
        size.height * (3.66667 / 8),
        size.width * (6 / 8),
        size.height * (3.66666 / 8),
      ),
      Radius.circular(size.width * (0.666667 / 8)),
    );
    final shackle =
        Path()
          ..moveTo(size.width * (2.33333 / 8), size.height * (3.66667 / 8))
          ..lineTo(size.width * (2.33333 / 8), size.height * (2.33333 / 8))
          ..arcToPoint(
            Offset(size.width * (5.66667 / 8), size.height * (2.33333 / 8)),
            radius: Radius.circular(size.width * (1.66667 / 8)),
            clockwise: true,
          )
          ..lineTo(size.width * (5.66667 / 8), size.height * (3.66667 / 8));
    canvas.drawPath(shackle, paint);
    canvas.drawRRect(body, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniLockGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _BlindGlyphPainter extends CustomPainter {
  const _BlindGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * (0.833333 / 8);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final path =
        Path()
          ..moveTo(size.width * (5.98 / 8), size.height * (5.98 / 8))
          ..cubicTo(
            size.width * (5.4102 / 8),
            size.height * (6.41433 / 8),
            size.width * (4.71637 / 8),
            size.height * (6.65495 / 8),
            size.width * (4 / 8),
            size.height * (6.66667 / 8),
          )
          ..cubicTo(
            size.width * (1.66667 / 8),
            size.height * (6.66667 / 8),
            size.width * (0.333333 / 8),
            size.height * (4 / 8),
            size.width * (0.333333 / 8),
            size.height * (4 / 8),
          )
          ..cubicTo(
            size.width * (0.747963 / 8),
            size.height * (3.2273 / 8),
            size.width * (1.32305 / 8),
            size.height * (2.5522 / 8),
            size.width * (2.02 / 8),
            size.height * (2.02 / 8),
          );
    canvas.drawPath(path, paint);
    final upperPath =
        Path()
          ..moveTo(size.width * (3.3 / 8), size.height * (1.41333 / 8))
          ..cubicTo(
            size.width * (3.52944 / 8),
            size.height * (1.35963 / 8),
            size.width * (3.76435 / 8),
            size.height * (1.33278 / 8),
            size.width * (4 / 8),
            size.height * (1.33333 / 8),
          )
          ..cubicTo(
            size.width * (6.33333 / 8),
            size.height * (1.33333 / 8),
            size.width * (7.66667 / 8),
            size.height * (4 / 8),
            size.width * (7.66667 / 8),
            size.height * (4 / 8),
          )
          ..cubicTo(
            size.width * (7.46433 / 8),
            size.height * (4.37854 / 8),
            size.width * (7.22302 / 8),
            size.height * (4.73491 / 8),
            size.width * (6.94667 / 8),
            size.height * (5.06333 / 8),
          );
    canvas.drawPath(upperPath, paint);
    canvas.drawLine(
      Offset(size.width * (0.333333 / 8), size.height * (0.333333 / 8)),
      Offset(size.width * (7.66667 / 8), size.height * (7.66667 / 8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BlindGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _AnimatedTunnelLine extends StatelessWidget {
  const _AnimatedTunnelLine({
    required this.metrics,
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  final _ShellSetupMetrics metrics;
  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: metrics.scaled(6),
      child: CustomPaint(
        painter: _AnimatedTunnelLinePainter(
          progress: progress,
          activeColor: activeColor,
          trackColor: trackColor,
        ),
      ),
    );
  }
}

class _AnimatedTunnelLinePainter extends CustomPainter {
  const _AnimatedTunnelLinePainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(size.height / 2),
      ),
      trackPaint,
    );

    final linePaint =
        Paint()
          ..color = activeColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.28
          ..strokeCap = StrokeCap.round;
    final dashWidth = size.height * 1.05;
    final dashGap = size.height * 0.9;
    final cycle = dashWidth + dashGap;
    var x = -cycle + (progress * cycle);
    final y = size.height / 2;
    while (x < size.width) {
      final dashStart = math.max(0.0, x).toDouble();
      final dashEnd = math.min(size.width, x + dashWidth).toDouble();
      if (dashEnd > dashStart) {
        canvas.drawLine(Offset(dashStart, y), Offset(dashEnd, y), linePaint);
      }
      x += cycle;
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedTunnelLinePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor;
  }
}

class _RelayQrGraphic extends StatelessWidget {
  const _RelayQrGraphic({required this.metrics, required this.dotColor});

  final _ShellSetupMetrics metrics;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8BB3EE);
    Widget corner({
      required Alignment alignment,
      required bool top,
      required bool left,
    }) {
      return Align(
        alignment: alignment,
        child: Container(
          width: metrics.scaled(14),
          height: metrics.scaled(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft:
                  top && left
                      ? Radius.circular(metrics.scaled(2))
                      : Radius.zero,
              topRight:
                  top && !left
                      ? Radius.circular(metrics.scaled(2))
                      : Radius.zero,
              bottomLeft:
                  !top && left
                      ? Radius.circular(metrics.scaled(2))
                      : Radius.zero,
              bottomRight:
                  !top && !left
                      ? Radius.circular(metrics.scaled(2))
                      : Radius.zero,
            ),
            border: Border(
              top:
                  top
                      ? BorderSide(color: accent, width: metrics.scaled(2))
                      : BorderSide.none,
              bottom:
                  !top
                      ? BorderSide(color: accent, width: metrics.scaled(2))
                      : BorderSide.none,
              left:
                  left
                      ? BorderSide(color: accent, width: metrics.scaled(2))
                      : BorderSide.none,
              right:
                  !left
                      ? BorderSide(color: accent, width: metrics.scaled(2))
                      : BorderSide.none,
            ),
          ),
        ),
      );
    }

    Widget dot(double left, double top) {
      return Positioned(
        left: metrics.scaled(left),
        top: metrics.scaled(top),
        child: Container(
          width: metrics.scaled(5),
          height: metrics.scaled(5),
          decoration: BoxDecoration(
            color: dotColor,
            borderRadius: BorderRadius.circular(metrics.scaled(1)),
          ),
        ),
      );
    }

    return SizedBox(
      width: metrics.scaled(58),
      height: metrics.scaled(59),
      child: Stack(
        children: [
          corner(alignment: Alignment.topLeft, top: true, left: true),
          corner(alignment: Alignment.topRight, top: true, left: false),
          corner(alignment: Alignment.bottomLeft, top: false, left: true),
          corner(alignment: Alignment.bottomRight, top: false, left: false),
          dot(17.5, 17.5),
          dot(33.5, 17.5),
          dot(25.5, 25.5),
          dot(17.5, 33.5),
          dot(33.5, 33.5),
        ],
      ),
    );
  }
}

class _ShellSetupMetrics {
  const _ShellSetupMetrics({
    required this.pageInset,
    required this.topPadding,
    required this.bottomPadding,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.headerToEyebrowGap,
    required this.eyebrowSize,
    required this.eyebrowLetterSpacing,
    required this.eyebrowToTitleGap,
    required this.heroTitleWidth,
    required this.heroTitleSize,
    required this.titleToSubtitleGap,
    required this.heroSubtitleWidth,
    required this.heroSubtitleSize,
    required this.subtitleToRelayCardGap,
    required this.relayCardHeight,
    required this.relayCardToFlowCardGap,
    required this.flowCardHeight,
    required this.flowCardToLinksGap,
    required this.footerSeparatorGap,
    required this.footerSeparatorSize,
    required this.linksToMetaGap,
    required this.footerMetaIconSize,
    required this.footerMetaGap,
    required this.footerMetaSize,
    required this.footerMetaLetterSpacing,
    required double scale,
  }) : _scale = scale;

  final double pageInset;
  final double topPadding;
  final double bottomPadding;
  final double titleSize;
  final double titleLetterSpacing;
  final double headerToEyebrowGap;
  final double eyebrowSize;
  final double eyebrowLetterSpacing;
  final double eyebrowToTitleGap;
  final double heroTitleWidth;
  final double heroTitleSize;
  final double titleToSubtitleGap;
  final double heroSubtitleWidth;
  final double heroSubtitleSize;
  final double subtitleToRelayCardGap;
  final double relayCardHeight;
  final double relayCardToFlowCardGap;
  final double flowCardHeight;
  final double flowCardToLinksGap;
  final double footerSeparatorGap;
  final double footerSeparatorSize;
  final double linksToMetaGap;
  final double footerMetaIconSize;
  final double footerMetaGap;
  final double footerMetaSize;
  final double footerMetaLetterSpacing;
  final double _scale;

  double scaled(double designValue) => designValue * _scale;

  factory _ShellSetupMetrics.forViewport(double width, double height) {
    final scale = width / 290;
    double scaled(double designValue) => designValue * scale;

    return _ShellSetupMetrics(
      pageInset: scaled(20),
      topPadding: scaled(12),
      bottomPadding: scaled(28),
      titleSize: scaled(22),
      titleLetterSpacing: scaled(0.55),
      headerToEyebrowGap: scaled(7),
      eyebrowSize: scaled(10),
      eyebrowLetterSpacing: scaled(0.5),
      eyebrowToTitleGap: scaled(37),
      heroTitleWidth: scaled(251.58),
      heroTitleSize: scaled(24),
      titleToSubtitleGap: scaled(7),
      heroSubtitleWidth: scaled(233.31),
      heroSubtitleSize: scaled(12),
      subtitleToRelayCardGap: scaled(30),
      relayCardHeight: scaled(191.12),
      relayCardToFlowCardGap: scaled(20),
      flowCardHeight: scaled(127),
      flowCardToLinksGap: scaled(21),
      footerSeparatorGap: scaled(10),
      footerSeparatorSize: scaled(16),
      linksToMetaGap: scaled(24),
      footerMetaIconSize: scaled(10),
      footerMetaGap: scaled(8),
      footerMetaSize: scaled(9),
      footerMetaLetterSpacing: scaled(0.225),
      scale: scale,
    );
  }
}

class _ShellSetupPalette {
  const _ShellSetupPalette({
    required this.relayTopBorderWidth,
    required this.headerTitleColor,
    required this.eyebrowColor,
    required this.heroPrimaryColor,
    required this.heroSecondaryColor,
    required this.heroSubtitleColor,
    required this.relayCardColor,
    required this.relayCardTitleColor,
    required this.relayCardBodyColor,
    required this.relayButtonColor,
    required this.relayButtonTextColor,
    required this.relayButtonArrowColor,
    required this.qrDotColor,
    required this.flowCardColor,
    required this.flowCardBorderColor,
    required this.flowNodeColor,
    required this.flowNodeBorderColor,
    required this.flowInactiveIconColor,
    required this.flowInactiveLabelColor,
    required this.flowDividerColor,
    required this.flowLockColor,
    required this.flowMetaColor,
    required this.footerLinkColor,
    required this.footerSeparatorColor,
    required this.footerMetaColor,
    this.relayCardShadow,
  });

  final double relayTopBorderWidth;
  final Color headerTitleColor;
  final Color eyebrowColor;
  final Color heroPrimaryColor;
  final Color heroSecondaryColor;
  final Color heroSubtitleColor;
  final Color relayCardColor;
  final Color relayCardTitleColor;
  final Color relayCardBodyColor;
  final Color relayButtonColor;
  final Color relayButtonTextColor;
  final Color relayButtonArrowColor;
  final Color qrDotColor;
  final Color flowCardColor;
  final Color flowCardBorderColor;
  final Color flowNodeColor;
  final Color flowNodeBorderColor;
  final Color flowInactiveIconColor;
  final Color flowInactiveLabelColor;
  final Color flowDividerColor;
  final Color flowLockColor;
  final Color flowMetaColor;
  final Color footerLinkColor;
  final Color footerSeparatorColor;
  final Color footerMetaColor;
  final BoxShadow? relayCardShadow;

  factory _ShellSetupPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return _ShellSetupPalette(
        headerTitleColor: Colors.white,
        relayTopBorderWidth: 1.5,
        eyebrowColor: Colors.white.withValues(alpha: 0.4),
        heroPrimaryColor: Colors.white,
        heroSecondaryColor: Colors.white.withValues(alpha: 0.35),
        heroSubtitleColor: Colors.white.withValues(alpha: 0.4),
        relayCardColor: Colors.white.withValues(alpha: 0.03),
        relayCardTitleColor: Colors.white,
        relayCardBodyColor: const Color(0xFF6D7077),
        relayButtonColor: Colors.white,
        relayButtonTextColor: const Color(0xFF050505),
        relayButtonArrowColor: const Color(0xFF050505).withValues(alpha: 0.4),
        qrDotColor: Colors.white.withValues(alpha: 0.3),
        flowCardColor: Colors.white.withValues(alpha: 0.02),
        flowCardBorderColor: Colors.white.withValues(alpha: 0.05),
        flowNodeColor: Colors.white.withValues(alpha: 0.06),
        flowNodeBorderColor: Colors.transparent,
        flowInactiveIconColor: Colors.white.withValues(alpha: 0.3),
        flowInactiveLabelColor: Colors.white.withValues(alpha: 0.24),
        flowDividerColor: Colors.white.withValues(alpha: 0.1),
        flowLockColor: Colors.white.withValues(alpha: 0.16),
        flowMetaColor: const Color(0xFF6A6D75),
        footerLinkColor: Colors.white.withValues(alpha: 0.6),
        footerSeparatorColor: Colors.white.withValues(alpha: 0.1),
        footerMetaColor: Colors.white.withValues(alpha: 0.3),
      );
    }
    return _ShellSetupPalette(
      headerTitleColor: const Color(0xFF111827),
      relayTopBorderWidth: 2,
      eyebrowColor: const Color(0xFF6B7280),
      heroPrimaryColor: const Color(0xFF111827),
      heroSecondaryColor: const Color(0xFF9CA3AF),
      heroSubtitleColor: const Color(0xFF6B7280),
      relayCardColor: Colors.white,
      relayCardTitleColor: const Color(0xFF111827),
      relayCardBodyColor: const Color(0xFF6B7280),
      relayButtonColor: const Color(0xFF0A0A0A),
      relayButtonTextColor: Colors.white,
      relayButtonArrowColor: Colors.white.withValues(alpha: 0.4),
      qrDotColor: const Color(0xFF9CA3AF),
      flowCardColor: const Color(0xCCF9FAFB),
      flowCardBorderColor: const Color(0xFFF3F4F6),
      flowNodeColor: Colors.white,
      flowNodeBorderColor: const Color(0xFFE5E7EB),
      flowInactiveIconColor: const Color(0xFF9CA3AF),
      flowInactiveLabelColor: const Color(0xFF9CA3AF),
      flowDividerColor: const Color(0xFFE5E7EB),
      flowLockColor: const Color(0xFFE5E7EB),
      flowMetaColor: const Color(0xFF9CA3AF),
      footerLinkColor: const Color(0xFF6B7280),
      footerSeparatorColor: const Color(0xFFE5E7EB),
      footerMetaColor: const Color(0xFF9CA3AF),
      relayCardShadow: BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    );
  }
}
