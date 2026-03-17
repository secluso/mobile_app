//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/routes/theme_provider.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_shell_ui.dart';
import 'package:secluso_flutter/utilities/logger.dart';

enum SettingsPreviewScrollPosition { top, bottom, veryBottom }

class SettingsPage extends StatefulWidget {
  final bool? previewNightTheme;
  final bool? previewNotificationsOn;
  final bool showShellChrome;
  final SettingsPreviewScrollPosition? previewScrollPosition;

  const SettingsPage({
    super.key,
    this.previewNightTheme,
    this.previewNotificationsOn,
    this.showShellChrome = false,
    this.previewScrollPosition,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();

  bool isNightTheme = false;
  bool isNotificationsOn = true;
  bool biometricLock = false;
  bool personAlerts = true;
  bool motionAlerts = true;
  bool showErrorNotifications = true;

  bool get _isPreviewMode => widget.previewNightTheme != null;

  @override
  void initState() {
    super.initState();
    if (_isPreviewMode) {
      isNightTheme = widget.previewNightTheme!;
      isNotificationsOn = widget.previewNotificationsOn ?? true;
      personAlerts = widget.previewNotificationsOn ?? true;
      motionAlerts = widget.previewNotificationsOn ?? true;
      showErrorNotifications = true;
      return;
    }
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.previewScrollPosition == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      double target = 0;
      switch (widget.previewScrollPosition!) {
        case SettingsPreviewScrollPosition.top:
          target = 0;
        case SettingsPreviewScrollPosition.bottom:
          target = max * 0.62;
        case SettingsPreviewScrollPosition.veryBottom:
          target = max;
      }
      _scrollController.jumpTo(target.clamp(0, max));
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled =
        prefs.getBool(PrefKeys.notificationsEnabled) ??
        prefs.getBool('notifications') ??
        true;
    setState(() {
      isNightTheme = prefs.getBool('darkTheme') ?? true;
      isNotificationsOn = notificationsEnabled;
      personAlerts = prefs.getBool('personAlerts') ?? true;
      motionAlerts = prefs.getBool('motionAlerts') ?? true;
      biometricLock = prefs.getBool('biometricLock') ?? false;
      showErrorNotifications = prefs.getBool('showErrorNotifications') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    if (_isPreviewMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkTheme', isNightTheme);
    await prefs.setBool(PrefKeys.notificationsEnabled, isNotificationsOn);
    await prefs.remove('notifications');
    await prefs.setBool('personAlerts', personAlerts);
    await prefs.setBool('motionAlerts', motionAlerts);
    await prefs.setBool('biometricLock', biometricLock);
    await prefs.setBool('showErrorNotifications', showErrorNotifications);
  }

  Future<void> _copyLogs() async {
    final logs = await Log.getLogDump();
    final exportText =
        logs.trim().isEmpty ? 'No logs available yet.' : logs;
    await Clipboard.setData(ClipboardData(text: exportText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          logs.trim().isEmpty ? 'No logs available yet. Placeholder copied.' : 'Logs copied to clipboard.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final shell = widget.showShellChrome;
    final shellMetrics = _ShellSettingsMetrics.forWidth(
      MediaQuery.sizeOf(context).width,
    );
    final displayNightTheme = shell && _isPreviewMode ? dark : isNightTheme;
    final shellPrimaryTextColor = dark ? Colors.white : const Color(0xFF111827);
    final shellSecondaryTextColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final shellSectionTextColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final shellChevronColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final shellSurfaceColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final shellSurfaceBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final shellDividerColor =
        dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE5E7EB);
    const shellToggleActiveColor = Color(0xFF8BB3EE);
    const shellToggleInactiveColor = Color(0xFFD1D5DB);
    final shellToggleThumbShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
    final sectionTitleStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellSectionTextColor,
              fontSize: shellMetrics.sectionTitleSize,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.normal,
              letterSpacing: shellMetrics.sectionTitleLetterSpacing,
              height: 13.5 / 9,
            );
    final shellRowTitleStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellPrimaryTextColor,
              fontSize: shellMetrics.rowTitleSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              letterSpacing: 0,
              height: 19.5 / 13,
            );
    final shellRowValueStyle =
        !shell
            ? null
            : GoogleFonts.inter(
              color: shellSecondaryTextColor,
              fontSize: shellMetrics.rowValueSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              letterSpacing: 0,
              height: 16.5 / 11,
            );
    final shellCardShadow =
        !shell
            ? null
            : dark
            ? const <BoxShadow>[]
            : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ];

    final content = ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        shell ? shellMetrics.pageInset : 28,
        shell ? shellMetrics.topPadding : 18,
        shell ? shellMetrics.pageInset : 28,
        shell ? shellMetrics.bottomPadding : 28,
      ),
      children: [
        Text(
          'Settings',
          style:
              shell
                  ? GoogleFonts.inter(
                    color: shellPrimaryTextColor,
                    fontSize: shellMetrics.titleSize,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.normal,
                    letterSpacing: -shellMetrics.titleLetterSpacing,
                    height: 33 / 22,
                  )
                  : theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        SizedBox(height: shell ? shellMetrics.subtitleGap : 8),
        Text(
          'App preferences for this device.',
          style:
              shell
                  ? GoogleFonts.inter(
                    color: shellSecondaryTextColor,
                    fontSize: shellMetrics.subtitleSize,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    height: 16.5 / 11,
                  )
                  : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
                  ),
        ),
        SizedBox(height: shell ? shellMetrics.headerBottomGap : 26),
        ShellSettingsGroup(
          title: 'Security',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Biometric Lock',
              trailing: ShellToggle(
                value: biometricLock,
                onChanged: (value) {
                  setState(() => biometricLock = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Auto-Lock Timeout',
              value: 'Immediately',
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: shell ? shellSecondaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle: shellRowValueStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Appearance',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Dark Mode',
              trailing: ShellToggle(
                value: displayNightTheme,
                onChanged: (value) {
                  setState(() => isNightTheme = value);
                  if (!_isPreviewMode) {
                    Provider.of<ThemeProvider>(
                      context,
                      listen: false,
                    ).setTheme(value);
                  }
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'App Icon',
              value: 'Default',
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: shell ? shellSecondaryTextColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle: shellRowValueStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Notifications',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Push Notifications',
              trailing: ShellToggle(
                value: isNotificationsOn,
                onChanged: (value) {
                  setState(() => isNotificationsOn = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Person Alerts',
              trailing: ShellToggle(
                value: personAlerts,
                onChanged: (value) {
                  setState(() => personAlerts = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Motion Alerts',
              trailing: ShellToggle(
                value: motionAlerts,
                onChanged: (value) {
                  setState(() => motionAlerts = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'System Alerts',
              trailing: ShellToggle(
                value: showErrorNotifications,
                onChanged: (value) {
                  setState(() => showErrorNotifications = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        if (!shell)
          ShellSectionLabel('Storage')
        else
          Text('STORAGE', style: sectionTitleStyle),
        SizedBox(height: shell ? shellMetrics.sectionTitleGap : 12),
        ShellCard(
          padding: EdgeInsets.zero,
          radius: shell ? shellMetrics.groupRadius : 22,
          color: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          boxShadow: shell ? shellCardShadow : null,
          child: Column(
            children: [
              Padding(
                padding:
                    shell
                        ? EdgeInsets.fromLTRB(
                          shellMetrics.storageInset,
                          shellMetrics.storageInset,
                          shellMetrics.storageInset,
                          shellMetrics.storageBottomInset,
                        )
                        : const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local Storage',
                      style:
                          shell
                              ? shellRowTitleStyle
                              : theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                    ),
                    SizedBox(
                      height: shell ? shellMetrics.storageBarTopGap : 14,
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: shell ? shellMetrics.storageBarHeight : 8,
                        value: 2.4 / 32,
                        backgroundColor:
                            dark
                                ? Colors.white.withValues(alpha: 0.1)
                                : const Color(0xFFE4E6EE),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF8BB3EE),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: shell ? shellMetrics.storageTextTopGap : 10,
                    ),
                    Text(
                      '2.4 GB used of 32 GB',
                      style:
                          shell
                              ? GoogleFonts.inter(
                                color: shellSecondaryTextColor,
                                fontSize: shellMetrics.storageInfoSize,
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.normal,
                                letterSpacing: 0,
                                height: 15 / 10,
                              )
                              : theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color:
                    shell
                        ? shellDividerColor
                        : theme.colorScheme.outlineVariant,
              ),
              ShellSettingsRow(
                title: 'Manage Storage',
                height: shell ? shellMetrics.manageRowHeight : 56,
                horizontalPadding:
                    shell ? shellMetrics.rowHorizontalPadding : 18,
                titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
                valueFontSize: shell ? shellMetrics.rowValueSize : 16,
                titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
                valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
                chevronSize: shell ? shellMetrics.chevronSize : 24,
                valueChevronGap: shell ? 8 : 10,
                titleColor: shell ? shellPrimaryTextColor : null,
                chevronColor: shell ? shellChevronColor : null,
                titleStyle: shellRowTitleStyle,
              ),
            ],
          ),
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'Diagnostics',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Show Error Notifications',
              trailing: ShellToggle(
                value: showErrorNotifications,
                onChanged: (value) {
                  setState(() => showErrorNotifications = value);
                  _saveSettings();
                },
                width: shell ? shellMetrics.toggleWidth : 50,
                height: shell ? shellMetrics.toggleHeight : 30,
                padding: shell ? shellMetrics.togglePadding : 3,
                thumbSize: shell ? shellMetrics.toggleThumbSize : 24,
                activeColor: shell ? shellToggleActiveColor : null,
                inactiveColor: shell ? shellToggleInactiveColor : null,
                thumbShadow: shell ? shellToggleThumbShadow : null,
              ),
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              titleColor: shell ? shellPrimaryTextColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Export Logs',
              onTap: _copyLogs,
              height: shell ? shellMetrics.rowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellSettingsGroup(
          title: 'About',
          titleStyle: sectionTitleStyle,
          titleGap: shell ? shellMetrics.sectionTitleGap : 12,
          radius: shell ? shellMetrics.groupRadius : 22,
          cardColor: shell ? shellSurfaceColor : null,
          borderColor: shell ? shellSurfaceBorderColor : null,
          dividerColor: shell ? shellDividerColor : null,
          boxShadow: shell ? shellCardShadow : null,
          children: [
            ShellSettingsRow(
              title: 'Version',
              value: '1.0.0 (24)',
              height: shell ? shellMetrics.aboutVersionRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              valueColor: shell ? shellSecondaryTextColor : null,
              titleStyle: shellRowTitleStyle,
              valueStyle: shellRowValueStyle,
            ),
            ShellSettingsRow(
              title: 'Terms of Service',
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Privacy Policy',
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
            ShellSettingsRow(
              title: 'Open Source Licenses',
              onTap: () => showLicensePage(context: context),
              height: shell ? shellMetrics.aboutLinkRowHeight : 56,
              horizontalPadding: shell ? shellMetrics.rowHorizontalPadding : 18,
              titleFontSize: shell ? shellMetrics.rowTitleSize : 16,
              valueFontSize: shell ? shellMetrics.rowValueSize : 16,
              titleWeight: shell ? FontWeight.w400 : FontWeight.w500,
              valueWeight: shell ? FontWeight.w400 : FontWeight.w500,
              chevronSize: shell ? shellMetrics.chevronSize : 24,
              valueChevronGap: shell ? 8 : 10,
              titleColor: shell ? shellPrimaryTextColor : null,
              chevronColor: shell ? shellChevronColor : null,
              titleStyle: shellRowTitleStyle,
            ),
          ],
        ),
        SizedBox(height: shell ? shellMetrics.sectionGap : 22),
        ShellCard(
          radius: shell ? shellMetrics.infoRadius : 22,
          color:
              shell
                  ? (dark
                      ? Colors.white.withValues(alpha: 0.02)
                      : const Color(0xFFF9FAFB))
                  : (dark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.white.withValues(alpha: 0.7)),
          borderColor:
              shell
                  ? (dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFE5E7EB))
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          boxShadow: shell ? const [] : null,
          padding:
              shell
                  ? EdgeInsets.fromLTRB(
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                    shellMetrics.infoInset,
                  )
                  : const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsFooterLockIcon(
                size: shell ? shellMetrics.infoIconSize : 18,
                color:
                    shell
                        ? (dark
                            ? Colors.white.withValues(alpha: 0.35)
                            : const Color(0xFF9CA3AF))
                        : theme.colorScheme.onSurface.withValues(alpha: 0.28),
              ),
              SizedBox(width: shell ? shellMetrics.infoGap : 12),
              Expanded(
                child: Text(
                  'These settings apply only to this phone. They do not affect how footage is encrypted, stored, or transmitted by your cameras.',
                  style:
                      shell
                          ? GoogleFonts.inter(
                            color: shellSecondaryTextColor,
                            fontSize: shellMetrics.infoTextSize,
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.normal,
                            letterSpacing: 0,
                            height: 16.25 / 10,
                          )
                          : theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.44,
                            ),
                            height: 1.5,
                          ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.showShellChrome) {
      final backgroundColor =
          dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
      return ShellScaffold(
        backgroundColor: backgroundColor,
        body: ColoredBox(color: backgroundColor, child: content),
        safeTop: true,
      );
    }

    return SeclusoScaffold(
      appBar: seclusoAppBar(
        context,
        title: 'Settings',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(top: true, child: content),
    );
  }
}

class _SettingsFooterLockIcon extends StatelessWidget {
  const _SettingsFooterLockIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SettingsFooterLockPainter(color)),
    );
  }
}

class _ShellSettingsMetrics {
  const _ShellSettingsMetrics({
    required this.pageInset,
    required this.topPadding,
    required this.bottomPadding,
    required this.titleSize,
    required this.titleLetterSpacing,
    required this.subtitleGap,
    required this.subtitleSize,
    required this.headerBottomGap,
    required this.sectionGap,
    required this.sectionTitleGap,
    required this.sectionTitleSize,
    required this.sectionTitleLetterSpacing,
    required this.groupRadius,
    required this.rowHeight,
    required this.rowHorizontalPadding,
    required this.rowTitleSize,
    required this.rowValueSize,
    required this.chevronSize,
    required this.toggleWidth,
    required this.toggleHeight,
    required this.togglePadding,
    required this.toggleThumbSize,
    required this.storageInset,
    required this.storageBottomInset,
    required this.storageBarTopGap,
    required this.storageBarHeight,
    required this.storageTextTopGap,
    required this.storageInfoSize,
    required this.manageRowHeight,
    required this.aboutVersionRowHeight,
    required this.aboutLinkRowHeight,
    required this.infoRadius,
    required this.infoInset,
    required this.infoIconSize,
    required this.infoGap,
    required this.infoTextSize,
  });

  final double pageInset;
  final double topPadding;
  final double bottomPadding;
  final double titleSize;
  final double titleLetterSpacing;
  final double subtitleGap;
  final double subtitleSize;
  final double headerBottomGap;
  final double sectionGap;
  final double sectionTitleGap;
  final double sectionTitleSize;
  final double sectionTitleLetterSpacing;
  final double groupRadius;
  final double rowHeight;
  final double rowHorizontalPadding;
  final double rowTitleSize;
  final double rowValueSize;
  final double chevronSize;
  final double toggleWidth;
  final double toggleHeight;
  final double togglePadding;
  final double toggleThumbSize;
  final double storageInset;
  final double storageBottomInset;
  final double storageBarTopGap;
  final double storageBarHeight;
  final double storageTextTopGap;
  final double storageInfoSize;
  final double manageRowHeight;
  final double aboutVersionRowHeight;
  final double aboutLinkRowHeight;
  final double infoRadius;
  final double infoInset;
  final double infoIconSize;
  final double infoGap;
  final double infoTextSize;

  factory _ShellSettingsMetrics.forWidth(double width) {
    final scale = (width / 290).clamp(0.88, 1.6);
    double s(double value) => value * scale;
    return _ShellSettingsMetrics(
      pageInset: s(20),
      topPadding: s(20),
      bottomPadding: s(28),
      titleSize: s(22),
      titleLetterSpacing: 0.55,
      subtitleGap: s(4),
      subtitleSize: s(11),
      headerBottomGap: s(12),
      sectionGap: s(20),
      sectionTitleGap: s(8),
      sectionTitleSize: s(9),
      sectionTitleLetterSpacing: 0.9,
      groupRadius: s(12),
      rowHeight: s(50.75),
      rowHorizontalPadding: s(14),
      rowTitleSize: s(13),
      rowValueSize: s(11),
      chevronSize: s(14),
      toggleWidth: s(40),
      toggleHeight: s(24),
      togglePadding: s(2),
      toggleThumbSize: s(20),
      storageInset: s(14),
      storageBottomInset: s(12.5),
      storageBarTopGap: s(14),
      storageBarHeight: s(8),
      storageTextTopGap: s(10),
      storageInfoSize: s(10),
      manageRowHeight: s(49.5),
      aboutVersionRowHeight: s(48.5),
      aboutLinkRowHeight: s(48.5),
      infoRadius: s(12),
      infoInset: s(16),
      infoIconSize: s(14),
      infoGap: s(12),
      infoTextSize: s(10),
    );
  }
}

class _SettingsFooterLockPainter extends CustomPainter {
  const _SettingsFooterLockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (0.833333 / 10);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.25 / 10),
        size.height * (4.58333 / 10),
        size.width * (7.5 / 10),
        size.height * (4.58334 / 10),
      ),
      Radius.circular(size.width * (0.83333 / 10)),
    );
    canvas.drawRRect(body, stroke);

    final shackle =
        Path()
          ..moveTo(size.width * (2.91667 / 10), size.height * (4.58333 / 10))
          ..lineTo(size.width * (2.91667 / 10), size.height * (2.91667 / 10))
          ..arcToPoint(
            Offset(size.width * (7.08333 / 10), size.height * (2.91667 / 10)),
            radius: Radius.circular(size.width * (2.08333 / 10)),
            clockwise: true,
          )
          ..lineTo(size.width * (7.08333 / 10), size.height * (4.58333 / 10));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _SettingsFooterLockPainter oldDelegate) =>
      oldDelegate.color != color;
}
