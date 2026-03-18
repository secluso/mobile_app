//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'home_page.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/routes/system_shell_page.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/routes/camera/camera_ui_bridge.dart';
import 'camera/new/qr_scan.dart';
import 'camera/view_camera.dart';

class UserCredentialsQrPayload {
  final String serverUsername;
  final String serverPassword;
  final String serverAddress;

  UserCredentialsQrPayload({
    required this.serverUsername,
    required this.serverPassword,
    required this.serverAddress,
  });
}

class ServerPage extends StatefulWidget {
  final bool showBackButton;
  final bool? previewHasSynced;
  final String? previewServerAddr;
  final List<String>? previewCameraNames;
  final bool showShellChrome;
  final bool openRelayScanOnLoad;
  final int relayScanRequestId;

  const ServerPage({
    super.key,
    required this.showBackButton,
    this.previewHasSynced,
    this.previewServerAddr,
    this.previewCameraNames,
    this.showShellChrome = false,
    this.openRelayScanOnLoad = false,
    this.relayScanRequestId = 0,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? serverAddr;
  List<String> _cameraNames = const [];

  final TextEditingController _ipController = TextEditingController();
  bool hasSynced = false;
  final ValueNotifier<bool> _isDialogOpen = ValueNotifier(false);
  bool _didAutoOpenRelayScan = false;
  int _lastHandledRelayScanRequestId = -1;

  bool get _isPreviewMode => widget.previewHasSynced != null;

  @override
  void initState() {
    super.initState();
    if (_isPreviewMode) {
      hasSynced = widget.previewHasSynced!;
      serverAddr = widget.previewServerAddr;
      _cameraNames =
          widget.previewCameraNames ??
          (hasSynced && !widget.showShellChrome
              ? const ['Front Door', 'Living Room', 'Backyard']
              : const []);
      _ipController.text = widget.previewServerAddr ?? '';
      _maybeAutoOpenRelayScan();
      return;
    }
    _loadServerSettings();
  }

  void _maybeAutoOpenRelayScan() {
    final shouldAutoOpen =
        (widget.openRelayScanOnLoad && !_didAutoOpenRelayScan) ||
        (widget.relayScanRequestId > 0 &&
            widget.relayScanRequestId > _lastHandledRelayScanRequestId);
    if (!shouldAutoOpen || hasSynced) {
      return;
    }
    _didAutoOpenRelayScan = true;
    _lastHandledRelayScanRequestId = widget.relayScanRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || hasSynced) return;
      unawaited(_openRelayScanFlow());
    });
  }

  @override
  void didUpdateWidget(covariant ServerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relayScanRequestId != widget.relayScanRequestId ||
        (!oldWidget.openRelayScanOnLoad && widget.openRelayScanOnLoad)) {
      _maybeAutoOpenRelayScan();
    }
  }

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServerAddr = prefs.getString(PrefKeys.serverAddr);
    final synced = savedServerAddr != null && savedServerAddr.isNotEmpty;
    final cameraNames = synced ? await _fetchCameraNames() : const <String>[];
    if (!mounted) return;
    setState(() {
      serverAddr = savedServerAddr;
      hasSynced = synced;
      _cameraNames = cameraNames;
      _ipController.text = serverAddr ?? '';
    });
    _maybeAutoOpenRelayScan();
  }

  Future<List<String>> _fetchCameraNames() async {
    try {
      if (!AppStores.isInitialized) {
        await AppStores.init();
      }
      final box = AppStores.instance.cameraStore.box<Camera>();
      final cameras = await box.getAllAsync();
      return cameras.map((camera) => camera.name).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Uri? _validatedRelayUri(String rawValue) {
    final parsed = Uri.tryParse(rawValue.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      return null;
    }
    return parsed;
  }

  Future<void> _saveServerSettings(
    UserCredentialsQrPayload credentialsFull,
  ) async {
    try {
      // TODO: Check how this handles on failure... bad QR code
      if (credentialsFull.serverUsername.length != Constants.usernameLength ||
          credentialsFull.serverPassword.length != Constants.passwordLength) {
        Log.e(
          "Server Page Save: User credentials should be more than 28 characters.",
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error processing QR code. Please try again"),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      var newServerAddr = credentialsFull.serverAddress;
      var serverUsername = credentialsFull.serverUsername;
      var serverPassword = credentialsFull.serverPassword;

      final validatedRelayUri = _validatedRelayUri(newServerAddr);
      if (validatedRelayUri == null) {
        Log.w(
          'Server QR scan rejected: invalid relay URL extracted from payload: $newServerAddr',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'That QR code is not a valid relay QR code.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }
      final normalizedServerAddr = validatedRelayUri.toString();

      //TODO: check to make sure serverIp is a valid IP address.

      final prefs = await SharedPreferences.getInstance();
      final prevServerAddr = prefs.getString(PrefKeys.serverAddr);
      final prevHasSynced = prevServerAddr != null && prevServerAddr.isNotEmpty;

      FcmConfig? fetchedFcmConfig;
      if (Platform.isAndroid) {
        final fetched = await HttpClientService.instance
            .fetchFcmConfigWithCredentials(
              serverAddr: normalizedServerAddr,
              username: serverUsername,
              password: serverPassword,
            );
        if (fetched.isFailure || fetched.value == null) {
          setState(() {
            serverAddr = prevServerAddr;
            hasSynced = prevHasSynced;
            _ipController.text = prevServerAddr ?? '';
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                "Failed to fetch FCM config. Server settings not saved.",
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
          return;
        }

        fetchedFcmConfig = fetched.value;
      }
      await prefs.setString(PrefKeys.serverAddr, normalizedServerAddr);
      await prefs.setString(PrefKeys.serverUsername, serverUsername);
      await prefs.setString(PrefKeys.serverPassword, serverPassword);
      await prefs.setBool(PrefKeys.needUpdateFcmToken, true);
      await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, true);
      await prefs.remove(PrefKeys.needUploadIosNotificationTarget);
      await prefs.remove(PrefKeys.iosRelayHubToken);
      await prefs.remove(PrefKeys.iosRelayHubTokenExpiryMs);
      await prefs.remove(PrefKeys.iosRelayBindingJson);
      HttpClientService.instance.resetVersionGateState();

      if (Platform.isAndroid) {
        await prefs.setString(
          PrefKeys.fcmConfigJson,
          jsonEncode(fetchedFcmConfig!.toJson()),
        );
      } else {
        await prefs.remove(PrefKeys.fcmConfigJson);
      }

      setState(() {
        serverAddr = normalizedServerAddr;
        hasSynced = true;
        _cameraNames = const [];
      });
      CameraUiBridge.refreshCameraListCallback?.call();

      //initialize all cameras again
      final box = AppStores.instance.cameraStore.box<Camera>();

      final allCameras = await box.getAllAsync();
      for (var camera in allCameras) {
        // TODO: Check if false, perhaps there's some weird error we might need to look into...
        await initialize(camera.name);
      }

      if (Platform.isAndroid) {
        bool firebaseReady = false;
        try {
          await FirebaseInit.ensure(fetchedFcmConfig!);
          firebaseReady = true;
        } catch (e, st) {
          Log.e("Firebase init failed: $e\n$st");
        }

        if (firebaseReady) {
          await PushNotificationService.instance.init();
          Log.d("Before try upload");
          await PushNotificationService.tryUploadIfNeeded(true);
          Log.d("After try upload");
        } else {
          Log.d("Skipping push setup; Firebase not initialized");
        }
      } else {
        await PushNotificationService.instance.init();
        await PushNotificationService.tryUploadIfNeeded(true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Server settings saved!")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Potentially invalid QR code. Please try again",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _removeServerConnection() async {
    final currentCameraNames =
        _isPreviewMode ? _cameraNames : await _fetchCameraNames();
    if (currentCameraNames.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove all cameras before removing the relay.'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.serverAddr);
    await prefs.remove(PrefKeys.serverUsername);
    await prefs.remove(PrefKeys.serverPassword);
    await prefs.remove(PrefKeys.fcmConfigJson);
    await prefs.remove(PrefKeys.needUpdateFcmToken);
    await prefs.remove(PrefKeys.needUpdateIosRelayBinding);
    await prefs.remove(PrefKeys.needUploadIosNotificationTarget);
    await prefs.remove(PrefKeys.iosApnsToken);
    await prefs.remove(PrefKeys.iosRelayHubToken);
    await prefs.remove(PrefKeys.iosRelayHubTokenExpiryMs);
    await prefs.remove(PrefKeys.iosRelayBindingJson);
    HttpClientService.instance.resetVersionGateState();
    _isDialogOpen.value = false;
    setState(() {
      serverAddr = null;
      hasSynced = false;
      _cameraNames = const [];
      _ipController.clear();
    });
    CameraUiBridge.refreshCameraListCallback?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Relay removed.")));
  }

  Future<void> _openAddCameraFlow() async {
    await GenericCameraQrScanPage.show(context);
    if (_isPreviewMode) return;
    final cameraNames = await _fetchCameraNames();
    if (!mounted) return;
    setState(() => _cameraNames = cameraNames);
  }

  Future<void> _openCameraDetails(String cameraName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CameraViewPage(cameraName: cameraName)),
    );
    if (_isPreviewMode) return;
    final cameraNames = await _fetchCameraNames();
    if (!mounted) return;
    setState(() => _cameraNames = cameraNames);
  }

  Future<void> _checkForUpdates() async {
    final serverVersionResult =
        await HttpClientService.instance.fetchServerVersion();
    if (!mounted) return;
    if (serverVersionResult.isFailure || serverVersionResult.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to check relay version right now.'),
        ),
      );
      return;
    }

    final serverVersion = serverVersionResult.value!;
    final clientVersion = await rustLibVersion();
    if (!mounted) return;

    final message =
        serverVersion == clientVersion
            ? 'Relay and app are up to date ($serverVersion).'
            : 'Relay version $serverVersion differs from app version $clientVersion.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPlaceholderMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRelayScanFlow() async {
    final credentialsFull = await Navigator.push<UserCredentialsQrPayload?>(
      context,
      MaterialPageRoute(builder: (_) => const _RelayQrScanPage()),
    );
    if (credentialsFull == null || !mounted) return;
    await _saveServerSettings(credentialsFull);
  }

  Widget _linkedRelayCard(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final endpoint = serverAddr ?? 'relay.local:8443';
    return ShellCard(
      radius: 28,
      color: dark ? const Color(0xFF0D1410) : const Color(0xFFF8FFFB),
      borderColor: dark ? const Color(0xFF0E5A41) : const Color(0xFFBCE4D1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF1ECF89).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF1ECF89),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relay Connected',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color:
                            dark
                                ? const Color(0xFF37D695)
                                : const Color(0xFF118E5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone linked · System ready',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.56,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color:
                  theme.brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: [
                _systemMetaRow(theme, 'Endpoint', endpoint),
                const SizedBox(height: 12),
                _systemMetaRow(theme, 'Protocol', 'MLS v1.0 (RFC 9420)'),
                const SizedBox(height: 12),
                _systemMetaRow(theme, 'Last Sync', 'Just now'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SystemActionButton(
                  label: 'Remove Relay',
                  onTap: _removeServerConnection,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SystemActionButton(
                  label: 'Check for Updates',
                  onTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairingCard(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShellCard(
          radius: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set up your relay server',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The relay is the encrypted bridge between your cameras and this app.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              _setupOptionCard(
                theme,
                title: 'Secluso Relay',
                subtitle: 'Scan the QR code from your Secluso account',
                icon: Icons.qr_code_2_rounded,
                highlighted: true,
                onTap: _openRelayScanFlow,
              ),
              const SizedBox(height: 14),
              _setupOptionCard(
                theme,
                title: 'Self-Hosted',
                subtitle: 'Run on your own server (DigitalOcean, Pi, NAS)',
                icon: Icons.terminal_rounded,
                highlighted: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ShellCard(
          radius: 18,
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white.withValues(alpha: 0.68),
          borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.26),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pairing credentials stay on this device. Nothing is sent to any server.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.32),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ShellCard(
          radius: 22,
          color: dark ? const Color(0xFF0F1714) : const Color(0xFFF2FCF8),
          borderColor: dark ? const Color(0xFF174E39) : const Color(0xFFBFE7D7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline_rounded, color: Color(0xFF1ECF89)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End-to-end encryption is always on',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color:
                            dark
                                ? const Color(0xFF28D08B)
                                : const Color(0xFF118E5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All credentials and encryption keys stay on this device. Secluso cannot access your footage.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.56,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final shellBackgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    if (widget.showShellChrome && !hasSynced) {
      return ShellScaffold(
        backgroundColor: shellBackgroundColor,
        safeTop: true,
        body:
            dark
                ? SystemShellUnpairedPage(
                  onUseSeclusoRelay: _openRelayScanFlow,
                  onUseSelfHosted:
                      () => _showPlaceholderMessage(
                        'Self-hosted relay setup is not wired in this preview yet.',
                      ),
                  onContactSupport:
                      () => _showPlaceholderMessage(
                        'Support links are not wired in this preview yet.',
                      ),
                  onVisitWebsite:
                      () => _showPlaceholderMessage(
                        'Website links are not wired in this preview yet.',
                      ),
                )
                : SystemShellUnpairedLightPage(
                  onUseSeclusoRelay: _openRelayScanFlow,
                  onUseSelfHosted:
                      () => _showPlaceholderMessage(
                        'Self-hosted relay setup is not wired in this preview yet.',
                      ),
                  onContactSupport:
                      () => _showPlaceholderMessage(
                        'Support links are not wired in this preview yet.',
                      ),
                  onVisitWebsite:
                      () => _showPlaceholderMessage(
                        'Website links are not wired in this preview yet.',
                      ),
                ),
      );
    }
    if (widget.showShellChrome && hasSynced) {
      if (!dark) {
        return ShellScaffold(
          backgroundColor: shellBackgroundColor,
          safeTop: true,
          body: SystemShellNoCamerasLightPage(
            endpoint: serverAddr ?? 'relay.local:8443',
            cameraNames: _cameraNames,
            onRestartRelay: _removeServerConnection,
            onCheckForUpdates: _checkForUpdates,
            onAddCamera: _openAddCameraFlow,
            onOpenCamera: _openCameraDetails,
            onContactSupport:
                () => _showPlaceholderMessage(
                  'Support links are not wired in this preview yet.',
                ),
            onVisitWebsite:
                () => _showPlaceholderMessage(
                  'Website links are not wired in this preview yet.',
                ),
          ),
        );
      }
      return ShellScaffold(
        backgroundColor: shellBackgroundColor,
        safeTop: true,
        body: SystemShellNoCamerasPage(
          endpoint: serverAddr ?? 'relay.local:8443',
          cameraNames: _cameraNames,
          onRestartRelay: _removeServerConnection,
          onCheckForUpdates: _checkForUpdates,
          onAddCamera: _openAddCameraFlow,
          onOpenCamera: _openCameraDetails,
          onContactSupport:
              () => _showPlaceholderMessage(
                'Support links are not wired in this preview yet.',
              ),
          onVisitWebsite:
              () => _showPlaceholderMessage(
                'Website links are not wired in this preview yet.',
              ),
        ),
      );
    }
    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        28,
        widget.showShellChrome ? 24 : 18,
        28,
        widget.showShellChrome ? 20 : 32,
      ),
      children: [
        Text(
          'System',
          style:
              widget.showShellChrome
                  ? shellTitleStyle(
                    context,
                    fontSize: 22,
                    designLetterSpacing: 0.55,
                  )
                  : theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        const SizedBox(height: 8),
        Text(
          hasSynced
              ? 'Your private relay and connected devices.'
              : 'Your private relay, ready when you are.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
            fontSize: widget.showShellChrome ? 11 : null,
            height: widget.showShellChrome ? 1.5 : null,
          ),
        ),
        const SizedBox(height: 18),
        if (hasSynced) ...[
          _linkedRelayCard(theme),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: ShellSectionLabel('Cameras')),
              TextButton(
                onPressed: _openAddCameraFlow,
                child: const Text('+ Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cameraNames.isEmpty)
            ShellCard(
              child: Column(
                children: [
                  Text(
                    'No cameras connected yet.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openAddCameraFlow,
                    child: const Text('Add your first camera'),
                  ),
                ],
              ),
            )
          else
            ShellCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _cameraNames.length; i++) ...[
                    _SystemCameraRow(name: _cameraNames[i]),
                    if (i != _cameraNames.length - 1) _divider(theme),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 18),
          ShellCard(
            radius: 24,
            color:
                theme.brightness == Brightness.dark
                    ? const Color(0xFF0F1714)
                    : const Color(0xFFF7FFFB),
            borderColor:
                theme.brightness == Brightness.dark
                    ? const Color(0xFF174E39)
                    : const Color(0xFFC7E8D8),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF1ECF89),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'End-to-end encryption is always on',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color:
                          theme.brightness == Brightness.dark
                              ? const Color(0xFF28D08B)
                              : const Color(0xFF118E5E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          _pairingCard(theme),
      ],
    );

    if (widget.showShellChrome) {
      return ShellScaffold(
        body: content,
        backgroundColor: shellBackgroundColor,
        safeTop: true,
      );
    }

    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: '',
        leading:
            widget.showBackButton
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
                : Builder(
                  builder:
                      (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => scaffoldKey.currentState?.openDrawer(),
                      ),
                ),
      ),
      body: SafeArea(top: true, child: content),
    );
  }
}

class _RelayQrScanPage extends StatefulWidget {
  const _RelayQrScanPage();

  @override
  State<_RelayQrScanPage> createState() => _RelayQrScanPageState();
}

class _RelayQrScanPageState extends State<_RelayQrScanPage> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _handlingScan = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_handlingScan) return;

    for (final barcode in capture.barcodes) {
      var rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(rawValue);
      } catch (_) {
        decoded = null;
      }

      var credentials = null;

      if (decoded is Map) {
        final versionKey = decoded['v'];
        final serverUsername = decoded['u'];
        final serverPassword = decoded['p'];
        final serverAddress = decoded['sa'];
        if (versionKey is String &&
            serverUsername is String &&
            serverPassword is String &&
            serverAddress is String &&
            versionKey == Constants.userCredentialsQrCodeVersion) {
          credentials = UserCredentialsQrPayload(
            serverUsername: serverUsername,
            serverPassword: serverPassword,
            serverAddress: serverAddress,
          );
          try {} catch (_) {}
        }
      }

      if (credentials == null) {
        continue;
      }

      _handlingScan = true;
      await _cameraController.stop();
      if (!mounted) return;
      Navigator.of(context).pop(credentials);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SeclusoQrScanScreen(
      title: 'Scan Relay QR',
      belowFrameText: "Point at your relay's QR\ncode",
      bottomMessage:
          'Relay credentials are stored only on this phone and used only to connect to your relay.',
      background: MobileScanner(
        controller: _cameraController,
        onDetect: _handleDetection,
      ),
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}

Widget _divider(ThemeData theme) =>
    Divider(height: 1, color: theme.colorScheme.outlineVariant);

class _SystemActionButton extends StatelessWidget {
  const _SystemActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor:
              dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.82),
          foregroundColor:
              dark
                  ? Colors.white.withValues(alpha: 0.84)
                  : const Color(0xFF3E4352),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color:
                dark
                    ? Colors.white.withValues(alpha: 0.84)
                    : const Color(0xFF3E4352),
          ),
        ),
      ),
    );
  }
}

Widget _systemMetaRow(ThemeData theme, String label, String value) {
  return Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SystemCameraRow extends StatelessWidget {
  const _SystemCameraRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const ShellStatusDot(Color(0xFF1ECF89)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ),
            Text(
              'Online',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _setupOptionCard(
  ThemeData theme, {
  required String title,
  required String subtitle,
  required IconData icon,
  required bool highlighted,
  required VoidCallback onTap,
}) {
  final dark = theme.brightness == Brightness.dark;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color:
              highlighted
                  ? (dark ? const Color(0xFF1B2433) : const Color(0xFFF2ECD7))
                  : (dark
                      ? Colors.white.withValues(alpha: 0.03)
                      : const Color(0xFFF5F6FA)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                highlighted
                    ? (dark ? const Color(0xFF445C8C) : const Color(0xFFE3C15B))
                    : theme.colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                    dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color:
                    highlighted
                        ? const Color(0xFF8BB1F4)
                        : const Color(0xFFB0BCD4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.58,
                      ),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
