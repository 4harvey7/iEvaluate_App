import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
    this.pressedScale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
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
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
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
    final bool useBlur = !highContrast &&
        defaultTargetPlatform == TargetPlatform.iOS;

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
    if (!useBlur) return surface; // Android / high-contrast: no blur, fully opaque
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
        if (action != null) action!,
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
    // Same as AppleGlass: disable blur on Android to prevent see-through.
    final bool useBlur = !highContrast &&
        defaultTargetPlatform == TargetPlatform.iOS;

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
                colors: [AppColors.glassStrong, AppColors.glass],
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
    final material = !useBlur
        ? surface
        : ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: surface,
            ),
          );
    if (onTap == null) return material;
    return ApplePressable(onTap: onTap, child: material);
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

class AppleLoadingState extends StatelessWidget {
  const AppleLoadingState({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}

class AppleSearchField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textTertiary,
        ),
        filled: true,
        fillColor: AppColors.surface,
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
                child: ApplePressable(
                  semanticLabel: item.label,
                  onTap: () => onSelected(index),
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
              );
            }),
          ),
        ),
      ),
    );
  }
}
