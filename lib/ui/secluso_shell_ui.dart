//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

TextStyle shellTitleStyle(
  BuildContext context, {
  required double fontSize,
  double designLetterSpacing = 0.55,
  Color? color,
}) {
  final theme = Theme.of(context);
  return GoogleFonts.inter(
    textStyle: theme.textTheme.headlineMedium,
    color: color ?? theme.colorScheme.onSurface,
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    letterSpacing: -designLetterSpacing,
    height: 33 / 22,
  );
}

class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.safeTop = true,
    this.backgroundColor,
  });

  final Widget body;
  final Widget? bottomNavigationBar;
  final bool safeTop;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SeclusoScaffold(
      body: ColoredBox(
        color: backgroundColor ?? Colors.transparent,
        child: SafeArea(
          top: safeTop,
          bottom: false,
          child: Column(
            children: [
              Expanded(child: body),
              if (bottomNavigationBar != null) bottomNavigationBar!,
            ],
          ),
        ),
      ),
    );
  }
}

class ShellPagePadding extends StatelessWidget {
  const ShellPagePadding({
    super.key,
    required this.child,
    this.bottomInset = 0,
  });

  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 24, 28, 20 + bottomInset),
      child: child,
    );
  }
}

class ShellCard extends StatelessWidget {
  const ShellCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color:
            color ??
            (dark
                ? const Color(0xFF111317).withValues(alpha: 0.96)
                : const Color(0xFFFDFDFE)),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              borderColor ??
              (dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0x1A1A2033)),
        ),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color:
                    dark
                        ? Colors.black.withValues(alpha: 0.24)
                        : Colors.black.withValues(alpha: 0.04),
                blurRadius: dark ? 24 : 14,
                offset: const Offset(0, 10),
              ),
            ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ShellTopAccentBorderPainter extends CustomPainter {
  const ShellTopAccentBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.revealHeight,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double revealHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, revealHeight));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ShellTopAccentBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.revealHeight != revealHeight;
  }
}

class ShellSectionLabel extends StatelessWidget {
  const ShellSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.32)
                : const Color(0xFF9BA1B1),
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }
}

class ShellBadge extends StatelessWidget {
  const ShellBadge({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final badgeColor = color ?? SeclusoColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color:
            filled
                ? badgeColor.withValues(alpha: dark ? 0.18 : 0.16)
                : (dark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.84)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              filled
                  ? badgeColor.withValues(alpha: 0.45)
                  : (dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0x180A0A0A)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: badgeColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: filled ? badgeColor : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class ShellStatusDot extends StatelessWidget {
  const ShellStatusDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class ShellSettingsGroup extends StatelessWidget {
  const ShellSettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.titleGap = 12,
    this.radius = 22,
    this.titleStyle,
    this.cardColor,
    this.borderColor,
    this.dividerColor,
    this.boxShadow,
  });

  final String title;
  final List<Widget> children;
  final double titleGap;
  final double radius;
  final TextStyle? titleStyle;
  final Color? cardColor;
  final Color? borderColor;
  final Color? dividerColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titleStyle == null)
          ShellSectionLabel(title)
        else
          Text(title.toUpperCase(), style: titleStyle),
        SizedBox(height: titleGap),
        ShellCard(
          padding: EdgeInsets.zero,
          radius: radius,
          color: cardColor,
          borderColor: borderColor,
          boxShadow: boxShadow,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 1,
                    color:
                        dividerColor ??
                        Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ShellSettingsRow extends StatelessWidget {
  const ShellSettingsRow({
    super.key,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.height = 56,
    this.horizontalPadding = 18,
    this.titleFontSize = 16,
    this.valueFontSize = 16,
    this.titleWeight = FontWeight.w500,
    this.valueWeight = FontWeight.w500,
    this.chevronSize = 24,
    this.valueChevronGap = 10,
    this.titleColor,
    this.valueColor,
    this.chevronColor,
    this.titleStyle,
    this.valueStyle,
  });

  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;
  final double horizontalPadding;
  final double titleFontSize;
  final double valueFontSize;
  final FontWeight titleWeight;
  final FontWeight valueWeight;
  final double chevronSize;
  final double valueChevronGap;
  final Color? titleColor;
  final Color? valueColor;
  final Color? chevronColor;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style:
                    titleStyle ??
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: titleColor,
                      fontSize: titleFontSize,
                      fontWeight: titleWeight,
                    ),
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                style:
                    valueStyle ??
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                      color:
                          valueColor ??
                          Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.52),
                      fontSize: valueFontSize,
                      fontWeight: valueWeight,
                    ),
              ),
              SizedBox(width: valueChevronGap),
            ],
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  size: chevronSize,
                  color:
                      chevronColor ??
                      Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
                ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return row;
    }

    return InkWell(onTap: onTap, child: row);
  }
}

