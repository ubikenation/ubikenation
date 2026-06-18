import 'package:flutter/material.dart';

/// Bolt/Uber-style animated launch screen: the logo scales up and fades in with
/// a subtle overshoot, holds briefly, then cross-fades into the app.
class AnimatedSplash extends StatefulWidget {
  const AnimatedSplash({super.key, required this.next});
  final Widget next;

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fade = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.6, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.72, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    _c.forward();
    _goNext();
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset('assets/logo.png', width: 240, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
