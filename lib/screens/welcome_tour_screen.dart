import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';

class WelcomeTourScreen extends StatefulWidget {
  const WelcomeTourScreen({super.key});

  @override
  State<WelcomeTourScreen> createState() => _WelcomeTourScreenState();
}

class _WelcomeTourScreenState extends State<WelcomeTourScreen>
    with TickerProviderStateMixin {
  static const String _videoAsset = 'assets/videos/onboarding_intro.mp4';

  VideoPlayerController? _videoController;
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmer;
  Timer? _captionTimer;
  int _currentIndex = 0;
  bool _videoReady = false;
  String? _videoError;

  final List<_TourCaption> _captions = const [
    _TourCaption(
      title: "Track Your Skin's True Transformation",
      subtitle:
          'A refined progress ritual for every treatment, photo, and glow milestone.',
    ),
    _TourCaption(
      title: 'AI-Powered Scans & Progress Insights',
      subtitle:
          'Notice meaningful changes with calm, guided analysis that keeps your journey clear.',
    ),
    _TourCaption(
      title: 'Log Procedures with Precision',
      subtitle:
          'Organize treatments, recovery notes, and care moments in one polished timeline.',
    ),
    _TourCaption(
      title: 'Your Luxe Clinical Journey Starts Here',
      subtitle:
          'Step into a premium space designed for clarity, confidence, and beautiful continuity.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
    _initializeVideo();
    _startCaptionCycle();
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.asset(_videoAsset);
    _videoController = controller;

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _videoReady = true;
        _videoError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoReady = false;
        _videoError = 'Intro video is unavailable.';
      });
    }
  }

  void _startCaptionCycle() {
    _captionTimer?.cancel();
    _captionTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _currentIndex = (_currentIndex + 1) % _captions.length);
    });
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    _videoController?.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _finishTour() async {
    final skinProfileComplete = await AppPrefs.isSkinProfileComplete();
    if (!mounted) return;
    if (!skinProfileComplete) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
      return;
    }

    await AppPrefs.setTourCompleted(true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoLayer(),
          _buildLuxeAtmosphere(),
          _buildBottomReadabilityGradient(),
          if (!_videoReady) _buildVideoStatusOverlay(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _SkipButton(onPressed: _finishTour),
                  ),
                  const Spacer(),
                  _buildCaptionOverlay(),
                  const SizedBox(height: 30),
                  _buildGetStartedButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoLayer() {
    final controller = _videoController;
    if (!_videoReady || controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: AppColors.warmAlabaster);
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildLuxeAtmosphere() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.warmAlabaster.withValues(alpha: 0.18),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ConcentricLuxePainter(
                color: AppColors.champagneGold.withValues(alpha: 0.24),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomReadabilityGradient() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Color(0x332C3539), Color(0xCC101412)],
          stops: [0.42, 0.68, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _buildCaptionOverlay() {
    final caption = _captions[_currentIndex];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 620),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Column(
        key: ValueKey<int>(_currentIndex),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.34),
              ),
            ),
            child: const Text(
              'AestheticSkinTracker',
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            caption.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Serif',
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.08,
              shadows: [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              caption.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 15.5,
                height: 1.42,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 16,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildCaptionDots(),
        ],
      ),
    );
  }

  Widget _buildCaptionDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_captions.length, (index) {
        final active = index == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: active ? 26 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.champagneGold
                : AppColors.cardBackground.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _buildGetStartedButton() {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: const [
                AppColors.champagneGold,
                AppColors.goldHover,
                AppColors.champagneGold,
              ],
              begin: Alignment(-1 + _shimmer.value, 0),
              end: Alignment(1 + _shimmer.value, 0),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.champagneGold.withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _finishTour,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: AppColors.onChampagneGold,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text(
              'Get Started',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoStatusOverlay() {
    return ColoredBox(
      color: AppColors.warmAlabaster,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _ConcentricLuxePainter(
              color: AppColors.champagneGold.withValues(alpha: 0.18),
            ),
          ),
          Center(
            child: _videoError == null
                ? const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      color: AppColors.champagneGold,
                      strokeWidth: 2.4,
                    ),
                  )
                : _VideoErrorCard(message: _videoError!),
          ),
        ],
      ),
    );
  }
}

class _TourCaption {
  final String title;
  final String subtitle;

  const _TourCaption({required this.title, required this.subtitle});
}

class _SkipButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SkipButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.refinedSlate,
        backgroundColor: AppColors.cardBackground.withValues(alpha: 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: AppColors.champagneGold.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Text(
        'Skip',
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VideoErrorCard extends StatelessWidget {
  final String message;

  const _VideoErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.play_circle_outline,
              color: AppColors.champagneGold,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add assets/videos/onboarding_intro.mp4 to enable the full intro video.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.64),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcentricLuxePainter extends CustomPainter {
  final Color color;

  const _ConcentricLuxePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final center = Offset(size.width * 0.5, size.height * 0.44);

    for (int i = 0; i < 6; i++) {
      final radius = (size.shortestSide * (0.18 + (i * 0.095))).clamp(
        34.0,
        230.0,
      );
      final path = Path();
      for (double deg = 0; deg <= 360; deg += 4) {
        final t = deg * math.pi / 180;
        final wave = math.sin((t * 3.0) + i) * 7;
        final x = center.dx + math.cos(t) * (radius + wave);
        final y = center.dy + math.sin(t) * (radius + wave);
        if (deg == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricLuxePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
