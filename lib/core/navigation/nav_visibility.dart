// lib/core/navigation/nav_visibility.dart
//
// Shared state for the tablet / desktop navigation list.

import 'package:flutter_riverpod/legacy.dart';

/// True while the docked tablet/desktop rail is hidden (all pages except POS).
final bosNavHiddenProvider = StateProvider<bool>((ref) => false);

/// True while the slide-over navigation drawer is open on the POS page.
/// On POS the rail never takes layout space; the menu button opens this
/// drawer on top of the POS and the POS stays exactly where it is.
final bosNavDrawerOpenProvider = StateProvider<bool>((ref) => false);

/// From this screen width the POS shows catalog + order side by side, the
/// order panel is always open, and navigation becomes a slide-over drawer.
const double kPosSplitBreakpoint = 720;
