// lib/features/startup/startup_screens.dart
//
// Every "in-between" screen of the app: loading, couldn't-start, device
// authorization, join-or-create, and no-access.
//
// These are PRESENTATIONAL widgets. All startup logic stays in main.dart; the
// existing private screens just build these with their state and callbacks
// (see startup_patch.md).
//
// Personality: the sign-in screen remembers who is signing in (Customer /
// Team / Owner). These screens read that same choice and quietly shift their
// colour, motif and wording to match. Nothing here changes how startup works.

import 'dart:async';
import 'dart:math' as math;

import 'package:bos_application/core/branding/branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// PERSONA (presentation only)
// ============================================================================

/// Same key and names the login screen writes.
const _personaPrefKey = 'login_persona';

enum StartupPersona {
  customer('Getting things ready…'),
  team('Getting your day ready…'),
  owner('Preparing your business…');

  const StartupPersona(this.status);

  final String status;
  /// Customers shouldn't see the internal "Business Operating System" name.
bool get showsFullName => this != StartupPersona.customer;

  (Color, Color) tones(ColorScheme scheme) {
    Color deep(Color c) => Color.lerp(c, Colors.black, 0.2)!;
    return switch (this) {
      StartupPersona.customer => (
        deep(scheme.tertiary),
        deep(
          Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.45),
            scheme.tertiary,
          ),
        ),
      ),
      StartupPersona.team => (
        deep(scheme.secondary),
        deep(
          Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.5),
            scheme.secondary,
          ),
        ),
      ),
      StartupPersona.owner => (
        deep(scheme.primary),
        deep(
          Color.alphaBlend(
            scheme.tertiary.withValues(alpha: 0.55),
            scheme.primary,
          ),
        ),
      ),
    };
  }
}

/// Last persona read from storage. Used only as the first-frame value so the
/// screen doesn't flash the owner colours before the real one loads.
StartupPersona? _cachedPersona;

Future<StartupPersona> _loadPersona() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_personaPrefKey);
    return _cachedPersona = StartupPersona.values.firstWhere(
      (p) => p.name == saved,
      orElse: () => StartupPersona.owner,
    );
  } catch (_) {
    return _cachedPersona ?? StartupPersona.owner;
  }
}

Future<void> preloadStartupPersona() => _loadPersona();

/// Call right after the login screen saves the persona, so the next startup
/// screen uses the right colours from its very first frame.
void setStartupPersona(String name) {
  _cachedPersona = StartupPersona.values.firstWhere(
    (p) => p.name == name,
    orElse: () => StartupPersona.owner,
  );
}

// ============================================================================
// BACKDROP — gradient + faint motif. Wrap any screen in this.
// ============================================================================

class StartupBackdrop extends StatefulWidget {
  const StartupBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<StartupBackdrop> createState() => _StartupBackdropState();
}

class _StartupBackdropState extends State<StartupBackdrop> {
  StartupPersona _persona = _cachedPersona ?? StartupPersona.owner;

