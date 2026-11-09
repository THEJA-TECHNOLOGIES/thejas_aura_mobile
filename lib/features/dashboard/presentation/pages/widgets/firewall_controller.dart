import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/core/utils/sized_context.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/disconnect_confirmation_dialog.dart';

class FirewallController extends StatelessWidget {
  const FirewallController({super.key});

  static String _formatRemaining(Duration duration) {
    if (duration.inHours > 0) {
      final mins = duration.inMinutes % 60;
      return mins > 0
          ? '${duration.inHours}h ${mins}m'
          : '${duration.inHours}h';
    }
    final mins = duration.inMinutes;
    return mins > 0 ? '${mins}m' : '< 1m';
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      DashboardBloc,
      DashboardState,
      (bool, bool, TunnelStatus, VpnPolicy)
    >(
      selector: (s) =>
          (s.isInitialized, s.isTogglingTunnel, s.status, s.policy),
      builder: (context, state) {
        final (isInitialized, isTogglingTunnel, status, policy) = state;
        final bloc = context.read<DashboardBloc>();
        final isPaused = policy.isPaused;
        final remaining = policy.remainingPauseDuration;

        final busy =
            !isInitialized ||
            isTogglingTunnel ||
            status == TunnelStatus.connecting ||
            status == TunnelStatus.disconnecting;

        final face = busy
            ? PowerFace.connecting
            : (status == TunnelStatus.connected && !isPaused)
            ? PowerFace.on
            : PowerFace.off;

        final stopping = status == TunnelStatus.disconnecting;

        return PowerHero(
          face: face,
          title: switch (face) {
            PowerFace.off =>
              isPaused ? 'Protection is paused' : 'Protection is off',
            PowerFace.connecting =>
              stopping ? 'Stopping protection…' : 'Starting protection…',
            PowerFace.on => "You're protected",
          },
          subtitle: switch (face) {
            PowerFace.off =>
              isPaused
                  ? 'Paused for ${_formatRemaining(remaining)}. Tap to resume.'
                  : 'Tap the button to raise the wall.',
            PowerFace.connecting =>
              stopping
                  ? 'Turning off the local filter.'
                  : 'Setting up the local filter. This only takes a moment.',
            PowerFace.on => 'Blocking trackers and ads across every app.',
          },
          chipText: switch (face) {
            PowerFace.off => isPaused ? 'Paused' : 'Not filtering',
            PowerFace.connecting => 'Connecting',
            PowerFace.on => 'Local filtering active',
          },
          onTap: busy
              ? null
              : () async {
                  if (status == TunnelStatus.connected && !isPaused) {
                    final choice = await showDisconnectConfirmationDialog(
                      context,
                      isAlwaysOnActive: policy.isAlwaysOnActive,
                      isLockdownActive: policy.isLockdownActive,
                      onOpenVpnSettings: () => bloc.openVpnSettings(),
                    );
                    if (choice == null) return; // Cancelled
                    if (choice is Duration) {
                      await bloc.pauseTunnel(choice);
                    } else if (choice == 'shutdown') {
                      await bloc.shutdownTunnel();
                    }
                  } else {
                    bloc.add(const DashboardEvent.tunnelToggled());
                  }
                },
        );
      },
    );
  }
}

enum PowerFace { off, connecting, on }

