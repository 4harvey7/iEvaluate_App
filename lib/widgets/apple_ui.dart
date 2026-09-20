import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A calm, fixed field of color behind every route. Translucent page and
/// content materials pick up these hues, producing depth without moving the
/// background or competing with data.
class AppleAmbientBackground extends StatelessWidget {
  const AppleAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    return ColoredBox(
      color: highContrast ? AppColors.solidSurface : const Color(0xFFF2F7FD),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!highContrast) ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.ambientGradient,
                ),
              ),
            ),
            const Positioned(
              top: -170,
              right: -130,
              width: 430,
              height: 430,
              child: _AmbientOrb(color: AppColors.accent),
            ),
            const Positioned(
              top: 360,
              left: -210,
              width: 470,
              height: 470,
              child: _AmbientOrb(color: AppColors.primary),
            ),
            const Positioned(
              bottom: -190,
              right: -170,
              width: 460,
              height: 460,
              child: _AmbientOrb(color: AppColors.purple),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.18), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// A press interaction that responds on pointer-down and settles from its
/// current presentation value, so interrupted touches never jump.
class ApplePressable extends StatefulWidget {
  const ApplePressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled,
    this.pressedScale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Set this when the child owns the tap callback (for example, a Button).
  /// The wrapper will still provide immediate pointer-down feedback without
  /// stealing the child's gesture or adding duplicate button semantics.
  final bool? enabled;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<ApplePressable> createState() => _ApplePressableState();
}