  @override
  void initState() {
    super.initState();
    _loadPersona().then((p) {
      if (mounted && p != _persona) setState(() => _persona = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (a, b) = _persona.tones(scheme);

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: DecoratedBox(
            key: ValueKey(_persona),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [a, b],
              ),
            ),
            child: SizedBox.expand(
              child: CustomPaint(painter: _MotifPainter(_persona)),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Faint abstract shapes, one family per audience:
///   customer — soft circles   team — schedule blocks   owner — rising bars
class _MotifPainter extends CustomPainter {
  _MotifPainter(this.persona);

  final StartupPersona persona;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.07);
    final strong = Paint()..color = Colors.white.withValues(alpha: 0.13);
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (persona) {
      case StartupPersona.customer:
        final base = size.shortestSide;
        final c = Offset(size.width * 0.88, size.height * 0.16);
        canvas.drawCircle(c, base * 0.5, soft);
        canvas.drawCircle(c, base * 0.66, stroke);
        canvas.drawCircle(
          Offset(size.width * 0.05, size.height * 0.86),
          base * 0.42,
          soft,
        );
        canvas.drawCircle(
          Offset(size.width * 0.98, size.height * 0.78),
          base * 0.2,
          strong,
        );

      case StartupPersona.team:
        const cols = 7;
        const rows = 5;
        const gap = 8.0;
        final gridWidth = size.width * 0.7;
        final cell = (gridWidth - (cols - 1) * gap) / cols;
        final x0 = size.width - gridWidth - 10;
        final y0 = size.height * 0.04;
        for (var r = 0; r < rows; r++) {
          for (var col = 0; col < cols; col++) {
            final rect = RRect.fromRectAndRadius(
              Rect.fromLTWH(
                x0 + col * (cell + gap),
                y0 + r * (cell + gap),
                cell,
                cell,
              ),
              Radius.circular(cell * 0.28),
            );
            canvas.drawRRect(rect, (r * 3 + col * 2) % 5 == 0 ? strong : soft);
          }
        }

      case StartupPersona.owner:
        const bars = 8;
        const gap = 10.0;
        final areaWidth = size.width * 0.72;
        final barWidth = (areaWidth - (bars - 1) * gap) / bars;
        final baseY = size.height - 24;
        final maxHeight = size.height * 0.34;
        final x0 = size.width - areaWidth - 12;
        const heights = [0.26, 0.4, 0.34, 0.56, 0.48, 0.7, 0.84, 1.0];
        final line = Path();
        for (var i = 0; i < bars; i++) {
          final h = maxHeight * heights[i];
          final left = x0 + i * (barWidth + gap);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, baseY - h, barWidth, h),
              Radius.circular(math.min(8, barWidth / 2)),
            ),
            i == bars - 1 ? strong : soft,
          );
          final p = Offset(left + barWidth / 2, baseY - h - 14);
          i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(line, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MotifPainter old) => old.persona != persona;
}

// ============================================================================
// LOADING
// ============================================================================

/// Full-screen startup loading. Calm, branded, and honest: it shows one
/// status line, and only after a while explains that things are taking longer.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({super.key, this.message, this.onSignOut});

  /// Overrides the persona's default status line.
  final String? message;

  /// When given, a "Sign out" link appears once loading runs long, so
  /// nobody is ever stuck behind a spinner.
  final VoidCallback? onSignOut;

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();
  Timer? _slowTimer;
  bool _slow = false;
  StartupPersona _persona = _cachedPersona ?? StartupPersona.owner;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _slow = true);
    });
    _loadPersona().then((p) {
      if (mounted) setState(() => _persona = p);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final status = widget.message ?? _persona.status;

    Widget ring(double phase) => AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = reduceMotion ? 0.4 : (_pulse.value + phase) % 1.0;
        final size = 116 + 120 * t;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: (1 - t) * 0.32),
              width: 1.6,
            ),
          ),
        );
      },
    );

    return Scaffold(
      body: StartupBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ring(0),
                        ring(0.5),
                        Container(
                          width: 116,
                          height: 116,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: const AppLogo(height: 80),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.appName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
if (_persona.showsFullName) ...[
  const SizedBox(height: 4),
  Text(
    AppStrings.appFullName,
    textAlign: TextAlign.center,
    style: theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
    ),
  ),
],
                  const SizedBox(height: 36),
                  SizedBox(
                    width: 190,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: !_slow
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              children: [
                                Text(
                                  'Still working… first sign-ins and slow '
                                  'connections can take a little longer.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    height: 1.4,
                                  ),
                                ),
                                if (widget.onSignOut != null)
                                  TextButton(
                                    onPressed: widget.onSignOut,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Sign out instead'),
                                  ),
                              ],
                            ),
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
}

// ============================================================================
// PANEL — shared layout for every non-loading startup screen
// ============================================================================

/// A centred card on the persona backdrop with a tinted icon badge, a title,
/// an optional message and any content. Use it for any new startup screen.
class StartupPanel extends StatelessWidget {
  const StartupPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.message,
    this.tone,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Badge colour; defaults to the theme's primary.
  final Color? tone;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = tone ?? scheme.primary;

    return Scaffold(
      body: StartupBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const AppLogo(height: 32),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 36,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: 34, color: accent),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          ...children,
                        ],
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 14),
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                        child: footer!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _busySpinner(BuildContext context) => SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(
    strokeWidth: 2.2,
    color: Theme.of(context).colorScheme.onPrimary,
  ),
);

const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(16)),
);