class ShellToggle extends StatelessWidget {
  const ShellToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 50,
    this.height = 30,
    this.padding = 3,
    this.thumbSize = 24,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.thumbShadow,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;
  final double padding;
  final double thumbSize;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final List<BoxShadow>? thumbShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color:
              value
                  ? activeColor ?? const Color(0xFF8FB5F4)
                  : theme.brightness == Brightness.dark
                  ? inactiveColor ?? Colors.white.withValues(alpha: 0.18)
                  : inactiveColor ?? const Color(0xFFE7E8EE),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              color: thumbColor ?? Colors.white,
              shape: BoxShape.circle,
              boxShadow:
                  thumbShadow ??
                  [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShellBottomNav extends StatelessWidget {
  const ShellBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.activityBadgeCount,
    this.settingsAlertBadge = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? activityBadgeCount;
  final bool settingsAlertBadge;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const designWidth = 310.0;
    const designHeight = 76.0;
    const itemTop = 10.25;
    const itemWidth = 64.0;
    const itemHeight = 39.5;
    final items = const [
      (label: 'Home', icon: Icons.home_outlined, left: 16.25),
      (label: 'Activity', icon: Icons.pin_drop_outlined, left: 80.75),
      (label: 'System', icon: Icons.shield_outlined, left: 145.25),
      (label: 'Settings', icon: Icons.settings_outlined, left: 209.75),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = width / designWidth;
        return SizedBox(
          width: width,
          height: designHeight * scale,
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: designWidth,
              height: designHeight,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                dark
                                    ? const Color(0xF2050505)
                                    : Colors.white.withValues(alpha: 0.95),
                            border: Border(
                              top: BorderSide(
                                color:
                                    dark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : const Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < items.length; i++)
                    Positioned(
                      left: items[i].left,
                      top: itemTop,
                      width: itemWidth,
                      height: itemHeight,
                      child: _ShellNavItem(
                        label: items[i].label,
                        icon: items[i].icon,
                        selected: currentIndex == i,
                        badgeCount: i == 1 ? activityBadgeCount : null,
                        showAlertBadge: i == 3 ? settingsAlertBadge : false,
                        onTap: () => onTap(i),
                      ),
                    ),
                  Positioned(
                    bottom: 6,
                    child: Container(
                      width: 120,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            dark
                                ? Colors.white.withValues(alpha: 0.4)
                                : const Color(0xFF9CA3AF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badgeCount,
    this.showAlertBadge = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? badgeCount;
  final bool showAlertBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final activeColor = const Color(0xFF8BB3EE);
    final inactiveColor =
        dark ? Colors.white.withValues(alpha: 0.3) : const Color(0xFF9AA0AE);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 39.5,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 22,
                top: 4,
                child:
                    label == 'Home'
                        ? _DesignHomeNavIcon(
                          size: 20,
                          color: selected ? activeColor : inactiveColor,
                        )
                        : label == 'Activity'
                        ? _DesignActivityNavIcon(
                          size: 20,
                          color: selected ? activeColor : inactiveColor,
                        )
                        : label == 'System'
                        ? _DesignSystemNavIcon(
                          size: 20,
                          color: selected ? activeColor : inactiveColor,
                        )
                        : label == 'Settings'
                        ? _DesignSettingsNavIcon(
                          size: 20,
                          color: selected ? activeColor : inactiveColor,
                        )
                        : Icon(
                          icon,
                          size: 20,
                          color: selected ? activeColor : inactiveColor,
                        ),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  right: 16,
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$badgeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              if (showAlertBadge)
                Positioned(
                  right: 16,
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '!',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 26,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? activeColor : inactiveColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
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

class _DesignActivityNavIcon extends StatelessWidget {
  const _DesignActivityNavIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignActivityNavPainter(color: color)),
    );
  }
}

class _DesignHomeNavIcon extends StatelessWidget {
  const _DesignHomeNavIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignHomeNavPainter(color: color)),
    );
  }
}

class _DesignSystemNavIcon extends StatelessWidget {
  const _DesignSystemNavIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignSystemNavPainter(color: color)),
    );
  }
}

class _DesignSettingsNavIcon extends StatelessWidget {
  const _DesignSettingsNavIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DesignSettingsNavPainter(color: color)),
    );
  }
}