class _ApplePressableState extends State<ApplePressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _settle(double target) {
    if (_reduceMotion) {
      _scale.value = target;
      return;
    }
    _scale.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 520, damping: 38),
        _scale.value,
        target,
        _scale.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled ?? widget.onTap != null;
    return Semantics(
      button: widget.onTap != null,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Listener(
          onPointerDown: enabled ? (_) => _settle(widget.pressedScale) : null,
          onPointerUp: enabled ? (_) => _settle(1) : null,
          onPointerCancel: enabled ? (_) => _settle(1) : null,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A quiet entrance for newly mounted content. It deliberately avoids
/// overshoot: passive motion should orient, not demand attention.
class AppleEntrance extends StatelessWidget {
  const AppleEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 420 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        final progress = delay == Duration.zero
            ? value
            : ((value * (420 + delay.inMilliseconds) - delay.inMilliseconds) /
                      420)
                  .clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A translucent material with an opaque high-contrast equivalent.
class AppleGlass extends StatelessWidget {
  const AppleGlass({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;

    // On Android (Impeller/Vulkan), BackdropFilter can show content from the
    // PREVIOUS ROUTE through the blur, making text unreadable. Disable it on
    // Android and let the opaque gradient background do the visual work instead.
    // iOS keeps the full blur for the authentic glass look.
    final bool useBlur =
        !highContrast && defaultTargetPlatform == TargetPlatform.iOS;

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highContrast
            ? AppColors.solidSurface
            : (useBlur ? null : AppColors.glassStrong), // solid on Android
        gradient: (highContrast || !useBlur)
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.glassStrong, AppColors.glassSubtle],
              ),
        borderRadius: borderRadius,
        border: Border.all(
          color: highContrast ? AppColors.textSecondary : AppColors.glassBorder,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
    if (!useBlur) {
      return surface; // Android / high-contrast: no blur, fully opaque
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: surface,
      ),
    );
  }
}

/// Consistent large-title wayfinding for every first-level screen.
class ApplePageHeader extends StatelessWidget {
  const ApplePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppleGlass(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(title, style: AppTextStyles.displayMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

class AppleSectionHeader extends StatelessWidget {
  const AppleSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: AppTextStyles.bodySmall),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

/// The standard opaque content layer. Glass is reserved for floating chrome.
class AppleSurface extends StatelessWidget {
  const AppleSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        // Content cards stay opaque. Glass is reserved for floating chrome;
        // blurring every nested card hurts legibility and GPU performance.
        color: highContrast ? AppColors.solidSurface : null,
        gradient: highContrast
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
              ),
        borderRadius: borderRadius,
        border: Border.all(
          color: highContrast ? AppColors.textSecondary : AppColors.glassBorder,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return surface;
    return ApplePressable(onTap: onTap, child: surface);
  }
}

class AppleIconBadge extends StatelessWidget {
  const AppleIconBadge({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class AppleMetricCard extends StatelessWidget {
  const AppleMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
    this.detail,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppleSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppleIconBadge(icon: icon, color: color),
          const SizedBox(height: 18),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.displaySmall,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall,
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

class AppleStatusPill extends StatelessWidget {
  const AppleStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, color: color, size: icon == null ? 7 : 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppleEmptyState extends StatelessWidget {
  const AppleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppleSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            AppleIconBadge(icon: icon, size: 54),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// A structural loading preview inspired by iOS content placeholders. It keeps
/// the page hierarchy visible while data loads, so content resolves in place
/// instead of appearing after an empty spinner.
class AppleLoadingState extends StatefulWidget {
  const AppleLoadingState({super.key, this.label = 'Loading…'});

  final String label;

  @override
  State<AppleLoadingState> createState() => _AppleLoadingStateState();
}

class _AppleLoadingStateState extends State<AppleLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion &&
        (_shimmer.isAnimating || reduceMotion)) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _shimmer.stop();
      _shimmer.value = 0.5;
    } else {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 88),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _shimmer,
                          builder: (context, child) {
                            if (_reduceMotion || highContrast) return child!;
                            final position = -1.6 + (_shimmer.value * 3.2);
                            return ShaderMask(
                              blendMode: BlendMode.srcATop,
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment(position - 1, 0),
                                end: Alignment(position + 1, 0),
                                colors: const [
                                  Color(0xFFDDE4EC),
                                  Color(0xFFF7FAFD),
                                  Color(0xFFDDE4EC),
                                ],
                                stops: const [0.25, 0.5, 0.75],
                              ).createShader(bounds),
                              child: child,
                            );
                          },
                          child: _AppleSkeletonLayout(
                            highContrast: highContrast,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AppleSkeletonLayout extends StatelessWidget {
  const _AppleSkeletonLayout({required this.highContrast});

  final bool highContrast;

  Color get _placeholderColor =>
      highContrast ? const Color(0xFF667085) : const Color(0xFFDDE4EC);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _AppleSkeletonBlock(
              width: 44,
              height: 44,
              radius: 14,
              color: _placeholderColor,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppleSkeletonLine(
                    widthFactor: 0.42,
                    height: 12,
                    color: _placeholderColor,
                  ),
                  const SizedBox(height: 9),
                  _AppleSkeletonLine(
                    widthFactor: 0.68,
                    height: 9,
                    color: _placeholderColor,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _AppleSkeletonBlock(
              width: 32,
              height: 32,
              radius: 10,
              color: _placeholderColor,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _AppleSkeletonPanel(
          height: 112,
          color: _placeholderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AppleSkeletonLine(
                widthFactor: 0.30,
                height: 10,
                color: _placeholderColor,
              ),
              const SizedBox(height: 12),
              _AppleSkeletonLine(
                widthFactor: 0.72,
                height: 18,
                color: _placeholderColor,
              ),
              const SizedBox(height: 10),
              _AppleSkeletonLine(
                widthFactor: 0.48,
                height: 9,
                color: _placeholderColor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < 3; index++) ...[
          _AppleSkeletonPanel(
            height: 88,
            color: _placeholderColor,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AppleSkeletonLine(
                        widthFactor: 0.34 + (index * 0.08),
                        height: 11,
                        color: _placeholderColor,
                      ),
                      const SizedBox(height: 10),
                      _AppleSkeletonLine(
                        widthFactor: 0.68 - (index * 0.06),
                        height: 9,
                        color: _placeholderColor,
                      ),
                      const SizedBox(height: 8),
                      _AppleSkeletonLine(
                        widthFactor: 0.48 + (index * 0.05),
                        height: 8,
                        color: _placeholderColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                _AppleSkeletonBlock(
                  width: 64,
                  height: 58,
                  radius: 13,
                  color: _placeholderColor,
                ),
              ],
            ),
          ),
          if (index != 2) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AppleSkeletonPanel extends StatelessWidget {
  const _AppleSkeletonPanel({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.solidSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F173B63),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AppleSkeletonLine extends StatelessWidget {
  const _AppleSkeletonLine({
    required this.widthFactor,
    required this.height,
    required this.color,
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: _AppleSkeletonBlock(
        width: double.infinity,
        height: height,
        radius: height / 2,
        color: color,
      ),
    );
  }
}

class _AppleSkeletonBlock extends StatelessWidget {
  const _AppleSkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class AppleSearchField extends StatefulWidget {
  const AppleSearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'Search',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  @override
  State<AppleSearchField> createState() => _AppleSearchFieldState();
}

class _AppleSearchFieldState extends State<AppleSearchField> {
  TextEditingController? _internalController;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AppleSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_refresh);
      widget.controller?.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_refresh);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        setState(() {});
        widget.onChanged?.call(value);
      },
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textTertiary,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : ApplePressable(
                semanticLabel: 'Clear search',
                onTap: _clear,
                pressedScale: 0.90,
                child: const Icon(
                  Icons.cancel_rounded,
                  color: AppColors.textTertiary,
                ),
              ),
        filled: true,
        fillColor: AppColors.solidSurface,
      ),
    );
  }
}

class AppleTabItem {
  const AppleTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating navigation that keeps content spatially stable while providing
/// immediate tactile-looking feedback on selection.
class AppleFloatingTabBar extends StatelessWidget {
  const AppleFloatingTabBar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<AppleTabItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 64,
        child: AppleGlass(
          padding: const EdgeInsets.all(5),
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              // selectedIndex == -1 means a drawer screen is active → no tab highlighted
              final selected = selectedIndex >= 0 && index == selectedIndex;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  child: ApplePressable(
                    semanticLabel: item.label,
                    onTap: () {
                      if (!selected) HapticFeedback.selectionClick();
                      onSelected(index);
                    },
                    child: AnimatedContainer(
                      height: 54,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryTint
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected ? item.selectedIcon : item.icon,
                            size: 21,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
