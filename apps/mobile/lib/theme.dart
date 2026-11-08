// Drop It mobile design system - Apple Human Interface Guidelines.
// Rules for contributors/agents live in AGENTS.md and .cursor/rules/apple-hig-design.mdc.
// Never hardcode colors in widgets: read them from `context.apple`.

import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoSlidingSegmentedControl,
        CupertinoDatePickerMode,
        CupertinoPageTransitionsBuilder,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';

/// Radii (Apple continuous-corner hierarchy).
class Radii {
  static const double sm = 10; // segmented controls, inner tiles
  static const double control = 12; // buttons, inputs
  static const double card = 16; // grouped cards
  static const double sheet = 20; // sheets, drawers, hero cards
}

/// Spacing (8pt grid).
class Gaps {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double hit = 44; // minimum touch target
}

@immutable
class AppleColors extends ThemeExtension<AppleColors> {
  const AppleColors({
    required this.groupedBg,
    required this.cardBg,
    required this.tertiaryFill,
    required this.glass,
    required this.labelSecondary,
    required this.separator,
    required this.accentPrimary,
    required this.accentTint,
    required this.accentEnergy,
    required this.accentEnergyText,
    required this.accentSuccess,
    required this.accentSuccessText,
    required this.accentDanger,
    required this.accentDangerText,
    required this.fastGradient,
    required this.fastButtonText,
  });

  final Color groupedBg;
  final Color cardBg;
  final Color tertiaryFill;
  final Color glass;
  final Color labelSecondary;
  final Color separator;
  final Color accentPrimary;
  final Color accentTint;
  final Color accentEnergy;
  final Color accentEnergyText;
  final Color accentSuccess;
  final Color accentSuccessText;
  final Color accentDanger;
  final Color accentDangerText;
  final List<Color> fastGradient;
  final Color fastButtonText;

  static const light = AppleColors(
    groupedBg: Color(0xFFF2F2F7),
    cardBg: Color(0xFFFFFFFF),
    tertiaryFill: Color(0xFFEFEFF4),
    glass: Color(0xC7FFFFFF),
    // 0.76 alpha (iOS uses 0.6) so 13pt secondary text passes WCAG AA.
    labelSecondary: Color(0xC23C3C43),
    separator: Color(0x2E3C3C43),
    accentPrimary: Color(0xFF007AFF),
    accentTint: Color(0x1F007AFF),
    accentEnergy: Color(0xFFFF9500),
    accentEnergyText: Color(0xFFC93400),
    accentSuccess: Color(0xFF34C759),
    accentSuccessText: Color(0xFF248A3D),
    accentDanger: Color(0xFFFF3B30),
    accentDangerText: Color(0xFFD70015),
    fastGradient: [Color(0xFFFF9F0A), Color(0xFFFF6A00)],
    fastButtonText: Color(0xFFC93400),
  );

  static const dark = AppleColors(
    groupedBg: Color(0xFF000000),
    cardBg: Color(0xFF1C1C1E),
    tertiaryFill: Color(0xFF2C2C2E),
    glass: Color(0xC71C1C1E),
    labelSecondary: Color(0x99EBEBF5),
    separator: Color(0x73545458),
    accentPrimary: Color(0xFF0A84FF),
    accentTint: Color(0x2E0A84FF),
    accentEnergy: Color(0xFFFF9F0A),
    accentEnergyText: Color(0xFFFF9F0A),
    accentSuccess: Color(0xFF30D158),
    accentSuccessText: Color(0xFF30D158),
    accentDanger: Color(0xFFFF453A),
    accentDangerText: Color(0xFFFF453A),
    fastGradient: [Color(0xFFFF9F0A), Color(0xFFE8590C)],
    fastButtonText: Color(0xFFC93400),
  );

  @override
  AppleColors copyWith() => this;

