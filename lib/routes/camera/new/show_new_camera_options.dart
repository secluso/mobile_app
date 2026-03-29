//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'ip_camera_option.dart';
import 'qr_scan.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/ui/secluso_luxury.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';

//TODO: We need to have a check that checks if they've entered the server options, and if not, tell them to do so to avoid any weird errors

class ShowNewCameraOptions extends StatelessWidget {
  const ShowNewCameraOptions({super.key});

  /// Navigates to the proprietary (QR) camera setup page.
  Future<void> _navigateToProprietaryCamera(BuildContext context) async {
    await WidgetsBinding.instance.endOfFrame;
    await GenericCameraQrScanPage.show(context);
  }

  /// Navigates to IP camera setup page
  void _navigateToIPCamera(BuildContext context) async {
    Log.d("Before show IP camera flow");
    await WidgetsBinding.instance.endOfFrame;
    await IpCameraDialog.showIpCameraPopup(context);
    Log.d("After (IP camera navigation start)");
  }

  @override
  Widget build(BuildContext context) {
    return SeclusoScaffold(
      appBar: seclusoAppBar(context, title: 'Add camera'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Builder(
              builder: (context) {
                return const SeclusoSectionIntro(
                  eyebrow: 'Enrollment',
                  title: 'Choose the first feed path.',
                  subtitle:
                      'Begin with the guided Secluso flow, or import an existing IP feed.',
                  editorial: true,
                );
              },
            ),
            const SizedBox(height: 18),
            _CameraOptionCard(
              title: "Use a Secluso camera",
              description:
                  'Scan the included setup code and let the app guide pairing.',
              imagePath: SeclusoPreviewAssets.tabletopCamera,
              chipLabel: 'Guided setup',
              icon: Icons.qr_code_scanner_outlined,
              featured: true,
              onTap: () => _navigateToProprietaryCamera(context),
            ),
            const SizedBox(height: 16),
            _CameraOptionCard(
              title: 'Use an IP camera',
              description:
                  'Connect an IP camera with the relay address and login.',
              imagePath: SeclusoPreviewAssets.corridorFeed,
              chipLabel: 'Flexible import',
              icon: Icons.hub_outlined,
              featured: false,
              onTap: () => _navigateToIPCamera(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraOptionCard extends StatelessWidget {
  const _CameraOptionCard({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.chipLabel,
    required this.icon,
    required this.featured,
    required this.onTap,
  });

  final String title;
  final String description;
  final String imagePath;
  final String chipLabel;
  final IconData icon;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surfaceColor =
        dark ? const Color(0xFF0C0D10) : Colors.white.withValues(alpha: 0.96);
    final bodyColor =
        dark
            ? Colors.white.withValues(alpha: 0.74)
            : theme.colorScheme.onSurface.withValues(alpha: 0.66);
    final titleColor = dark ? Colors.white : theme.colorScheme.onSurface;
    final actionColor = dark ? Colors.white : theme.colorScheme.onSurface;
    if (!featured) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(30),
          border:
              dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 184,
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SeclusoStatusChip(
                              label: chipLabel,
                              icon: icon,
                              color: SeclusoColors.blueSoft,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: titleColor,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: bodyColor,
                                height: 1.42,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Text(
                                  'Open setup',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: actionColor,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: actionColor.withValues(alpha: 0.72),
                                  size: 18,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              imagePath,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(
                                      alpha: dark ? 0.22 : 0.08,
                                    ),
                                    Colors.transparent,
                                    Colors.black.withValues(
                                      alpha: dark ? 0.08 : 0.02,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(32),
        border:
            dark ? null : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              children: [
                SizedBox(
                  height: 198,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          imagePath,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(
                                  alpha: dark ? 0.04 : 0.0,
                                ),
                                Colors.black.withValues(
                                  alpha: dark ? 0.18 : 0.04,
                                ),
                                Colors.black.withValues(
                                  alpha: dark ? 0.48 : 0.22,
                                ),
                                Colors.black.withValues(
                                  alpha: dark ? 0.78 : 0.44,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        child: SeclusoStatusChip(
                          label: chipLabel,
                          icon: icon,
                          color: SeclusoColors.blueSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 270),
                        child: Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: titleColor,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: bodyColor,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Open setup',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: actionColor,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: actionColor.withValues(alpha: 0.72),
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
