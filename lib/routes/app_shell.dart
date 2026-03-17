//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/activity_page.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'package:secluso_flutter/routes/server_page.dart';
import 'package:secluso_flutter/routes/settings_page.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.preview = false,
    this.openRelayScanOnLoad = false,
    this.previewHomeHasSynced = true,
    this.previewHomeCameras,
    this.previewHomeShowNotificationWarning = false,
    this.previewHomeShowRecentError = false,
    this.previewHomeUnreadCount,
    this.previewHomeRecentEvents,
    this.previewSystemHasSynced = true,
    this.previewSystemCameraNames,
    this.previewActivityItems,
  });

  final int initialIndex;
  final bool preview;
  final bool openRelayScanOnLoad;
  final bool previewHomeHasSynced;
  final List<CameraPreviewData>? previewHomeCameras;
  final bool previewHomeShowNotificationWarning;
  final bool previewHomeShowRecentError;
  final int? previewHomeUnreadCount;
  final List<HomeRecentEventPreviewData>? previewHomeRecentEvents;
  final bool previewSystemHasSynced;
  final List<String>? previewSystemCameraNames;
  final List<ActivityPreviewItem>? previewActivityItems;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;
  int _activityRefreshToken = 0;
  int _serverRelayScanRequestId = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    CameraUiBridge.refreshActivityCallback = () {
      if (!mounted) return;
      setState(() {
        _activityRefreshToken++;
      });
    };
    CameraUiBridge.switchShellTabCallback = (index, {openRelayScanOnLoad = false}) {
      if (!mounted) return;
      setState(() {
        _index = index;
        if (index == 1) {
          _activityRefreshToken++;
        }
        if (index == 2 && openRelayScanOnLoad) {
          _serverRelayScanRequestId++;
        }
      });
    };
  }

  @override
  void dispose() {
    if (CameraUiBridge.refreshActivityCallback != null) {
      CameraUiBridge.refreshActivityCallback = null;
    }
    if (CameraUiBridge.switchShellTabCallback != null) {
      CameraUiBridge.switchShellTabCallback = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const designNavWidth = 310.0;
    const designNavHeight = 76.0;
    final navHeight =
        MediaQuery.sizeOf(context).width / designNavWidth * designNavHeight;
    final tabs = <Widget>[
      widget.preview
          ? CamerasPage(
            shellMode: true,
            previewServerHasSynced: widget.previewHomeHasSynced,
            previewShowNotificationWarning:
                widget.previewHomeShowNotificationWarning,
            previewShowRecentError: widget.previewHomeShowRecentError,
            previewUnreadCount: widget.previewHomeUnreadCount,
            previewRecentEvents: widget.previewHomeRecentEvents,
            previewCameras:
                widget.previewHomeCameras ??
                const [
                  CameraPreviewData(
                    name: 'Front Door',
                    unreadMessages: true,
                    previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
                    statusLabel: 'Person · 2m',
                    recentActivityTitle: 'Person Detected',
                    recentActivityTimeLabel: '2m ago',
                  ),
                  CameraPreviewData(
                    name: 'Living Room',
                    previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
                    statusLabel: 'Quiet',
                  ),
                  CameraPreviewData(
                    name: 'Backyard',
                    unreadMessages: true,
                    previewAssetPath: SeclusoPreviewAssets.designBackyard,
                    statusLabel: 'Motion · 14m',
                    recentActivityTitle: 'Motion',
                    recentActivityTimeLabel: '14m ago',
                  ),
                ],
          )
          : const CamerasPage(shellMode: true),
      widget.preview
          ? ActivityPage(
            shellMode: true,
            refreshToken: _activityRefreshToken,
            previewItems:
                widget.previewActivityItems ??
                const [
                  ActivityPreviewItem(
                    cameraName: 'Front Door',
                    videoName: '2:34 PM',
                    previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
                    detections: {'human'},
                    durationLabel: '0:12',
                    sectionLabel: 'TODAY',
                  ),
                  ActivityPreviewItem(
                    cameraName: 'Backyard',
                    videoName: '2:20 PM',
                    previewAssetPath: SeclusoPreviewAssets.designBackyard,
                    detections: {},
                    durationLabel: '0:08',
                    sectionLabel: 'TODAY',
                  ),
                  ActivityPreviewItem(
                    cameraName: 'Front Door',
                    videoName: '11:15 AM',
                    previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
                    detections: {'human'},
                    durationLabel: '0:22',
                    sectionLabel: 'TODAY',
                  ),
                  ActivityPreviewItem(
                    cameraName: '',
                    videoName: '6:00 PM',
                    detections: {},
                    title: 'System',
                    subtitle: 'Armed (Away) · 6:00 PM',
                    sectionLabel: 'YESTERDAY',
                    isSystem: true,
                  ),
                  ActivityPreviewItem(
                    cameraName: 'Living Room',
                    videoName: '3:45 PM',
                    previewAssetPath: SeclusoPreviewAssets.designLivingRoom,
                    detections: {},
                    durationLabel: '0:06',
                    sectionLabel: 'YESTERDAY',
                  ),
                  ActivityPreviewItem(
                    cameraName: 'Front Door',
                    videoName: 'Mon 9:12 AM',
                    previewAssetPath: SeclusoPreviewAssets.designFrontDoor,
                    detections: {'human'},
                    durationLabel: '0:18',
                    sectionLabel: 'EARLIER THIS WEEK',
                  ),
                ],
          )
          : ActivityPage(
            shellMode: true,
            refreshToken: _activityRefreshToken,
          ),
      widget.preview
          ? ServerPage(
            showBackButton: false,
            showShellChrome: true,
            openRelayScanOnLoad: widget.openRelayScanOnLoad,
            relayScanRequestId: _serverRelayScanRequestId,
            previewHasSynced: widget.previewSystemHasSynced,
            previewServerAddr: 'relay.local:8443',
            previewCameraNames: widget.previewSystemCameraNames,
          )
          : ServerPage(
            showBackButton: false,
            showShellChrome: true,
            openRelayScanOnLoad: widget.openRelayScanOnLoad,
            relayScanRequestId: _serverRelayScanRequestId,
          ),
      widget.preview
          ? const SettingsPage(
            showShellChrome: true,
            previewNightTheme: true,
            previewNotificationsOn: true,
          )
          : const SettingsPage(showShellChrome: true),
    ];
    final navBar = ShellBottomNav(
      currentIndex: _index,
      activityBadgeCount:
          widget.preview
              ? ((widget.previewActivityItems == null ||
                      widget.previewActivityItems!.isNotEmpty)
                  ? 2
                  : null)
              : null,
      onTap:
          (index) => setState(() {
            _index = index;
            if (index == 1) {
              _activityRefreshToken++;
            }
          }),
    );

    return ShellScaffold(
      safeTop: false,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: _index == 0 ? 0 : navHeight,
            child: IndexedStack(index: _index, children: tabs),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: navBar),
        ],
      ),
    );
  }
}
