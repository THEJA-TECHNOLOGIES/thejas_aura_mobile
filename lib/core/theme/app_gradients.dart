import 'package:material_ui/material_ui.dart';

@immutable
class AppGradients extends ThemeExtension<AppGradients> {
  // ── Core ──
  final LinearGradient primary;
  final LinearGradient primaryReverse;
  final LinearGradient primaryVertical;
  final LinearGradient secondary;
  final LinearGradient secondaryReverse;

  // ── Glass / Brand blend ──
  final LinearGradient glass;
  final LinearGradient glassReverse;
  final LinearGradient glassVertical;

  // ── Signature combos ──
  final LinearGradient purpleRose;
  final LinearGradient rosePurple;
  final LinearGradient purpleIndigo;
  final LinearGradient roseDeep;

  // ── Power button face ──
  final LinearGradient power;

  // ── Backgrounds ──
  final LinearGradient backgroundDark;
  final LinearGradient backgroundLight;
  final LinearGradient surface;

  // ── Overlays ──
  final LinearGradient glassOverlay;
  final LinearGradient glassOverlaySubtle;
  final LinearGradient overlayBottom;
  final LinearGradient overlayTop;

  // ── Utility ──
  final LinearGradient shimmer;
  final LinearGradient welcomeBox;

  // ── Password strength ──
  final LinearGradient passwordWeak;
  final LinearGradient passwordMedium;
  final LinearGradient passwordStrong;

  const AppGradients({
    required this.primary,
    required this.primaryReverse,
    required this.primaryVertical,
    required this.secondary,
    required this.secondaryReverse,
    required this.glass,
    required this.glassReverse,
    required this.glassVertical,
    required this.purpleRose,
    required this.rosePurple,
    required this.purpleIndigo,
    required this.roseDeep,
    required this.power,
    required this.backgroundDark,
    required this.backgroundLight,
    required this.surface,
    required this.glassOverlay,
    required this.glassOverlaySubtle,
    required this.overlayBottom,
    required this.overlayTop,
    required this.shimmer,
    required this.welcomeBox,
    required this.passwordWeak,
    required this.passwordMedium,
    required this.passwordStrong,
  });