// ============================================================================
// COULDN'T START
// ============================================================================

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
    this.onSignOut,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onSignOut;

  ({IconData icon, String title, String message}) _describe() {
    final text = '$error'.toLowerCase();
if (text.contains('reach the cloud') ||
    text.contains('socketexception') ||
    text.contains('timeoutexception') ||
    text.contains('failed host lookup')) {
      return (
        icon: Icons.wifi_off_rounded,
        title: 'Can’t reach ${AppStrings.appName} right now',
        message:
            'Check your internet connection and try again. If this device '
            'has never opened your business before, it needs to connect once.',
      );
    }
    if (text.contains('signed out')) {
      return (
        icon: Icons.lock_clock_outlined,
        title: 'You were signed out',
        message: 'Please sign in again to continue.',
      );
    }
    if (text.contains('sqlite') || text.contains('drift') || text.contains('database')) {
  return (
    icon: Icons.storage_rounded,
    title: '${AppStrings.appName} couldn’t open its data',
    message: 'The local database could not be prepared. Try again, or '
        'restart the app if this keeps happening.',
  );
}
    return (
      icon: Icons.warning_amber_rounded,
      title: '${AppStrings.appName} couldn’t start',
      message:
          'Something went wrong while opening your business. Try again, or '
          'restart the app if this keeps happening.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = _describe();

    return StartupPanel(
      icon: info.icon,
      tone: scheme.error,
      title: info.title,
      message: info.message,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: _buttonShape,
          ),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text(
            'Try again',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (onSignOut != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onSignOut, child: const Text('Sign out')),
        ],
        const SizedBox(height: 4),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Technical details',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '$error',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '$error'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text('Details copied.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy'),
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
}

// ============================================================================
// DEVICE AUTHORIZATION
// ============================================================================

class DeviceAuthorizationView extends StatelessWidget {
  const DeviceAuthorizationView({
    super.key,
    required this.message,
    required this.canReactivate,
    required this.working,
    required this.onReactivate,
    required this.onSignOut,
  });

  final String message;

  /// True when the device was revoked and may be reactivated without a fresh
  /// sign-in.
  final bool canReactivate;
  final bool working;
  final VoidCallback onReactivate;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StartupPanel(
      icon: Icons.phonelink_lock_outlined,
      tone: scheme.error,
      title: 'This device needs authorization',
      message: message,
      footer: const Text('Your business stays protected.'),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No local business data or pending synchronization changes '
                  'have been deleted.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (canReactivate) ...[
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: _buttonShape,
            ),
            onPressed: working ? null : onReactivate,
            child: working
                ? _busySpinner(context)
                : const Text(
                    'Reactivate this device',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(height: 6),
        ],
        TextButton(
          onPressed: working ? null : onSignOut,
          child: const Text('Sign out and sign in again'),
        ),
      ],
    );
  }
}

// ============================================================================
// JOIN OR CREATE
// ============================================================================

class JoinOrCreateView extends StatelessWidget {
  const JoinOrCreateView({
    super.key,
    required this.hasCode,
    required this.busy,
    required this.error,
    required this.codeController,
    required this.onCreate,
    required this.onHaveCode,
    required this.onSubmitCode,
    required this.onBack,
    required this.onCancel,
  });

  /// Whether the invite-code step is showing.
  final bool hasCode;
  final bool busy;
  final String? error;
  final TextEditingController codeController;
  final VoidCallback onCreate;
  final VoidCallback onHaveCode;
  final VoidCallback onSubmitCode;
  final VoidCallback onBack;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StartupPanel(
      icon: hasCode ? Icons.vpn_key_outlined : Icons.rocket_launch_outlined,
      title: 'Set up your business',
      message: hasCode
          ? 'Enter the code the business owner gave you.'
          : 'Start your own business, or join one you were invited to.',
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: hasCode
              ? Column(
                  key: const ValueKey('code'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: codeController,
                      autofocus: true,
                      enabled: !busy,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onSubmitCode(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Invite code',
                        errorText: error,
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: _buttonShape,
                      ),
                      onPressed: busy ? null : onSubmitCode,
                      child: busy
                          ? _busySpinner(context)
                          : const Text(
                              'Join business',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: busy ? null : onBack,
                      child: const Text('Back'),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey('choose'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ChoiceCard(
                      icon: Icons.add_business_rounded,
                      title: 'Create my business',
                      subtitle: 'Set up your own space in a minute.',
                      primary: true,
                      onTap: busy ? null : onCreate,
                    ),
                    const SizedBox(height: 10),
                    _ChoiceCard(
                      icon: Icons.vpn_key_outlined,
                      title: 'I have an invite code',
                      subtitle: 'Join a business you were invited to.',
                      onTap: busy ? null : onHaveCode,
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: busy ? null : onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;
    final sub = primary
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;

    return Material(
      color: primary ? scheme.primary : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: primary
                      ? scheme.onPrimary.withValues(alpha: 0.18)
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: primary ? scheme.onPrimary : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: sub),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: sub),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// NO ACCESS
// ============================================================================

class NoAccessView extends StatelessWidget {
  const NoAccessView({
    super.key,
    required this.busy,
    required this.onJoinWithCode,
    required this.onCreateBusiness,
    required this.onRetry,
    required this.onCancel,
  });

  final bool busy;
  final VoidCallback onJoinWithCode;
  final VoidCallback onCreateBusiness;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StartupPanel(
      icon: Icons.lock_outline_rounded,
      tone: scheme.error,
      title: 'No access to this business',
      message:
          'Your account isn’t an active member of this business, or your '
          'access was removed or suspended. You can join another business, '
          'start your own, or go back.',
      footer: const Text(
        'Cancel switches you to another business, or signs you out if you '
        'don’t have one.',
      ),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: _buttonShape,
          ),
          onPressed: busy ? null : onJoinWithCode,
          icon: const Icon(Icons.confirmation_number_outlined),
          label: const Text(
            'Enter invite code',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: _buttonShape,
          ),
          onPressed: busy ? null : onCreateBusiness,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Create a business'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: _buttonShape,
          ),
          onPressed: busy ? null : onRetry,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: const Text('Check again'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: busy ? null : onCancel,
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}