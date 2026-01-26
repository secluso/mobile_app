//! SPDX-License-Identifier: GPL-3.0-or-later

/// Lightweight process-wide UI flags shared across isolates.
/// We only keep a single bit today so non-UI
/// workers can safely decide whether to use UI elements.
class UiState {
  static bool _bindingReady = false;

  static bool get isBindingReady => _bindingReady;

  static void markBindingReady() {
    _bindingReady = true;
  }
}