class _DesignActivityNavPainter extends CustomPainter {
  const _DesignActivityNavPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (18.3333 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (15 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (12.5 / 20), size.height * (17.5 / 20))
          ..lineTo(size.width * (7.5 / 20), size.height * (2.5 / 20))
          ..lineTo(size.width * (5 / 20), size.height * (10 / 20))
          ..lineTo(size.width * (1.66667 / 20), size.height * (10 / 20));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignActivityNavPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignHomeNavPainter extends CustomPainter {
  const _DesignHomeNavPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final house =
        Path()
          ..moveTo(size.width * (2.5 / 20), size.height * (7.5 / 20))
          ..lineTo(size.width * (10 / 20), size.height * (1.66667 / 20))
          ..lineTo(size.width * (17.5 / 20), size.height * (7.5 / 20))
          ..lineTo(size.width * (17.5 / 20), size.height * (16.6667 / 20))
          ..cubicTo(
            size.width * (17.5 / 20),
            size.height * (17.1087 / 20),
            size.width * (17.3244 / 20),
            size.height * (17.5326 / 20),
            size.width * (17.0118 / 20),
            size.height * (17.8452 / 20),
          )
          ..cubicTo(
            size.width * (16.6993 / 20),
            size.height * (18.1577 / 20),
            size.width * (16.2754 / 20),
            size.height * (18.3333 / 20),
            size.width * (15.8333 / 20),
            size.height * (18.3333 / 20),
          )
          ..lineTo(size.width * (4.16667 / 20), size.height * (18.3333 / 20))
          ..cubicTo(
            size.width * (3.72464 / 20),
            size.height * (18.3333 / 20),
            size.width * (3.30072 / 20),
            size.height * (18.1577 / 20),
            size.width * (2.98816 / 20),
            size.height * (17.8452 / 20),
          )
          ..cubicTo(
            size.width * (2.67559 / 20),
            size.height * (17.5326 / 20),
            size.width * (2.5 / 20),
            size.height * (17.1087 / 20),
            size.width * (2.5 / 20),
            size.height * (16.6667 / 20),
          )
          ..close();
    canvas.drawPath(house, stroke);
    canvas.drawLine(
      Offset(size.width * (7.5 / 20), size.height * (18.3333 / 20)),
      Offset(size.width * (7.5 / 20), size.height * (10 / 20)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (12.5 / 20), size.height * (10 / 20)),
      Offset(size.width * (12.5 / 20), size.height * (18.3333 / 20)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * (7.5 / 20), size.height * (10 / 20)),
      Offset(size.width * (12.5 / 20), size.height * (10 / 20)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DesignHomeNavPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignSystemNavPainter extends CustomPainter {
  const _DesignSystemNavPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.5 / 20)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (10 / 20), size.height * (18.3333 / 20))
          ..cubicTo(
            size.width * (10 / 20),
            size.height * (18.3333 / 20),
            size.width * (16.6667 / 20),
            size.height * (15 / 20),
            size.width * (16.6667 / 20),
            size.height * (10 / 20),
          )
          ..lineTo(size.width * (16.6667 / 20), size.height * (4.16667 / 20))
          ..lineTo(size.width * (10 / 20), size.height * (1.66667 / 20))
          ..lineTo(size.width * (3.33333 / 20), size.height * (4.16667 / 20))
          ..lineTo(size.width * (3.33333 / 20), size.height * (10 / 20))
          ..cubicTo(
            size.width * (3.33333 / 20),
            size.height * (15 / 20),
            size.width * (10 / 20),
            size.height * (18.3333 / 20),
            size.width * (10 / 20),
            size.height * (18.3333 / 20),
          );
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignSystemNavPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignSettingsNavPainter extends CustomPainter {
  const _DesignSettingsNavPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (1.5 / 20);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width * (8.45 / 20);
    final rootRadius = size.width * (7.25 / 20);
    final gear = Path();
    for (var i = 0; i < 16; i++) {
      final angle = (-math.pi / 2) + (math.pi / 8 * i);
      final radius = i.isEven ? outerRadius : rootRadius;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        gear.moveTo(point.dx, point.dy);
      } else {
        gear.lineTo(point.dx, point.dy);
      }
    }
    gear.close();
    canvas.drawPath(gear, stroke);
    canvas.drawCircle(center, size.width * (2.5 / 20), stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignSettingsNavPainter oldDelegate) =>
      oldDelegate.color != color;
}