/// Design tokens used by the hero (copied from the Bulwark design).
class Tokens {
  Tokens(this.dark)
    : teal = dark ? const Color(0xFF2DD4A7) : const Color(0xFF0B7F65),
      onTeal = dark ? const Color(0xFF062A21) : const Color(0xFFFFFFFF),
      tealSoft = dark
          ? const Color(0x242DD4A7)
          : const Color(0x1A0B7F65), // .14 / .10
      tealLine = dark
          ? const Color(0x732DD4A7)
          : const Color(0x730B7F65), // .45
      ring1 = dark
          ? const Color(0x382DD4A7)
          : const Color(0x2E0B7F65), // .22 / .18
      ring2 = dark
          ? const Color(0x6B2DD4A7)
          : const Color(0x610B7F65), // .42 / .38
      line = dark ? const Color(0xFF22304D) : const Color(0xFFD8E0EC),
      s2 = dark ? const Color(0xFF16223A) : const Color(0xFFEAF0F8),
      offBg = dark ? const Color(0xFF16223A) : const Color(0xFFE6EDF7),
      offIcon = dark ? const Color(0xFF7F8FAE) : const Color(0xFF7A8AA5),
      muted = dark ? const Color(0xFF93A2BF) : const Color(0xFF56677F),
      text = dark ? const Color(0xFFE9EFFB) : const Color(0xFF0F1B33),
      gradient = LinearGradient(
        // 160deg in CSS
        begin: const Alignment(-0.342, -0.94),
        end: const Alignment(0.342, 0.94),
        colors: dark
            ? const [Color(0xFF3BE3B5), Color(0xFF1DB48C)]
            : const [Color(0xFF18A98A), Color(0xFF0B7F65)],
      ),
      onInset = dark
          ? const Color(0x24FFFFFF)
          : const Color(0x47FFFFFF), // .14 / .28
      onGlow = dark
          ? const Color(0x612DD4A7)
          : const Color(0x520B7F65); // .38 / .32

  final bool dark;
  final Color teal, onTeal, tealSoft, tealLine, ring1, ring2, line, s2;
  final Color offBg, offIcon, muted, text, onInset, onGlow;
  final LinearGradient gradient;
}

class PowerHero extends StatefulWidget {
  const PowerHero({
    super.key,
    required this.face,
    required this.title,
    required this.subtitle,
    required this.chipText,
    this.onTap,
  });

  final PowerFace face;
  final String title, subtitle, chipText;
  final VoidCallback? onTap;

  @override
  State<PowerHero> createState() => _PowerHeroState();
}

