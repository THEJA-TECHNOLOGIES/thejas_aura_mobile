import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  // ── Primary Purple/Indigo ──
  final Color primary;
  final Color primary50;
  final Color primary100;
  final Color primary200;
  final Color primary300;
  final Color primary400;
  final Color primary500;
  final Color primary600;
  final Color primary800;
  final Color primary900;
  final Color primary950;

  // ── Secondary Rose/Pink ──
  final Color secondary;
  final Color secondary50;
  final Color secondary100;
  final Color secondary200;
  final Color secondary300;
  final Color secondary400;
  final Color secondary500;
  final Color secondary600;
  final Color secondary800;
  final Color secondary900;
  final Color secondary950;

  // ── Neutrals ──
  final Color white;
  final Color black;
  final Color background;
  final Color surfaceLight;
  final Color surfaceDark;

  // ── Text ──
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color text4;
  final Color text5;

  // ── Borders ──
  final Color border;
  final Color borderLight;
  final Color activeBorder;
  final Color inActiveBorder;

  // ── Components ──
  final Color card;
  final Color accent2;
  final Color accent3;

  // ── Grays ──
  final Color gray;
  final Color gray2;
  final Color gray4;

  // ── Browns (amber/warn tones) ──
  final Color brown;
  final Color brownLight;
  final Color brownExtraLight;

  // ── Status ──
  final Color activeStatus;
  final Color inActiveStatus;
  final Color error;
  final Color errorLight;
  final Color errorExtraLight;
  final Color errorDark;
  final Color success;
  final Color successLight;
  final Color successDark;
  final Color warning;
  final Color warningLight;
  final Color warningDark;

  // ── Primary extras (power button, chips, selection) ──
  final Color onPrimary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color primaryLine;
  final Color primaryRing1;
  final Color primaryRing2;
  final Color primarySelected;

  // ── Power button ──
  final Color powerEdge;
  final Color powerGlow;
  final Color powerHalo;
  final Color offBg;
  final Color offIcon;

  // ── Secondary extras ──
  final Color secondarySoft;
  final Color focus;

  // ── Warning / error extras ──
  final Color warningSoft;
  final Color warningLine;
  final Color errorSoft;
  final Color errorLine;
  final Color onError;

  // ── Violet (logs / reports) ──
  final Color violet;
  final Color violetSoft;

  // ── Surfaces & controls ──
  final Color surfaceRaised;
  final Color segmentBg;
  final Color shimmer;
  final Color trackOff;
  final Color trackOn;
  final Color scrim;

  // ── Toast ──
  final Color toast;
  final Color toastText;
  final Color toastAccent;
  final Color toastError;
  final Color toastWarning;

  // ── Shadow colors ──
  final Color shadowCard;
  final Color shadowSheet;
  final Color shadowOff;
  final Color shadowSegment;

  // ── Block-list categories ──
  final Color catTrackers;
  final Color catAds;
  final Color catMarketing;
  final Color catReports;
  final Color catMalware;
  final Color catSocial;
  final Color catIot;

  const AppColors({
    required this.primary,
    required this.primary50,
    required this.primary100,
    required this.primary200,
    required this.primary300,
    required this.primary400,
    required this.primary500,
    required this.primary600,
    required this.primary800,
    required this.primary900,
    required this.primary950,
    required this.secondary,
    required this.secondary50,
    required this.secondary100,
    required this.secondary200,
    required this.secondary300,
    required this.secondary400,
    required this.secondary500,
    required this.secondary600,
    required this.secondary800,
    required this.secondary900,
    required this.secondary950,
    required this.white,
    required this.black,
    required this.background,
    required this.surfaceLight,
    required this.surfaceDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.text4,
    required this.text5,
    required this.border,
    required this.borderLight,
    required this.activeBorder,
    required this.inActiveBorder,
    required this.card,
    required this.accent2,
    required this.accent3,
    required this.gray,
    required this.gray2,
    required this.gray4,
    required this.brown,
    required this.brownLight,
    required this.brownExtraLight,
    required this.activeStatus,
    required this.inActiveStatus,
    required this.error,
    required this.errorLight,
    required this.errorExtraLight,
    required this.errorDark,
    required this.success,
    required this.successLight,
    required this.successDark,
    required this.warning,
    required this.warningLight,
    required this.warningDark,
    required this.onPrimary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.primaryLine,
    required this.primaryRing1,
    required this.primaryRing2,
    required this.primarySelected,
    required this.powerEdge,
    required this.powerGlow,
    required this.powerHalo,
    required this.offBg,
    required this.offIcon,
    required this.secondarySoft,
    required this.focus,
    required this.warningSoft,
    required this.warningLine,
    required this.errorSoft,
    required this.errorLine,
    required this.onError,
    required this.violet,
    required this.violetSoft,
    required this.surfaceRaised,
    required this.segmentBg,
    required this.shimmer,
    required this.trackOff,
    required this.trackOn,
    required this.scrim,
    required this.toast,
    required this.toastText,
    required this.toastAccent,
    required this.toastError,
    required this.toastWarning,
    required this.shadowCard,
    required this.shadowSheet,
    required this.shadowOff,
    required this.shadowSegment,
    required this.catTrackers,
    required this.catAds,
    required this.catMarketing,
    required this.catReports,
    required this.catMalware,
    required this.catSocial,
    required this.catIot,
  });

  // ── Dark Preset ──────────────────────────────────────────────
  // Bulwark dark: navy surfaces, mint primary, periwinkle secondary,
  // amber for "yours/warn", rose for errors.
  static const dark = AppColors(
    // Primary (mint) — inverted scale (50 = darkest, 950 = lightest in dark mode)
    primary: Color(0xFF2DD4A7),
    primary50: Color(0xFF052B23),
    primary100: Color(0xFF0A4136),
    primary200: Color(0xFF0F5A4A),
    primary300: Color(0xFF12735D),
    primary400: Color(0xFF1DB48C),
    primary500: Color(0xFF2DD4A7),
    primary600: Color(0xFF5BE3BE),
    primary800: Color(0xFFA8F0DC),
    primary900: Color(0xFFD2F8EE),
    primary950: Color(0xFFEAFCF7),

    // Secondary (periwinkle blue) — inverted scale
    secondary: Color(0xFF7C9CFF),
    secondary50: Color(0xFF101A47),
    secondary100: Color(0xFF1B2B75),
    secondary200: Color(0xFF2A41A6),
    secondary300: Color(0xFF3A56CC),
    secondary400: Color(0xFF5F80F5),
    secondary500: Color(0xFF7C9CFF),
    secondary600: Color(0xFF9DB5FF),
    secondary800: Color(0xFFC9D6FF),
    secondary900: Color(0xFFE3EAFF),
    secondary950: Color(0xFFF3F6FF),

    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),

    // Dark backgrounds: background < surfaceLight (cards/sheets) < surfaceDark (raised rows, inputs)
    background: Color(0xFF0A1120),
    surfaceLight: Color(0xFF101A2E),
    surfaceDark: Color(0xFF16223A),
    // Text — light on dark
    textPrimary: Color(0xFFE9EFFB),
    textSecondary: Color(0xFFC3CEE3),
    textTertiary: Color(0xFF93A2BF), // muted
    text4: Color(0xFF6F7F9E), // placeholder
    text5: Color(0xFF4E5D7D), // disabled
    // Borders
    border: Color(0xFF22304D),
    borderLight: Color(0xFF2E4068),
    activeBorder: Color(0xFF2DD4A7), // primary
    inActiveBorder: Color(0xFF2E4068),

    // Components
    card: Color(0xFF101A2E),
    accent2: Color(0xFF5BE3BE), // primary-600 (lighter in dark)
    accent3: Color(0xFF9DB5FF), // secondary-600
    // Grays
    gray: Color(0xFF6F7F9E),
    gray2: Color(0xFF93A2BF),
    gray4: Color(0xFF22304D),

    // Browns (amber tones) — "custom / added by you"
    brown: Color(0xFFF6B352),
    brownLight: Color(0xFF3D2C0E),
    brownExtraLight: Color(0xFF2A1F0A),

    // Status
    activeStatus: Color(0xFF2DD4A7),
    inActiveStatus: Color(0xFF6F7F9E),

    // Error (rose)
    error: Color(0xFFFF7C8F),
    errorLight: Color(0xFF3F1A25),
    errorExtraLight: Color(0xFF2A1119),
    errorDark: Color(0xFFE8566D),

    // Success (mint)
    success: Color(0xFF2DD4A7),
    successLight: Color(0xFF0A4136),
    successDark: Color(0xFF1DB48C),

    // Warning (amber)
    warning: Color(0xFFF6B352),
    warningLight: Color(0xFF3D2C0E),
    warningDark: Color(0xFFE09A2E),

    // Primary extras (power button, chips, selection)
    onPrimary: Color(
      0xFF062A21,
    ), // text/icon on primary fill (dark mode needs dark ink for contrast)
    primaryPressed: Color(0xFF1DB48C), // pressed state of primary button
    primarySoft: Color(0x242DD4A7), // tinted chip / connecting button fill
    primaryLine: Color(0x732DD4A7), // outline on tinted primary surfaces
    primaryRing1: Color(0x382DD4A7), // power button outer ring (active)
    primaryRing2: Color(0x6B2DD4A7), // power button middle ring (active)
    primarySelected: Color(0x142DD4A7), // selected row background
    // Power button
    powerEdge: Color(0x24FFFFFF), // 1px light edge on gradient button
    powerGlow: Color(0x612DD4A7), // drop glow under connected button
    powerHalo: Color(0x1F2DD4A7), // 10px halo ring (desktop card)
    offBg: Color(0xFF16223A), // power button face when off
    offIcon: Color(0xFF7F8FAE), // power icon when off
    // Secondary extras
    secondarySoft: Color(0x297C9CFF), // default-list tint
    focus: Color(0xFF7C9CFF), // keyboard focus ring
    // Warning / error extras
    warningSoft: Color(0x24F6B352), // amber tint
    warningLine: Color(0x80F6B352), // amber outline
    errorSoft: Color(0x1FFF7C8F), // rose tint
    errorLine: Color(0x80FF7C8F), // rose outline
    onError: Color(0xFF2A1119), // text/icon on error fill
    // Violet (logs / reports)
    violet: Color(0xFFB697FF), // logs / reports accent
    violetSoft: Color(0x29B697FF), // violet tint
    // Surfaces & controls
    surfaceRaised: Color(0xFF1F2F50), // active segment / raised chip
    segmentBg: Color(0xFF101A2E), // segmented-control track
    shimmer: Color(0xFF1F2F50), // skeleton highlight sweep
    trackOff: Color(0xFF2B3A5C), // switch / bar track when off
    trackOn: Color(0x732DD4A7), // switch / bar track when on
    scrim: Color(0x73000000), // dialog barrier
    // Toast
    toast: Color(0xFF1B2A47), // toast background
    toastText: Color(0xFFE9EFFB), // toast text
    toastAccent: Color(0xFF2DD4A7), // toast success icon / action
    toastError: Color(0xFFFF7C8F), // toast error icon
    toastWarning: Color(0xFFF6B352), // toast warning icon
    // Shadow colors
    shadowCard: Color(0x59000000), // card shadow
    shadowSheet: Color(0x80000000), // bottom sheet shadow
    shadowOff: Color(0x73000000), // off-state power button shadow
    shadowSegment: Color(0x00000000), // active segment shadow (none in dark)
    // Block-list categories
    catTrackers: Color(0xFF7C9CFF), // Trackers
    catAds: Color(0xFFFF8A6B), // Ads
    catMarketing: Color(0xFFF6B352), // Marketing
    catReports: Color(0xFFB697FF), // Reports
    catMalware: Color(0xFFFF7C8F), // Malware
    catSocial: Color(0xFF58C8F2), // Social
    catIot: Color(0xFF8BD17C), // IoT
  );

  // ── Light Preset ─────────────────────────────────────────────
  // Same roles, darker accent shades so text/icons keep 4.5:1 on white.
  static const light = AppColors(
    // Primary (mint, deepened for light) — normal scale (50 = lightest, 950 = darkest)
    primary: Color(0xFF0B7F65),
    primary50: Color(0xFFE8FBF5),
    primary100: Color(0xFFC9F5E8),
    primary200: Color(0xFF9BE0CB),
    primary300: Color(0xFF3FB596),
    primary400: Color(0xFF0B7F65),
    primary500: Color(0xFF096B55),
    primary600: Color(0xFF075C4A),
    primary800: Color(0xFF054536),
    primary900: Color(0xFF03342A),
    primary950: Color(0xFF021F19),

    // Secondary (blue)
    secondary: Color(0xFF4864D9),
    secondary50: Color(0xFFF0F3FE),
    secondary100: Color(0xFFDDE4FC),
    secondary200: Color(0xFFB9C6F7),
    secondary300: Color(0xFF8197EA),
    secondary400: Color(0xFF4864D9),
    secondary500: Color(0xFF3A51B8),
    secondary600: Color(0xFF2E4196),
    secondary800: Color(0xFF1F2C69),
    secondary900: Color(0xFF151E48),
    secondary950: Color(0xFF0C1230),

    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),

    // Light backgrounds
    background: Color(0xFFF4F7FB),
    surfaceLight: Color(0xFFFFFFFF),
    surfaceDark: Color(0xFFEAF0F8),
    // Text — dark on light
    textPrimary: Color(0xFF0F1B33),
    textSecondary: Color(0xFF34445F),
    textTertiary: Color(0xFF56677F), // muted
    text4: Color(0xFF7A8AA5), // placeholder
    text5: Color(0xFFA9B6CA), // disabled
    // Borders
    border: Color(0xFFD8E0EC),
    borderLight: Color(0xFFC5D0E2),
    activeBorder: Color(0xFF0B7F65),
    inActiveBorder: Color(0xFFC5D0E2),

    // Components
    card: Color(0xFFFFFFFF),
    accent2: Color(0xFF096B55),
    accent3: Color(0xFF3A51B8),

    // Grays
    gray: Color(0xFF7A8AA5),
    gray2: Color(0xFF56677F),
    gray4: Color(0xFFD8E0EC),

    // Browns (amber tones)
    brown: Color(0xFF9A5A00),
    brownLight: Color(0xFFFDF1DC),
    brownExtraLight: Color(0xFFFEF8EC),

    // Status
    activeStatus: Color(0xFF0B7F65),
    inActiveStatus: Color(0xFF7A8AA5),

    // Error
    error: Color(0xFFD1364F),
    errorLight: Color(0xFFFBE3E7),
    errorExtraLight: Color(0xFFFEF2F4),
    errorDark: Color(0xFFB52A42),

    // Success
    success: Color(0xFF0B7F65),
    successLight: Color(0xFFD6F2E9),
    successDark: Color(0xFF096B55),

    // Warning
    warning: Color(0xFF9A5A00),
    warningLight: Color(0xFFFDF1DC),
    warningDark: Color(0xFF7F4A00),

    // Primary extras (power button, chips, selection)
    onPrimary: Color(
      0xFFFFFFFF,
    ), // text/icon on primary fill (dark mode needs dark ink for contrast)
    primaryPressed: Color(0xFF096B55), // pressed state of primary button
    primarySoft: Color(0x1A0B7F65), // tinted chip / connecting button fill
    primaryLine: Color(0x730B7F65), // outline on tinted primary surfaces
    primaryRing1: Color(0x2E0B7F65), // power button outer ring (active)
    primaryRing2: Color(0x610B7F65), // power button middle ring (active)
    primarySelected: Color(0x140B7F65), // selected row background
    // Power button
    powerEdge: Color(0x47FFFFFF), // 1px light edge on gradient button
    powerGlow: Color(0x520B7F65), // drop glow under connected button
    powerHalo: Color(0x1A0B7F65), // 10px halo ring (desktop card)
    offBg: Color(0xFFE6EDF7), // power button face when off
    offIcon: Color(0xFF7A8AA5), // power icon when off
    // Secondary extras
    secondarySoft: Color(0x1F4864D9), // default-list tint
    focus: Color(0xFF4864D9), // keyboard focus ring
    // Warning / error extras
    warningSoft: Color(0x1A9A5A00), // amber tint
    warningLine: Color(0x739A5A00), // amber outline
    errorSoft: Color(0x17D1364F), // rose tint
    errorLine: Color(0x66D1364F), // rose outline
    onError: Color(0xFFFFFFFF), // text/icon on error fill
    // Violet (logs / reports)
    violet: Color(0xFF7B4FD1), // logs / reports accent
    violetSoft: Color(0x1F7B4FD1), // violet tint
    // Surfaces & controls
    surfaceRaised: Color(0xFFFFFFFF), // active segment / raised chip
    segmentBg: Color(0xFFE6EDF7), // segmented-control track
    shimmer: Color(0xFFF7FAFD), // skeleton highlight sweep
    trackOff: Color(0xFFC5D0E2), // switch / bar track when off
    trackOn: Color(0x730B7F65), // switch / bar track when on
    scrim: Color(0x610F1B33), // dialog barrier
    // Toast
    toast: Color(0xFF10203F), // toast background
    toastText: Color(0xFFFFFFFF), // toast text
    toastAccent: Color(0xFF5BE3BE), // toast success icon / action
    toastError: Color(0xFFFF8DA0), // toast error icon
    toastWarning: Color(0xFFF6B352), // toast warning icon
    // Shadow colors
    shadowCard: Color(0x120F1B33), // card shadow
    shadowSheet: Color(0x240F1B33), // bottom sheet shadow
    shadowOff: Color(0x1A0F1B33), // off-state power button shadow
    shadowSegment: Color(0x240F1B33), // active segment shadow (none in dark)
    // Block-list categories
    catTrackers: Color(0xFF4864D9), // Trackers
    catAds: Color(0xFFC4512F), // Ads
    catMarketing: Color(0xFF9A5A00), // Marketing
    catReports: Color(0xFF7B4FD1), // Reports
    catMalware: Color(0xFFD1364F), // Malware
    catSocial: Color(0xFF0F7FA6), // Social
    catIot: Color(0xFF3F8A2C), // IoT
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primary50,
    Color? primary100,
    Color? primary200,
    Color? primary300,
    Color? primary400,
    Color? primary500,
    Color? primary600,
    Color? primary800,
    Color? primary900,
    Color? primary950,
    Color? secondary,
    Color? secondary50,
    Color? secondary100,
    Color? secondary200,
    Color? secondary300,
    Color? secondary400,
    Color? secondary500,
    Color? secondary600,
    Color? secondary800,
    Color? secondary900,
    Color? secondary950,
    Color? white,
    Color? black,
    Color? background,
    Color? surfaceLight,
    Color? surfaceDark,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? text4,
    Color? text5,
    Color? border,
    Color? borderLight,
    Color? activeBorder,
    Color? inActiveBorder,
    Color? card,
    Color? accent2,
    Color? accent3,
    Color? gray,
    Color? gray2,
    Color? gray4,
    Color? brown,
    Color? brownLight,
    Color? brownExtraLight,
    Color? activeStatus,
    Color? inActiveStatus,
    Color? error,
    Color? errorLight,
    Color? errorExtraLight,
    Color? errorDark,
    Color? success,
    Color? successLight,
    Color? successDark,
    Color? warning,
    Color? warningLight,
    Color? warningDark,
    Color? onPrimary,
    Color? primaryPressed,
    Color? primarySoft,
    Color? primaryLine,
    Color? primaryRing1,
    Color? primaryRing2,
    Color? primarySelected,
    Color? powerEdge,
    Color? powerGlow,
    Color? powerHalo,
    Color? offBg,
    Color? offIcon,
    Color? secondarySoft,
    Color? focus,
    Color? warningSoft,
    Color? warningLine,
    Color? errorSoft,
    Color? errorLine,
    Color? onError,
    Color? violet,
    Color? violetSoft,
    Color? surfaceRaised,
    Color? segmentBg,
    Color? shimmer,
    Color? trackOff,
    Color? trackOn,
    Color? scrim,
    Color? toast,
    Color? toastText,
    Color? toastAccent,
    Color? toastError,
    Color? toastWarning,
    Color? shadowCard,
    Color? shadowSheet,
    Color? shadowOff,
    Color? shadowSegment,
    Color? catTrackers,
    Color? catAds,
    Color? catMarketing,
    Color? catReports,
    Color? catMalware,
    Color? catSocial,
    Color? catIot,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primary50: primary50 ?? this.primary50,
      primary100: primary100 ?? this.primary100,
      primary200: primary200 ?? this.primary200,
      primary300: primary300 ?? this.primary300,
      primary400: primary400 ?? this.primary400,
      primary500: primary500 ?? this.primary500,
      primary600: primary600 ?? this.primary600,
      primary800: primary800 ?? this.primary800,
      primary900: primary900 ?? this.primary900,
      primary950: primary950 ?? this.primary950,
      secondary: secondary ?? this.secondary,
      secondary50: secondary50 ?? this.secondary50,
      secondary100: secondary100 ?? this.secondary100,
      secondary200: secondary200 ?? this.secondary200,
      secondary300: secondary300 ?? this.secondary300,
      secondary400: secondary400 ?? this.secondary400,
      secondary500: secondary500 ?? this.secondary500,
      secondary600: secondary600 ?? this.secondary600,
      secondary800: secondary800 ?? this.secondary800,
      secondary900: secondary900 ?? this.secondary900,
      secondary950: secondary950 ?? this.secondary950,
      white: white ?? this.white,
      black: black ?? this.black,
      background: background ?? this.background,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      text4: text4 ?? this.text4,
      text5: text5 ?? this.text5,
      border: border ?? this.border,
      borderLight: borderLight ?? this.borderLight,
      activeBorder: activeBorder ?? this.activeBorder,
      inActiveBorder: inActiveBorder ?? this.inActiveBorder,
      card: card ?? this.card,
      accent2: accent2 ?? this.accent2,
      accent3: accent3 ?? this.accent3,
      gray: gray ?? this.gray,
      gray2: gray2 ?? this.gray2,
      gray4: gray4 ?? this.gray4,
      brown: brown ?? this.brown,
      brownLight: brownLight ?? this.brownLight,
      brownExtraLight: brownExtraLight ?? this.brownExtraLight,
      activeStatus: activeStatus ?? this.activeStatus,
      inActiveStatus: inActiveStatus ?? this.inActiveStatus,
      error: error ?? this.error,
      errorLight: errorLight ?? this.errorLight,
      errorExtraLight: errorExtraLight ?? this.errorExtraLight,
      errorDark: errorDark ?? this.errorDark,
      success: success ?? this.success,
      successLight: successLight ?? this.successLight,
      successDark: successDark ?? this.successDark,
      warning: warning ?? this.warning,
      warningLight: warningLight ?? this.warningLight,
      warningDark: warningDark ?? this.warningDark,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryLine: primaryLine ?? this.primaryLine,
      primaryRing1: primaryRing1 ?? this.primaryRing1,
      primaryRing2: primaryRing2 ?? this.primaryRing2,
      primarySelected: primarySelected ?? this.primarySelected,
      powerEdge: powerEdge ?? this.powerEdge,
      powerGlow: powerGlow ?? this.powerGlow,
      powerHalo: powerHalo ?? this.powerHalo,
      offBg: offBg ?? this.offBg,
      offIcon: offIcon ?? this.offIcon,
      secondarySoft: secondarySoft ?? this.secondarySoft,
      focus: focus ?? this.focus,
      warningSoft: warningSoft ?? this.warningSoft,
      warningLine: warningLine ?? this.warningLine,
      errorSoft: errorSoft ?? this.errorSoft,
      errorLine: errorLine ?? this.errorLine,
      onError: onError ?? this.onError,
      violet: violet ?? this.violet,
      violetSoft: violetSoft ?? this.violetSoft,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      segmentBg: segmentBg ?? this.segmentBg,
      shimmer: shimmer ?? this.shimmer,
      trackOff: trackOff ?? this.trackOff,
      trackOn: trackOn ?? this.trackOn,
      scrim: scrim ?? this.scrim,
      toast: toast ?? this.toast,
      toastText: toastText ?? this.toastText,
      toastAccent: toastAccent ?? this.toastAccent,
      toastError: toastError ?? this.toastError,
      toastWarning: toastWarning ?? this.toastWarning,
      shadowCard: shadowCard ?? this.shadowCard,
      shadowSheet: shadowSheet ?? this.shadowSheet,
      shadowOff: shadowOff ?? this.shadowOff,
      shadowSegment: shadowSegment ?? this.shadowSegment,
      catTrackers: catTrackers ?? this.catTrackers,
      catAds: catAds ?? this.catAds,
      catMarketing: catMarketing ?? this.catMarketing,
      catReports: catReports ?? this.catReports,
      catMalware: catMalware ?? this.catMalware,
      catSocial: catSocial ?? this.catSocial,
      catIot: catIot ?? this.catIot,
    );
  }

  // ── lerp ─────────────────────────────────────────────────────
  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primary50: Color.lerp(primary50, other.primary50, t)!,
      primary100: Color.lerp(primary100, other.primary100, t)!,
      primary200: Color.lerp(primary200, other.primary200, t)!,
      primary300: Color.lerp(primary300, other.primary300, t)!,
      primary400: Color.lerp(primary400, other.primary400, t)!,
      primary500: Color.lerp(primary500, other.primary500, t)!,
      primary600: Color.lerp(primary600, other.primary600, t)!,
      primary800: Color.lerp(primary800, other.primary800, t)!,
      primary900: Color.lerp(primary900, other.primary900, t)!,
      primary950: Color.lerp(primary950, other.primary950, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondary50: Color.lerp(secondary50, other.secondary50, t)!,
      secondary100: Color.lerp(secondary100, other.secondary100, t)!,
      secondary200: Color.lerp(secondary200, other.secondary200, t)!,
      secondary300: Color.lerp(secondary300, other.secondary300, t)!,
      secondary400: Color.lerp(secondary400, other.secondary400, t)!,
      secondary500: Color.lerp(secondary500, other.secondary500, t)!,
      secondary600: Color.lerp(secondary600, other.secondary600, t)!,
      secondary800: Color.lerp(secondary800, other.secondary800, t)!,
      secondary900: Color.lerp(secondary900, other.secondary900, t)!,
      secondary950: Color.lerp(secondary950, other.secondary950, t)!,
      white: Color.lerp(white, other.white, t)!,
      black: Color.lerp(black, other.black, t)!,
      background: Color.lerp(background, other.background, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      text4: Color.lerp(text4, other.text4, t)!,
      text5: Color.lerp(text5, other.text5, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      activeBorder: Color.lerp(activeBorder, other.activeBorder, t)!,
      inActiveBorder: Color.lerp(inActiveBorder, other.inActiveBorder, t)!,
      card: Color.lerp(card, other.card, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accent3: Color.lerp(accent3, other.accent3, t)!,
      gray: Color.lerp(gray, other.gray, t)!,
      gray2: Color.lerp(gray2, other.gray2, t)!,
      gray4: Color.lerp(gray4, other.gray4, t)!,
      brown: Color.lerp(brown, other.brown, t)!,
      brownLight: Color.lerp(brownLight, other.brownLight, t)!,
      brownExtraLight: Color.lerp(brownExtraLight, other.brownExtraLight, t)!,
      activeStatus: Color.lerp(activeStatus, other.activeStatus, t)!,
      inActiveStatus: Color.lerp(inActiveStatus, other.inActiveStatus, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorLight: Color.lerp(errorLight, other.errorLight, t)!,
      errorExtraLight: Color.lerp(errorExtraLight, other.errorExtraLight, t)!,
      errorDark: Color.lerp(errorDark, other.errorDark, t)!,
      success: Color.lerp(success, other.success, t)!,
      successLight: Color.lerp(successLight, other.successLight, t)!,
      successDark: Color.lerp(successDark, other.successDark, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningLight: Color.lerp(warningLight, other.warningLight, t)!,
      warningDark: Color.lerp(warningDark, other.warningDark, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      primaryLine: Color.lerp(primaryLine, other.primaryLine, t)!,
      primaryRing1: Color.lerp(primaryRing1, other.primaryRing1, t)!,
      primaryRing2: Color.lerp(primaryRing2, other.primaryRing2, t)!,
      primarySelected: Color.lerp(primarySelected, other.primarySelected, t)!,
      powerEdge: Color.lerp(powerEdge, other.powerEdge, t)!,
      powerGlow: Color.lerp(powerGlow, other.powerGlow, t)!,
      powerHalo: Color.lerp(powerHalo, other.powerHalo, t)!,
      offBg: Color.lerp(offBg, other.offBg, t)!,
      offIcon: Color.lerp(offIcon, other.offIcon, t)!,
      secondarySoft: Color.lerp(secondarySoft, other.secondarySoft, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningLine: Color.lerp(warningLine, other.warningLine, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      errorLine: Color.lerp(errorLine, other.errorLine, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      violetSoft: Color.lerp(violetSoft, other.violetSoft, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      segmentBg: Color.lerp(segmentBg, other.segmentBg, t)!,
      shimmer: Color.lerp(shimmer, other.shimmer, t)!,
      trackOff: Color.lerp(trackOff, other.trackOff, t)!,
      trackOn: Color.lerp(trackOn, other.trackOn, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      toast: Color.lerp(toast, other.toast, t)!,
      toastText: Color.lerp(toastText, other.toastText, t)!,
      toastAccent: Color.lerp(toastAccent, other.toastAccent, t)!,
      toastError: Color.lerp(toastError, other.toastError, t)!,
      toastWarning: Color.lerp(toastWarning, other.toastWarning, t)!,
      shadowCard: Color.lerp(shadowCard, other.shadowCard, t)!,
      shadowSheet: Color.lerp(shadowSheet, other.shadowSheet, t)!,
      shadowOff: Color.lerp(shadowOff, other.shadowOff, t)!,
      shadowSegment: Color.lerp(shadowSegment, other.shadowSegment, t)!,
      catTrackers: Color.lerp(catTrackers, other.catTrackers, t)!,
      catAds: Color.lerp(catAds, other.catAds, t)!,
      catMarketing: Color.lerp(catMarketing, other.catMarketing, t)!,
      catReports: Color.lerp(catReports, other.catReports, t)!,
      catMalware: Color.lerp(catMalware, other.catMalware, t)!,
      catSocial: Color.lerp(catSocial, other.catSocial, t)!,
      catIot: Color.lerp(catIot, other.catIot, t)!,
    );
  }
}
