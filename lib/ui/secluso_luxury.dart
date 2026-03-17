//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

extension SeclusoLuxuryText on ThemeData {
  TextStyle? editorialHero({Color? color, double fontSize = 34}) {
    return GoogleFonts.playfairDisplay(
      textStyle: textTheme.displaySmall?.copyWith(
        color: color ?? colorScheme.onSurface,
        fontSize: fontSize,
        height: 1.02,
        letterSpacing: -0.9,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  TextStyle? editorialSection({Color? color, double fontSize = 24}) {
    return GoogleFonts.playfairDisplay(
      textStyle: textTheme.titleLarge?.copyWith(
        color: color ?? colorScheme.onSurface,
        fontSize: fontSize,
        height: 1.08,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SeclusoSectionIntro extends StatelessWidget {
  const SeclusoSectionIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.editorial = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final bool editorial;

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
            letterSpacing: 2.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style:
              editorial
                  ? theme.editorialSection(fontSize: 28)
                  : theme.textTheme.titleLarge?.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class SeclusoPageHeader extends StatelessWidget {
  const SeclusoPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class SeclusoUtilityCard extends StatelessWidget {
  const SeclusoUtilityCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SeclusoGlassCard(
      borderRadius: 22,
      padding: padding,
      tint:
          tint ??
          (dark
              ? const Color(0xFF111317).withValues(alpha: 0.94)
              : const Color(0xFFFFFCF7).withValues(alpha: 0.97)),
      child: child,
    );
  }
}

class SeclusoSystemStripItem {
  const SeclusoSystemStripItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

class SeclusoSystemStrip extends StatelessWidget {
  const SeclusoSystemStrip({super.key, required this.items});

  final List<SeclusoSystemStripItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SeclusoUtilityCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: _StripCell(item: items[i], theme: theme),
            ),
            if (i != items.length - 1)
              Container(
                width: 1,
                height: 34,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({required this.item, required this.theme});

  final SeclusoSystemStripItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class SeclusoToggle extends StatelessWidget {
  const SeclusoToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 58,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color:
              value
                  ? SeclusoColors.blue
                  : theme.colorScheme.onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                value
                    ? SeclusoColors.blueSoft.withValues(alpha: 0.85)
                    : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: value ? SeclusoColors.paper : theme.colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SeclusoFlatRow extends StatelessWidget {
  const SeclusoFlatRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: SeclusoColors.blueSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ??
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: row,
      ),
    );
  }
}
