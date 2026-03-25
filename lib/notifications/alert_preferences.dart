//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

class AlertDecision {
  const AlertDecision._({
    required this.shouldShow,
    this.label,
    this.shouldAlertOnce = false,
  });

  const AlertDecision.hide() : this._(shouldShow: false);

  const AlertDecision.show(String label, {bool shouldAlertOnce = false})
    : this._(shouldShow: true, label: label, shouldAlertOnce: shouldAlertOnce);

  final bool shouldShow;
  final String? label;
  final bool shouldAlertOnce;
}

bool _hasPersonDetection(Set<String> detections) {
  return detections.contains('human') || detections.contains('person');
}

bool _hasVehicleDetection(Set<String> detections) {
  return detections.contains('vehicle') || detections.contains('car');
}

bool _hasPetDetection(Set<String> detections) {
  return detections.contains('pet') || detections.contains('pets');
}

Set<String> normalizeDetections(Iterable<String> detections) {
  final normalized = <String>{};
  for (final detection in detections) {
    final value = detection.trim().toLowerCase();
    if (value.isEmpty) continue;
    if (value == 'person') {
      normalized.add('human');
      continue;
    }
    if (value == 'car') {
      normalized.add('vehicle');
      continue;
    }
    if (value == 'pets') {
      normalized.add('pet');
      continue;
    }
    normalized.add(value);
  }
  return normalized;
}

bool _globalNotificationsEnabled(SharedPreferences prefs) {
  return prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
}

bool _globalPersonAlertsEnabled(SharedPreferences prefs) {
  return prefs.getBool('personAlerts') ?? true;
}

bool _globalMotionAlertsEnabled(SharedPreferences prefs) {
  return prefs.getBool('motionAlerts') ?? true;
}

bool _cameraNotificationsEnabled(SharedPreferences prefs, String cameraName) {
  return prefs.getBool(
        PrefKeys.cameraNotificationsEnabledPrefix + cameraName,
      ) ??
      true;
}

List<String> cameraNotificationEvents(
  SharedPreferences prefs,
  String cameraName,
) {
  final values =
      prefs.getStringList(
        PrefKeys.cameraNotificationEventsPrefix + cameraName,
      ) ??
      const ['All'];
  if (values.isEmpty) {
    return const ['All'];
  }
  return values;
}

bool _cameraAllowsAny(List<String> values) => values.contains('All');

bool _cameraAllowsHumans(List<String> values) {
  return values.contains('All') || values.contains('Humans');
}

bool _cameraAllowsVehicles(List<String> values) {
  return values.contains('All') || values.contains('Vehicles');
}

bool _cameraAllowsPets(List<String> values) {
  return values.contains('All') || values.contains('Pets');
}

bool shouldShowProvisionalMotionAlert(
  SharedPreferences prefs,
  String cameraName,
) {
  if (!_globalNotificationsEnabled(prefs)) {
    return false;
  }
  if (!_cameraNotificationsEnabled(prefs, cameraName)) {
    return false;
  }
  if (!_globalMotionAlertsEnabled(prefs)) {
    return false;
  }
  final cameraEvents = cameraNotificationEvents(prefs, cameraName);
  return _cameraAllowsAny(cameraEvents);
}

AlertDecision evaluateMotionAlertPreferences(
  SharedPreferences prefs,
  String cameraName, {
  required bool motion,
  required Iterable<String> detections,
}) {
  if (!_globalNotificationsEnabled(prefs)) {
    return const AlertDecision.hide();
  }
  if (!_cameraNotificationsEnabled(prefs, cameraName)) {
    return const AlertDecision.hide();
  }

  final normalizedDetections = normalizeDetections(detections);
  final cameraEvents = cameraNotificationEvents(prefs, cameraName);
  final provisionalWouldShow = shouldShowProvisionalMotionAlert(
    prefs,
    cameraName,
  );

  if (_hasPersonDetection(normalizedDetections) &&
      _globalPersonAlertsEnabled(prefs) &&
      _cameraAllowsHumans(cameraEvents)) {
    return AlertDecision.show(
      'Person detected',
      shouldAlertOnce: provisionalWouldShow,
    );
  }

  if (_hasVehicleDetection(normalizedDetections) &&
      _globalMotionAlertsEnabled(prefs) &&
      _cameraAllowsVehicles(cameraEvents)) {
    return AlertDecision.show(
      'Vehicle detected',
      shouldAlertOnce: provisionalWouldShow,
    );
  }

  if (_hasPetDetection(normalizedDetections) &&
      _globalMotionAlertsEnabled(prefs) &&
      _cameraAllowsPets(cameraEvents)) {
    return AlertDecision.show(
      'Pet detected',
      shouldAlertOnce: provisionalWouldShow,
    );
  }

  if (motion &&
      _globalMotionAlertsEnabled(prefs) &&
      _cameraAllowsAny(cameraEvents)) {
    return AlertDecision.show('Motion', shouldAlertOnce: provisionalWouldShow);
  }

  return const AlertDecision.hide();
}