class _PowerHeroState extends State<PowerHero> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PowerHero old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final connecting = widget.face == PowerFace.connecting;
    if (connecting && !_spin.isAnimating) {
      _spin.repeat();
      _pulse.repeat();
    } else if (!connecting && _spin.isAnimating) {
      _spin.stop();
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  bool _isFocused = false;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = Tokens(context.isDark);
    final face = widget.face;
    final connecting = face == PowerFace.connecting;

    // Chip
    final chipFg = face == PowerFace.off ? t.muted : t.teal;
    final chipBg = face == PowerFace.off ? t.s2 : t.tealSoft;

    // Rings (outer, middle)
    final ring1 = switch (face) {
      PowerFace.off || PowerFace.connecting => t.line,
      PowerFace.on => t.ring1,
    };
    final ring2 = _isFocused
        ? context.isDark
              ? Colors.white
              : Colors.black
        : switch (face) {
            PowerFace.off => t.line,
            PowerFace.connecting => t.ring1,
            PowerFace.on => t.ring2,
          };

    // Button face
    final BoxDecoration button;
    final BoxDecoration buttonOverlay; // the "inset" 1px edge
    final Color iconColor;
    switch (face) {
      case PowerFace.on:
        button = BoxDecoration(
          shape: BoxShape.circle,
          gradient: t.gradient,
          boxShadow: !context.isMobile
              ? []
              : [
                  BoxShadow(
                    color: t.onGlow,
                    blurRadius: t.dark ? 56 : 44,
                    offset: Offset(0, t.dark ? 18 : 16),
                  ),
                ],
        );
        buttonOverlay = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.onInset, width: 1),
        );
        iconColor = t.onTeal;
      case PowerFace.connecting:
        button = BoxDecoration(shape: BoxShape.circle, color: t.tealSoft);
        buttonOverlay = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.tealLine, width: 1.5),
        );
        iconColor = t.teal;
      case PowerFace.off:
        button = BoxDecoration(
          shape: BoxShape.circle,
          color: t.offBg,
          boxShadow: !context.isMobile
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: t.dark ? 0.45 : 0.10),
                    blurRadius: t.dark ? 30 : 24,
                    offset: Offset(0, t.dark ? 12 : 10),
                  ),
                ],
        );
        buttonOverlay = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.line, width: 1),
        );
        iconColor = t.offIcon;
    }

    const dur = Duration(milliseconds: 300);

    return Focus(
      autofocus: PlatformChecker.isAndroidTV ? true : false,
      onFocusChange: (bool hasFocus) {
        if (!PlatformChecker.isAndroidTV) {
          return;
        }
        setState(() {
          _isFocused = hasFocus;
        });
      },
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          final isRemoteSelect =
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA;
          final isKeyboardEnter =
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;

          if (isRemoteSelect || isKeyboardEnter) {
            if (widget.onTap != null) {
              widget.onTap?.call();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: context.isMobile || context.isTablet
              ? null
              : .symmetric(
                  horizontal: PlatformChecker.isAndroidTV ? 34 : 78,
                  vertical: 24,
                ),
          decoration: context.isMobile || context.isTablet
              ? null
              : BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: .circular(20),
                  border: Border.all(color: colors.border, width: 1),
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (context.isMobile || context.isTablet) ...[
                AnimatedContainer(
                  duration: dur,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, _) {
                          // bw-pulse: ring grows 0→8px and fades .55→0 over first 70%.
                          final p = (_pulse.value / 0.7).clamp(0.0, 1.0);
                          final show = connecting && _pulse.value < 0.7;
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chipFg,
                              boxShadow: show
                                  ? [
                                      BoxShadow(
                                        color: t.teal.withValues(
                                          alpha: 0.55 * (1 - p),
                                        ),
                                        spreadRadius: 8 * p,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.chipText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: chipFg,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Rings + button ──────────────────────────────────────────
              Semantics(
                button: true,
                enabled: widget.onTap != null,
                label: switch (face) {
                  PowerFace.off => 'Turn protection on',
                  PowerFace.connecting => 'Starting protection',
                  PowerFace.on => 'Turn protection off',
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // outer ring 240
                        AnimatedContainer(
                          duration: dur,
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ring1, width: 1),
                          ),
                        ),
                        // spinning arc rides on the OUTER ring while connecting
                        if (connecting)
                          RotationTransition(
                            turns: _spin,
                            child: CustomPaint(
                              size: const Size(240, 240),
                              painter: _ArcPainter(t.teal),
                            ),
                          ),
                        // middle ring 206
                        AnimatedContainer(
                          duration: dur,
                          width: 206,
                          height: 206,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ring2,
                              width: _isFocused ? 3 : 1,
                            ),
                          ),
                        ),
                        // button 172
                        AnimatedContainer(
                          duration: dur,
                          curve: Curves.easeOut,
                          width: 172,
                          height: 172,
                          decoration: button,
                          foregroundDecoration: buttonOverlay,
                          alignment: Alignment.center,
                          child: CustomPaint(
                            size: const Size(66, 66),
                            painter: _PowerIconPainter(iconColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Title + subtitle ────────────────────────────────────────
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.52,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: t.muted,
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
}

/// 3px round-capped arc on the outer ring: 130 of 748 px circumference ≈ 62.6°.
class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    final r = size.width / 2 - 1; // r=119 on a 240 box
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: r),
      0,
      130 / 119, // arc length / radius
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

/// The exact power glyph from the design (24-unit viewBox, stroke 2.1).
class _PowerIconPainter extends CustomPainter {
  _PowerIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final path = Path()
      ..moveTo(12 * s, 3 * s)
      ..lineTo(12 * s, 11 * s)
      ..moveTo(6.3 * s, 6.8 * s)
      ..arcToPoint(
        Offset(17.7 * s, 6.8 * s),
        radius: Radius.circular(8 * s),
        largeArc: true,
        clockwise: false,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PowerIconPainter old) => old.color != color;
}
