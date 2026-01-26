//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/notification_permissions.dart';

class CameraSetupStatusDialog extends StatefulWidget {
  final Map<String, dynamic> result;

  const CameraSetupStatusDialog({super.key, required this.result});

  static Future<void> show(BuildContext context, Map<String, dynamic> result) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: CameraSetupStatusDialog(result: result),
          ),
    );
  }

  @override
  State<CameraSetupStatusDialog> createState() =>
      _CameraSetupStatusDialogState();
}

class _CameraSetupStatusDialogState extends State<CameraSetupStatusDialog> {
  bool? _success;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  void _startSetup() {
    setState(() => _success = null);

    final cameraName = widget.result["cameraName"]! as String;
    final ip = widget.result["cameraIp"]! as String;
    final qrCode = List<int>.from(widget.result["qrCode"]! as Uint8List);

    Log.d("CameraSetup: begin for $cameraName");

    addCamera(cameraName, ip, qrCode, false, '', '', '').then((
      firmwareVersion,
    ) async {
      if (!mounted) return;

      final success = !firmwareVersion.startsWith("Error");

      if (success) {
        await _persistCamera(cameraName, firmwareVersion);
      }

      setState(() => _success = success);

      if (success) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        });
      }
    });
  }

  Future<void> _persistCamera(String cameraName, String firmwareVersion) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_$cameraName", true);

    final existingCameraSet =
        prefs.getStringList(PrefKeys.cameraSet) ?? <String>[];
    final wasFirstCamera = existingCameraSet.isEmpty;
    if (!existingCameraSet.contains(cameraName)) {
      existingCameraSet.add(cameraName);
      await prefs.setStringList(PrefKeys.cameraSet, existingCameraSet);
      await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName, 0);
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + cameraName,
        CameraStatus.online,
      );
      await prefs.setInt(
        PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
        0,
      );
      await prefs.setInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName, 0);
      await prefs.setString(
        PrefKeys.firmwareVersionPrefix + cameraName,
        firmwareVersion,
      );
    }

    final box = AppStores.instance.cameraStore.box<Camera>();
    box.put(Camera(cameraName));

    CameraListNotifier.instance.refreshCallback?.call();

    if (wasFirstCamera) {
      await requestNotificationsAfterFirstCameraAdd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).dialogBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child:
            _success == null
                ? _buildLoading()
                : _success == true
                ? _buildSuccess()
                : _buildError(),
      ),
    );
  }

  Widget _buildLoading() => Column(
    key: const ValueKey('loading'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(
        'Setting up your camera...',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildSuccess() => Column(
    key: const ValueKey('success'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 60),
      const SizedBox(height: 20),
      Text(
        'Camera successfully added!',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildError() => Column(
    key: const ValueKey('error'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
      const SizedBox(height: 20),
      Text(
        'Failed to add camera.\nWould you like to try again?',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          const SizedBox(width: 16),
          ElevatedButton(onPressed: _startSetup, child: const Text('Retry')),
        ],
      ),
    ],
  );
}
