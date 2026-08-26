import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// A brief, spatially calm handoff between roles.
class RoleSwitchScreen extends StatefulWidget {
  final String targetRoleName;
  final IconData targetIcon;

  /// What to do when the animation finishes (e.g., Navigator.push or pop).
  /// We pass the current BuildContext so the callback can navigate properly.
  final void Function(BuildContext context) onComplete;

  const RoleSwitchScreen({
    super.key,
    required this.targetRoleName,
    required this.targetIcon,
    required this.onComplete,
  });

  @override
  State<RoleSwitchScreen> createState() => _RoleSwitchScreenState();
}

class _RoleSwitchScreenState extends State<RoleSwitchScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Wait a short moment to let the user see the transition, then execute nav callback
    Future.delayed(const Duration(milliseconds: 760), () {
      if (mounted) {
        widget.onComplete(context);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDeep,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            return Opacity(
              opacity: reduceMotion ? 1 : _fadeAnimation.value,
              child: Transform.scale(
                scale: reduceMotion ? 1 : _scaleAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.textInvertedFaint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.targetIcon,
                        size: 72,
                        color: AppColors.textInverted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Switching to\n${widget.targetRoleName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 48),
                    const SizedBox(
                      width: 88,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: AppColors.textInverted,
                        backgroundColor: AppColors.textInvertedFaint,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