  @override
  AppleColors lerp(ThemeExtension<AppleColors>? other, double t) {
    if (other is! AppleColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppleThemeContext on BuildContext {
  AppleColors get apple =>
      Theme.of(this).extension<AppleColors>() ?? AppleColors.dark;
}

ThemeData buildAppleTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? AppleColors.dark : AppleColors.light;
  final label = dark ? Colors.white : Colors.black;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: c.accentPrimary,
        onPrimary: Colors.white,
        secondary: c.accentPrimary,
        surface: c.cardBg,
        onSurface: label,
        error: c.accentDanger,
        outline: c.separator,
        outlineVariant: c.separator,
      );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );
  const controlSize = Size(0, Gaps.hit);
  const buttonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  const pressShadow = Color(0x40000000);
  final pressOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return const Color(0x33000000);
    return null;
  });
  final pressElevation = WidgetStateProperty.resolveWith<double>((states) {
    if (states.contains(WidgetState.disabled) || states.contains(WidgetState.pressed)) {
      return 0;
    }
    return 3;
  });
  Widget pressScale(BuildContext context, Set<WidgetState> states, Widget? child) {
    final pressed = states.contains(WidgetState.pressed);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: pressed ? 0.96 : 1,
      duration: reduce ? Duration.zero : Duration(milliseconds: pressed ? 60 : 150),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.groupedBg,
    canvasColor: c.groupedBg,
    extensions: [c],
    splashFactory: const PressFadeFactory(),
    splashColor: const Color(0x33000000),
    highlightColor: c.accentTint,
    popupMenuTheme: PopupMenuThemeData(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: c.separator, width: 0.5),
      ),
      textStyle: TextStyle(
        color: label,
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: Gaps.xs),
    ),
    dividerTheme: DividerThemeData(
      color: c.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    cardTheme: CardThemeData(
      color: c.cardBg,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: dark
            ? BorderSide(color: c.separator, width: 0.5)
            : BorderSide.none,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.glass,
      foregroundColor: label,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: label,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      shape: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(Radii.sheet),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: Gaps.sm,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.tertiaryFill,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: Gaps.md,
      ),
      labelStyle: TextStyle(color: c.labelSecondary),
      helperStyle: TextStyle(color: c.labelSecondary, fontSize: 13),
      hintStyle: TextStyle(color: c.labelSecondary),
      floatingLabelStyle: TextStyle(color: c.accentPrimary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: c.accentPrimary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: controlSize,
            shape: controlShape,
            textStyle: buttonText,
            backgroundColor: c.accentPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: c.tertiaryFill,
            disabledForegroundColor: c.labelSecondary,
            shadowColor: pressShadow,
            surfaceTintColor: Colors.transparent,
          ).copyWith(
        elevation: pressElevation,
        overlayColor: pressOverlay,
        backgroundBuilder: pressScale,
        animationDuration: const Duration(milliseconds: 90),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: controlSize,
            shape: controlShape,
            textStyle: buttonText,
            side: BorderSide.none,
            backgroundColor: c.accentTint,
            foregroundColor: c.accentPrimary,
            shadowColor: pressShadow,
            surfaceTintColor: Colors.transparent,
          ).copyWith(
        elevation: pressElevation,
        overlayColor: pressOverlay,
        backgroundBuilder: pressScale,
        animationDuration: const Duration(milliseconds: 90),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            minimumSize: controlSize,
            shape: controlShape,
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
            foregroundColor: c.accentPrimary,
          ).copyWith(
        overlayColor: pressOverlay,
        backgroundBuilder: pressScale,
        animationDuration: const Duration(milliseconds: 90),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom().copyWith(
        overlayColor: pressOverlay,
        backgroundBuilder: pressScale,
        animationDuration: const Duration(milliseconds: 90),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.accentSuccess
            : c.tertiaryFill,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accentPrimary,
      circularTrackColor: c.tertiaryFill,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _SoftPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: _SoftPageTransitionsBuilder(),
        TargetPlatform.windows: _SoftPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _SoftPageTransitionsBuilder(),
      },
    ),
  );
}

