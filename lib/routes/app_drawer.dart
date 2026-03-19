//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'camera/list_cameras.dart';
import 'design_lab_page.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

final GlobalKey<CamerasPageState> camerasPageKey =
    GlobalKey<CamerasPageState>();

class AppDrawer extends StatelessWidget {
  final Function(Widget) onNavigate;

  const AppDrawer({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Drawer(
      backgroundColor: colors.surface.withValues(alpha: 0.98),
      child: Stack(
        children: [
          const SeclusoBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SeclusoGlassCard(
                      borderRadius: 28,
                      tint:
                          dark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.white.withValues(alpha: 0.9),
                      padding: EdgeInsets.zero,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors:
                                      dark
                                          ? [
                                            const Color(0xFF15171B),
                                            const Color(0xFF101114),
                                            const Color(0xFF0B0C0E),
                                          ]
                                          : [
                                            Colors.white,
                                            const Color(0xFFF6F7FB),
                                            const Color(0xFFECEFF5),
                                          ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -36,
                            right: -28,
                            child: IgnorePointer(
                              child: Container(
                                width: 138,
                                height: 138,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      SeclusoColors.blue.withValues(
                                        alpha: dark ? 0.18 : 0.14,
                                      ),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.black.withValues(
                                      alpha: dark ? 0.42 : 0.08,
                                    ),
                                    Colors.black.withValues(
                                      alpha: dark ? 0.18 : 0.02,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Secluso'.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: SeclusoColors.blue,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                RichText(
                                  text: TextSpan(
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontSize: 20),
                                    children: [
                                      const TextSpan(text: 'See everything.\n'),
                                      const TextSpan(text: 'Share '),
                                      TextSpan(
                                        text: 'nothing.',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontSize: 20,
                                              color: SeclusoColors.blueSoft,
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'A private control room for indoor feeds, relay pairing, and fast review.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildDrawerItem(
                  context,
                  Icons.camera_alt_outlined,
                  'Cameras',
                  'Feeds, events, and archive review.',
                  () => onNavigate(CamerasPage(key: camerasPageKey)),
                ),
                const SizedBox(height: 10),
                _buildDrawerItem(
                  context,
                  Icons.hub_outlined,
                  'Server',
                  'Relay pairing, trust, and sync.',
                  () => onNavigate(const AppShell(initialIndex: 2)),
                ),
                const SizedBox(height: 10),
                _buildDrawerItem(
                  context,
                  Icons.tune_outlined,
                  'Preferences',
                  'Theme, alerts, and app controls.',
                  () => onNavigate(const AppShell(initialIndex: 3)),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 10),
                  _buildDrawerItem(
                    context,
                    Icons.science_outlined,
                    'Design Lab',
                    'Open stable preview screens and pairing dialogs.',
                    () => onNavigate(const DesignLabPage()),
                  ),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async => _openLicenses(context),
                    icon: Icon(
                      Icons.description_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                    label: const Text('Licenses and version'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLicenses(BuildContext context) async {
    final clientVersion = await rustLibVersion();
    final currentYear = DateTime.now().year;
    showLicensePage(
      context: context,
      applicationName: 'Secluso Camera',
      applicationVersion: clientVersion,
      applicationIcon: Image.asset(
        'assets/icon_centered.png',
        width: 200,
        height: 200,
      ),
      applicationLegalese: '© $currentYear Secluso',
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String text,
    String subtitle,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: SeclusoColors.blue, size: 17),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward,
              size: 18,
              color: dark ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
