//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

class SeclusoScaffold extends StatelessWidget {
  const SeclusoScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Stack(
          fit: StackFit.expand,
          children: [const SeclusoBackdrop(), body],
        ),
      ),
    );
  }
}

PreferredSizeWidget seclusoAppBar(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<Widget>? actions,
  bool centerTitle = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return AppBar(
    backgroundColor: dark ? Colors.transparent : const Color(0xFFF2F2F7),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: leading,
    centerTitle: centerTitle,
    titleSpacing: centerTitle ? null : 18,
    title: Text(title),
    actions: actions,
    flexibleSpace: Container(
      decoration: BoxDecoration(
        color: dark ? null : const Color(0xFFF2F2F7),
        gradient:
            dark
                ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SeclusoColors.ink.withValues(alpha: 0.92),
                    SeclusoColors.ink.withValues(alpha: 0.74),
                    Colors.transparent,
                  ],
                )
                : null,
        border:
            dark
                ? null
                : const Border(bottom: BorderSide(color: Color(0x140A0A0A))),
        boxShadow:
            dark
                ? null
                : const [
                  BoxShadow(
                    color: Color(0x050A0A0A),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
      ),
    ),
  );
}

class SeclusoBackdrop extends StatelessWidget {
  const SeclusoBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              dark
                  ? const [
                    Color(0xFF080808),
                    Color(0xFF0B0B0C),
                    Color(0xFF111214),
                  ]
                  : const [
                    Color(0xFFF7F7FB),
                    Color(0xFFF4F4F8),
                    Color(0xFFF1F1F6),
                  ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (dark)
            Positioned(
              top: -90,
              right: -40,
              child: _AmbientGlow(
                size: 220,
                color: SeclusoColors.blue.withValues(alpha: 0.08),
              ),
            ),
          if (dark)
            Positioned(
              bottom: -180,
              left: -150,
              child: _AmbientGlow(
                size: 260,
                color: Colors.white.withValues(alpha: 0.015),
              ),
            ),
          if (dark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.32),
                    ],
                  ),
                ),
              ),
            ),
          if (!dark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.2),
                      Colors.transparent,
                      const Color(0xFFE4E6EE).withValues(alpha: 0.28),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SeclusoGlassCard extends StatelessWidget {
  const SeclusoGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 24,
    this.borderColor,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color:
            tint ??
            (dark
                ? const Color(0xFF111113).withValues(alpha: 0.9)
                : const Color(0xFFFFFCF8).withValues(alpha: 0.96)),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color:
              borderColor ??
              (dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0x140A0A0A)),
        ),
        boxShadow: [
          BoxShadow(
            color:
                dark
                    ? Colors.black.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.07),
            blurRadius: dark ? 18 : 16,
            offset: Offset(0, dark ? 8 : 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SeclusoStatusChip extends StatelessWidget {
  const SeclusoStatusChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
  });

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? SeclusoColors.blue;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: chipColor),
          const SizedBox(width: 6),
        ] else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
          ),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: chipColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
          ),
        ),
      ],
    );
  }
}

class SeclusoSectionHeader extends StatelessWidget {
  const SeclusoSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: SeclusoColors.blue,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 14),
        Text(title, style: theme.textTheme.headlineLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(subtitle!, style: theme.textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}
