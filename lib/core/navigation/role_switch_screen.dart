import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// A sleek transition screen that shows briefly when a user switches roles.
/// It displays a bouncy icon, some text, and then executes the [onComplete] callback.
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

class _RoleSwitchScreenState extends State<RoleSwitchScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Set up a quick pop-and-fade animation for the icon
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Wait a short moment to let the user see the transition, then execute nav callback
    Future.delayed(const Duration(milliseconds: 1400), () {
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
      backgroundColor: AppColors.textPrimary, // Use the Midnight Espresso for a premium theatrical feel
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.targetIcon, size: 80, color: AppColors.primary),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Switching to\n${widget.targetRoleName} View...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 48),
                    const CircularProgressIndicator(color: AppColors.primary),
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