class _SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

/// Vertical list with consistent 8pt-grid page padding and gaps between children.
class AppList extends StatelessWidget {
  const AppList({super.key, required this.children, this.gap = Gaps.lg});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(Gaps.lg),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
      itemBuilder: (_, index) => children[index],
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: context.apple.accentDangerText));
}

/// One line of the password checklist.
/// Darkens a control only while it is held, then fades the tint away.
class PressFadeFactory extends InteractiveInkFeatureFactory {
  const PressFadeFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _PressFade(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      textDirection: textDirection,
      customBorder: customBorder,
      borderRadius: borderRadius,
      rectCallback: rectCallback,
      onRemoved: onRemoved,
    );
  }
}

class _PressFade extends InteractiveInkFeature {
  _PressFade({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required TextDirection textDirection,
    super.customBorder,
    super.onRemoved,
    BorderRadius? borderRadius,
    RectCallback? rectCallback,
  }) : _borderRadius = borderRadius ?? BorderRadius.zero,
       _textDirection = textDirection,
       _rectCallback = rectCallback {
    _alpha = AnimationController(value: 1, duration: const Duration(milliseconds: 140), vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_onStatus);
    controller.addInkFeature(this);
  }

  final BorderRadius _borderRadius;
  final TextDirection _textDirection;
  final RectCallback? _rectCallback;
  late final AnimationController _alpha;
  bool _released = false;
  bool _disposed = false;

  @override
  void confirm() => _release();

  @override
  void cancel() => _release();

  void _release() {
    if (_released || _disposed) return;
    _released = true;
    if (_alpha.isDismissed) {
      dispose();
    } else {
      _alpha.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && _released) dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _alpha.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final paint = Paint()..color = color.withValues(alpha: color.a * _alpha.value);
    final origin = MatrixUtils.getAsTranslation(transform);
    final rect = _rectCallback != null ? _rectCallback() : Offset.zero & referenceBox.size;
    void draw(Rect target) {
      canvas.save();
      if (customBorder != null) {
        canvas.clipPath(customBorder!.getOuterPath(target, textDirection: _textDirection));
      }
      final radius = _borderRadius.resolve(_textDirection);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          target,
          topLeft: radius.topLeft,
          topRight: radius.topRight,
          bottomLeft: radius.bottomLeft,
          bottomRight: radius.bottomRight,
        ),
        paint,
      );
      canvas.restore();
    }

    if (origin == null) {
      canvas.save();
      canvas.transform(transform.storage);
      draw(rect);
      canvas.restore();
    } else {
      draw(rect.shift(origin));
    }
  }
}