  // ── Dark Preset ──────────────────────────────────────────────
  static final dark = AppGradients(
    // Primary (mint) — base → lighter
    primary: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF2DD4A7), Color(0xFF5BE3BE)],
    ),
    primaryReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF2DD4A7), Color(0xFF5BE3BE)],
    ),
    primaryVertical: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF2DD4A7), Color(0xFF5BE3BE)],
    ),

    // Secondary (periwinkle blue)
    secondary: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF7C9CFF), Color(0xFF9DB5FF)],
    ),
    secondaryReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF7C9CFF), Color(0xFF9DB5FF)],
    ),

    // Glass — mint → blue blend
    glass: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF5BE3BE), Color(0xFF9DB5FF)],
    ),
    glassReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF5BE3BE), Color(0xFF9DB5FF)],
    ),
    glassVertical: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF5BE3BE), Color(0xFF9DB5FF)],
    ),

    // Signature combos (names kept from the old purple/rose palette:
    // purpleRose = primary → secondary, purpleIndigo = primary tints)
    purpleRose: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2DD4A7), Color(0xFF7C9CFF)],
    ),
    rosePurple: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7C9CFF), Color(0xFF2DD4A7)],
    ),
    purpleIndigo: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF5BE3BE), Color(0xFF2DD4A7)],
    ),
    roseDeep: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9DB5FF), Color(0xFF7C9CFF)],
    ),

    // Power button face (≈160° like the design)
    power: const LinearGradient(
      begin: Alignment(-0.35, -1.0),
      end: Alignment(0.35, 1.0),
      colors: [Color(0xFF3BE3B5), Color(0xFF1DB48C)],
    ),

    // Backgrounds
    backgroundDark: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF060B16), Color(0xFF0A1120)],
    ),
    backgroundLight: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A1120), Color(0xFF101A2E)],
    ),
    surface: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF101A2E), Color(0xFF16223A)],
    ),

    // Overlays
    glassOverlay: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF2DD4A7).withValues(alpha: 0.15),
        const Color(0xFF7C9CFF).withValues(alpha: 0.15),
      ],
    ),
    glassOverlaySubtle: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF2DD4A7).withValues(alpha: 0.08),
        const Color(0xFF7C9CFF).withValues(alpha: 0.08),
      ],
    ),
    overlayBottom: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        const Color(0xFF000000).withValues(alpha: 0.8),
      ],
    ),
    overlayTop: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Colors.transparent,
        const Color(0xFF000000).withValues(alpha: 0.8),
      ],
    ),

    // Shimmer — subtle white flash for skeleton loaders
    shimmer: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.08),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    ),

    // Welcome box tint
    welcomeBox: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF2DD4A7).withValues(alpha: 0.10),
        const Color(0xFF7C9CFF).withValues(alpha: 0.10),
      ],
    ),

    // Password strength indicators (rose / amber / mint)
    passwordWeak: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFFF7C8F), Color(0xFFE8566D)],
    ),
    passwordMedium: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFF6B352), Color(0xFFE09A2E)],
    ),
    passwordStrong: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF2DD4A7), Color(0xFF1DB48C)],
    ),
  );

  static final light = AppGradients(
    // Primary (deep mint) — base → darker, keeps white button text readable
    primary: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF0B7F65), Color(0xFF096B55)],
    ),
    primaryReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF0B7F65), Color(0xFF096B55)],
    ),
    primaryVertical: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0B7F65), Color(0xFF096B55)],
    ),
    secondary: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF4864D9), Color(0xFF3A51B8)],
    ),
    secondaryReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF4864D9), Color(0xFF3A51B8)],
    ),
    glass: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF096B55), Color(0xFF3A51B8)],
    ),
    glassReverse: const LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      colors: [Color(0xFF096B55), Color(0xFF3A51B8)],
    ),
    glassVertical: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF096B55), Color(0xFF3A51B8)],
    ),
    purpleRose: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B7F65), Color(0xFF4864D9)],
    ),
    rosePurple: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4864D9), Color(0xFF0B7F65)],
    ),
    purpleIndigo: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF096B55), Color(0xFF0B7F65)],
    ),
    roseDeep: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3A51B8), Color(0xFF4864D9)],
    ),
    power: const LinearGradient(
      begin: Alignment(-0.35, -1.0),
      end: Alignment(0.35, 1.0),
      colors: [Color(0xFF18A98A), Color(0xFF0B7F65)],
    ),
    backgroundDark: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF4F7FB), Color(0xFFEAF0F8)],
    ),
    backgroundLight: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFFFF), Color(0xFFF4F7FB)],
    ),
    surface: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFEAF0F8)],
    ),
    glassOverlay: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0B7F65).withValues(alpha: 0.08),
        const Color(0xFF4864D9).withValues(alpha: 0.08),
      ],
    ),
    glassOverlaySubtle: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0B7F65).withValues(alpha: 0.04),
        const Color(0xFF4864D9).withValues(alpha: 0.04),
      ],
    ),
    overlayBottom: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        const Color(0xFF000000).withValues(alpha: 0.4),
      ],
    ),
    overlayTop: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Colors.transparent,
        const Color(0xFF000000).withValues(alpha: 0.4),
      ],
    ),
    shimmer: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    ),
    welcomeBox: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0B7F65).withValues(alpha: 0.06),
        const Color(0xFF4864D9).withValues(alpha: 0.06),
      ],
    ),
    passwordWeak: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFD1364F), Color(0xFFB52A42)],
    ),
    passwordMedium: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFB86A00), Color(0xFF9A5A00)],
    ),
    passwordStrong: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF0B7F65), Color(0xFF096B55)],
    ),
  );
  @override
  AppGradients copyWith({
    LinearGradient? primary,
    LinearGradient? primaryReverse,
    LinearGradient? primaryVertical,
    LinearGradient? secondary,
    LinearGradient? secondaryReverse,
    LinearGradient? glass,
    LinearGradient? glassReverse,
    LinearGradient? glassVertical,
    LinearGradient? purpleRose,
    LinearGradient? rosePurple,
    LinearGradient? purpleIndigo,
    LinearGradient? roseDeep,
    LinearGradient? power,
    LinearGradient? backgroundDark,
    LinearGradient? backgroundLight,
    LinearGradient? surface,
    LinearGradient? glassOverlay,
    LinearGradient? glassOverlaySubtle,
    LinearGradient? overlayBottom,
    LinearGradient? overlayTop,
    LinearGradient? shimmer,
    LinearGradient? welcomeBox,
    LinearGradient? passwordWeak,
    LinearGradient? passwordMedium,
    LinearGradient? passwordStrong,
  }) {
    return AppGradients(
      primary: primary ?? this.primary,
      primaryReverse: primaryReverse ?? this.primaryReverse,
      primaryVertical: primaryVertical ?? this.primaryVertical,
      secondary: secondary ?? this.secondary,
      secondaryReverse: secondaryReverse ?? this.secondaryReverse,
      glass: glass ?? this.glass,
      glassReverse: glassReverse ?? this.glassReverse,
      glassVertical: glassVertical ?? this.glassVertical,
      purpleRose: purpleRose ?? this.purpleRose,
      rosePurple: rosePurple ?? this.rosePurple,
      purpleIndigo: purpleIndigo ?? this.purpleIndigo,
      roseDeep: roseDeep ?? this.roseDeep,
      power: power ?? this.power,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      backgroundLight: backgroundLight ?? this.backgroundLight,
      surface: surface ?? this.surface,
      glassOverlay: glassOverlay ?? this.glassOverlay,
      glassOverlaySubtle: glassOverlaySubtle ?? this.glassOverlaySubtle,
      overlayBottom: overlayBottom ?? this.overlayBottom,
      overlayTop: overlayTop ?? this.overlayTop,
      shimmer: shimmer ?? this.shimmer,
      welcomeBox: welcomeBox ?? this.welcomeBox,
      passwordWeak: passwordWeak ?? this.passwordWeak,
      passwordMedium: passwordMedium ?? this.passwordMedium,
      passwordStrong: passwordStrong ?? this.passwordStrong,
    );
  }

  // ── lerp ─────────────────────────────────────────────────────
  @override
  AppGradients lerp(covariant ThemeExtension<AppGradients>? other, double t) {
    if (other is! AppGradients) return this;
    return AppGradients(
      primary: LinearGradient.lerp(primary, other.primary, t)!,
      primaryReverse: LinearGradient.lerp(
        primaryReverse,
        other.primaryReverse,
        t,
      )!,
      primaryVertical: LinearGradient.lerp(
        primaryVertical,
        other.primaryVertical,
        t,
      )!,
      secondary: LinearGradient.lerp(secondary, other.secondary, t)!,
      secondaryReverse: LinearGradient.lerp(
        secondaryReverse,
        other.secondaryReverse,
        t,
      )!,
      glass: LinearGradient.lerp(glass, other.glass, t)!,
      glassReverse: LinearGradient.lerp(glassReverse, other.glassReverse, t)!,
      glassVertical: LinearGradient.lerp(
        glassVertical,
        other.glassVertical,
        t,
      )!,
      purpleRose: LinearGradient.lerp(purpleRose, other.purpleRose, t)!,
      rosePurple: LinearGradient.lerp(rosePurple, other.rosePurple, t)!,
      purpleIndigo: LinearGradient.lerp(purpleIndigo, other.purpleIndigo, t)!,
      roseDeep: LinearGradient.lerp(roseDeep, other.roseDeep, t)!,
      power: LinearGradient.lerp(power, other.power, t)!,
      backgroundDark: LinearGradient.lerp(
        backgroundDark,
        other.backgroundDark,
        t,
      )!,
      backgroundLight: LinearGradient.lerp(
        backgroundLight,
        other.backgroundLight,
        t,
      )!,
      surface: LinearGradient.lerp(surface, other.surface, t)!,
      glassOverlay: LinearGradient.lerp(glassOverlay, other.glassOverlay, t)!,
      glassOverlaySubtle: LinearGradient.lerp(
        glassOverlaySubtle,
        other.glassOverlaySubtle,
        t,
      )!,
      overlayBottom: LinearGradient.lerp(
        overlayBottom,
        other.overlayBottom,
        t,
      )!,
      overlayTop: LinearGradient.lerp(overlayTop, other.overlayTop, t)!,
      shimmer: LinearGradient.lerp(shimmer, other.shimmer, t)!,
      welcomeBox: LinearGradient.lerp(welcomeBox, other.welcomeBox, t)!,
      passwordWeak: LinearGradient.lerp(passwordWeak, other.passwordWeak, t)!,
      passwordMedium: LinearGradient.lerp(
        passwordMedium,
        other.passwordMedium,
        t,
      )!,
      passwordStrong: LinearGradient.lerp(
        passwordStrong,
        other.passwordStrong,
        t,
      )!,
    );
  }
}