/// Sinks while held so a tap on a custom control is visible.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: reduce
              ? Duration.zero
              : Duration(milliseconds: _down ? 60 : 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.control),
              boxShadow: _down
                  ? const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 1,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 1,
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _down ? 1 : 0,
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 90),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x24000000),
                          borderRadius: BorderRadius.all(Radius.circular(Radii.control)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppleMenuOption<T> {
  const AppleMenuOption(this.value, this.label);
  final T value;
  final String label;
}

/// Filled select control whose menu uses the card, radius, and accent tokens.
class AppleMenuField<T> extends StatefulWidget {
  const AppleMenuField({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String? label;
  final T value;
  final List<AppleMenuOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  State<AppleMenuField<T>> createState() => _AppleMenuFieldState<T>();
}

class _AppleMenuFieldState<T> extends State<AppleMenuField<T>> {
  final _fieldKey = GlobalKey();
  bool _open = false;

  Future<void> _openMenu() async {
    final fieldContext = _fieldKey.currentContext;
    if (fieldContext == null) return;
    final box = fieldContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(fieldContext).context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromRect(
      origin & box.size,
      Offset.zero & overlay.size,
    );
    final apple = fieldContext.apple;
    final labelColor = Theme.of(fieldContext).colorScheme.onSurface;
    setState(() => _open = true);
    final chosen = await showMenu<T>(
      context: fieldContext,
      position: rect,
      color: apple.cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: Theme.of(fieldContext).brightness == Brightness.dark ? 0 : 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: apple.separator, width: 0.5),
      ),
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
        maxHeight: 320,
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: Gaps.xs),
      initialValue: widget.value,
      items: [
        for (final option in widget.options)
          PopupMenuItem<T>(
            value: option.value,
            height: Gaps.hit,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: option.value == widget.value
                    ? apple.accentPrimary
                    : labelColor,
                fontWeight: option.value == widget.value
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize: 17,
              ),
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (chosen != null) widget.onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    final selected = widget.options.firstWhere(
      (option) => option.value == widget.value,
    );
    return Pressable(
      key: _fieldKey,
      label: widget.label,
      onTap: _openMenu,
      child: InputDecorator(
        isEmpty: false,
        isFocused: _open,
        decoration: InputDecoration(labelText: widget.label)
            .applyDefaults(Theme.of(context).inputDecorationTheme),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: apple.labelSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

String formatIsoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatDisplayDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

/// Date of birth control. The stored value is `yyyy-mm-dd`; the field shows a picker.
class AppleDateField extends StatelessWidget {
  const AppleDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.doneLabel,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String doneLabel;

  DateTime _clamp(DateTime date) {
    final now = DateTime.now();
    final min = DateTime(1900, 1, 1);
    final max = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(min)) return min;
    if (day.isAfter(max)) return max;
    return day;
  }

  Future<void> _pick(BuildContext context) async {
    final apple = context.apple;
    final now = DateTime.now();
    final maximum = DateTime(now.year, now.month, now.day);
    var selected = _clamp(
      value ?? DateTime(maximum.year - 25, maximum.month, maximum.day),
    );
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (sheetContext) {
        final onSurface = Theme.of(sheetContext).colorScheme.onSurface;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(sheetContext).brightness,
                    primaryColor: apple.accentPrimary,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: onSurface,
                        fontSize: 21,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: selected,
                    minimumDate: DateTime(1900, 1, 1),
                    maximumDate: maximum,
                    onDateTimeChanged: (next) => selected = next,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gaps.lg,
                  0,
                  Gaps.lg,
                  Gaps.lg,
                ),
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: Text(doneLabel),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) onChanged(_clamp(picked));
  }

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    final text = value == null ? null : formatDisplayDate(value!);
    return Pressable(
      label: label,
      onTap: () => _pick(context),
      child: InputDecorator(
        isEmpty: text == null,
        decoration: InputDecoration(labelText: label)
            .applyDefaults(Theme.of(context).inputDecorationTheme),
        child: Row(
          children: [
            Expanded(
              child: Text(text ?? '', style: const TextStyle(fontSize: 17)),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: apple.labelSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class RuleRow extends StatelessWidget {
  const RuleRow(this.ok, this.label, {super.key});
  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${ok ? '✓' : '○'} $label',
        style: TextStyle(
          color: ok ? apple.accentSuccessText : apple.labelSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// iOS segmented control in the app's tokens. [value] may be null so a
/// choice can start unselected (no silent default).
class AppleSegmented<T extends Object> extends StatelessWidget {
  const AppleSegmented({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.large = false,
  });

  final String? label;
  final T? value;
  final List<AppleMenuOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Full 44pt touch height (for primary choices such as onboarding).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: apple.labelSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: apple.tertiaryFill,
          thumbColor: apple.cardBg,
          children: {
            for (final option in options)
              option.value: Padding(
                padding: EdgeInsets.symmetric(vertical: large ? 11 : 6),
                child: Text(
                  option.label,
                  style: TextStyle(fontSize: large ? 16 : 13),
                ),
              ),
          },
          onValueChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }
}
