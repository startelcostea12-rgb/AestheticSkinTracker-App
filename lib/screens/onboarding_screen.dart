import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../app_theme.dart';
import '../utils/app_prefs.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shimmerAnimation;
  late final Animation<double> _logoFadeIn;
  Timer? _autoRouteTimer;
  bool _isRouting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _logoFadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    );
    _startAutoRoute();
  }

  @override
  void dispose() {
    _autoRouteTimer?.cancel();
    _autoRouteTimer = null;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateByProfile() async {
    if (_isRouting) return;
    _isRouting = true;
    _autoRouteTimer?.cancel(); // Cancel timer before navigation
    await AppPrefs.getScanEntries();
    final skinProfileComplete = await AppPrefs.isSkinProfileComplete();
    final tourCompleted = await AppPrefs.isTourCompleted();
    if (!mounted) return;
    if (skinProfileComplete) {
      Navigator.of(
        context,
      ).pushReplacementNamed(tourCompleted ? '/home' : '/welcome-tour');
    } else {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    }
  }

  Future<void> _startAutoRoute() async {
    _autoRouteTimer?.cancel();
    _autoRouteTimer = Timer(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _navigateByProfile();
    });
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = AppColors.warmAlabaster;
    const titleColor = AppColors.refinedSlate;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: _handleBackNavigation,
                icon: const Icon(Icons.arrow_back, color: titleColor),
                tooltip: 'Back',
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.warmAlabaster,
                    AppColors.cardBackground,
                    AppColors.champagneGold.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.20,
                child: CustomPaint(
                  painter: _SplashSwirlPainter(
                    color: AppColors.champagneGold.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoFadeIn,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cardBackground,
                      border: Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.72),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.20,
                          ),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              'assets/logo/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.spa_rounded,
                                color: AppColors.champagneGold,
                                size: 34,
                              ),
                            ),
                          ),
                          // Pearl shimmer handoff from native splash into Flutter UI.
                          AnimatedBuilder(
                            animation: _shimmerAnimation,
                            builder: (context, _) {
                              return IgnorePointer(
                                child: Opacity(
                                  opacity: 0.26,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.0),
                                          Colors.white.withValues(alpha: 0.28),
                                          Colors.white.withValues(alpha: 0.0),
                                        ],
                                        stops: const [0.2, 0.5, 0.8],
                                        begin: Alignment(
                                          -1.4 + _shimmerAnimation.value,
                                          -1,
                                        ),
                                        end: Alignment(
                                          -0.4 + _shimmerAnimation.value,
                                          1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: _shimmerAnimation,
                  builder: (context, child) {
                    return ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: [
                            titleColor.withValues(alpha: 0.6),
                            AppColors.champagneGold.withValues(alpha: 0.8),
                            titleColor.withValues(alpha: 0.6),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                          begin: Alignment(-1 + _shimmerAnimation.value, 0),
                          end: Alignment(1 + _shimmerAnimation.value, 0),
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'AestheticSkinTracker',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Serif',
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Luxury skin progress, guided with care',
                  style: TextStyle(
                    fontFamily: 'Serif',
                    fontSize: 16,
                    color: titleColor.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.champagneGold.withValues(alpha: 0.9),
                    ),
                    backgroundColor: titleColor.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashSwirlPainter extends CustomPainter {
  final Color color;

  const _SplashSwirlPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;

    final center = Offset(size.width * 0.5, size.height * 0.42);
    for (int i = 0; i < 5; i++) {
      final radius = (size.shortestSide * (0.2 + (i * 0.11))).clamp(
        32.0,
        190.0,
      );
      final path = Path();
      for (double deg = 0; deg <= 360; deg += 5) {
        final t = deg * math.pi / 180;
        final wave = math.sin((t * 3.1) + i) * 8;
        final r = radius + wave;
        final x = center.dx + math.cos(t) * r;
        final y = center.dy + math.sin(t) * r;
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
  bool shouldRepaint(covariant _SplashSwirlPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// Placeholder destination after splash

class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clinicController = TextEditingController();
  int _step = 0;
  bool _saving = false;
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmer;
  static const int _totalSteps = 2;

  @override
  void initState() {
    super.initState();
    _restoreStoredSelections();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clinicController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _restoreStoredSelections() async {
    final savedName = await AppPrefs.getUserNameOrNull();
    final savedClinic = await AppPrefs.getUserClinic();
    if (!mounted) return;
    setState(() {
      if (savedName != null && savedName.isNotEmpty) {
        _nameController.text = savedName;
        _step = 1;
      }
      _clinicController.text = savedClinic;
    });
  }

  Future<void> _next() async {
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name to continue.')),
      );
      return;
    }
    if (_step == 0) {
      await AppPrefs.setUserName(_nameController.text.trim());
      if (!mounted) return;
    }
    if (_step < (_totalSteps - 1)) {
      setState(() => _step += 1);
      return;
    }
    await _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    setState(() => _saving = true);
    await AppPrefs.saveOnboarding(
      userName: _nameController.text.trim(),
      procedureType: '',
      ageRange: '',
      skinConcerns: const [],
      clinic: _clinicController.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/welcome-tour', (route) => false);
  }

  Future<void> _skipNameForNow() async {
    await AppPrefs.setUserName(_nameController.text.trim());
    if (!mounted) return;
    setState(() => _step = 1);
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (_step > 0) {
      setState(() => _step -= 1);
      return;
    }
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacementNamed('/home');
  }

  Widget _buildTitle(String text, Color color) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                color,
                AppColors.champagneGold.withValues(alpha: 0.82),
                color,
              ],
              stops: const [0.0, 0.54, 1.0],
              begin: Alignment(-0.8 + (_shimmer.value * 0.6), 0),
              end: Alignment(0.8 + (_shimmer.value * 0.6), 0),
            ).createShader(bounds);
          },
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 31,
              height: 1.08,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'Serif',
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressDots(Color textColor) {
    return Column(
      children: [
        Text(
          'STEP ${_step + 1} OF $_totalSteps',
          style: const TextStyle(
            color: AppColors.champagneGold,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(_totalSteps, (index) {
            final active = index == _step;
            final completed = index < _step;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 28 : 9,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: completed
                    ? AppColors.mutedSage
                    : active
                    ? AppColors.champagneGold
                    : AppColors.refinedSlate.withValues(alpha: 0.16),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEyebrow(String text, IconData icon) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.mutedSage.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.mutedSage.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.mutedSage, size: 15),
            const SizedBox(width: 7),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.mutedSage,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMark() {
    return Center(
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardBackground,
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.45),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.champagneGold.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              'assets/logo/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.spa_rounded,
                color: AppColors.champagneGold,
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportCopy(String text, Color textColor) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: textColor.withValues(alpha: 0.74),
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      style: const TextStyle(
        color: AppColors.refinedSlate,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.champagneGold),
        labelStyle: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.66),
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.42),
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.76),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.champagneGold.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.champagneGold,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSelector() {
    final selectedLocation = _clinicController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Where do you receive your treatments?',
          style: TextStyle(
            color: AppColors.refinedSlate,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildLocationOption(
                icon: Icons.spa_outlined,
                label: 'Medspa / Clinic',
                selected: selectedLocation == 'Medspa / Clinic',
                onTap: () {
                  setState(() => _clinicController.text = 'Medspa / Clinic');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildLocationOption(
                icon: Icons.home_outlined,
                label: 'Home / Other',
                selected: selectedLocation == 'Home / Other',
                onTap: () {
                  setState(() => _clinicController.text = 'Home / Other');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationOption({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = selected ? AppColors.champagneGold : AppColors.mutedSage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.champagneGold.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.champagneGold.withValues(alpha: 0.54)
                : AppColors.mutedSage.withValues(alpha: 0.20),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 13,
                height: 1.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssuranceTile({
    required IconData icon,
    required String title,
    required String body,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: AppColors.refinedSlate.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          transitionBuilder: (child, animation) {
            final slide =
                Tween<Offset>(
                  begin: const Offset(0.0, 0.04),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: SingleChildScrollView(
            key: ValueKey<int>(_step),
            physics: const BouncingScrollPhysics(),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool shimmer,
  }) {
    Widget buttonFor(Gradient? gradient) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: gradient == null
                ? AppColors.champagneGold
                : Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: AppColors.onChampagneGold,
            disabledBackgroundColor: AppColors.champagneGold.withValues(
              alpha: 0.42,
            ),
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    if (!shimmer) return buttonFor(null);
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        return buttonFor(
          LinearGradient(
            colors: const [
              AppColors.champagneGold,
              AppColors.goldHover,
              AppColors.champagneGold,
            ],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1 + _shimmer.value, 0),
            end: Alignment(1 + _shimmer.value, 0),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;

    Widget content;
    if (_step == 0) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroMark(),
          const SizedBox(height: 22),
          _buildEyebrow('Personal glow plan', Icons.spa_outlined),
          const SizedBox(height: 18),
          _buildTitle("Let's personalize your skin journey", textColor),
          const SizedBox(height: 14),
          _buildSupportCopy(
            'Tell us what to call you so every check-in feels calm, clear, and made for you.',
            textColor,
          ),
          const SizedBox(height: 28),
          _buildTextField(
            controller: _nameController,
            label: 'Preferred name',
            hint: 'Enter your first name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 18),
          _buildAssuranceTile(
            icon: Icons.lock_outline,
            title: 'Private by design',
            body:
                'Your profile helps personalize the experience while keeping the flow simple.',
            accent: AppColors.mutedSage,
          ),
        ],
      );
    } else if (_step == 1) {
      final displayName = _nameController.text.trim().isEmpty
          ? 'there'
          : _nameController.text.trim();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroMark(),
          const SizedBox(height: 22),
          _buildEyebrow('Ready for your ritual', Icons.check_circle_outline),
          const SizedBox(height: 18),
          _buildTitle('Your calm progress ritual is ready', textColor),
          const SizedBox(height: 14),
          _buildSupportCopy(
            'Welcome, $displayName. Choose your care setting so your progress space feels tailored from the start, with free tracking now and optional Premium analysis later.',
            textColor,
          ),
          const SizedBox(height: 24),
          _buildLocationSelector(),
          const SizedBox(height: 18),
          _buildAssuranceTile(
            icon: Icons.auto_awesome_outlined,
            title: 'Premium tracking, softly guided',
            body:
                'Start with a fresh photo, then unlock deeper AI analysis, richer scan history, and clearer progress summaries whenever you are ready.',
            accent: AppColors.champagneGold,
          ),
          const SizedBox(height: 12),
          _buildAssuranceTile(
            icon: Icons.eco_outlined,
            title: 'Supportive progress cues',
            body:
                'Gentle highlights help you notice positive change without turning self-care into pressure.',
            accent: AppColors.mutedSage,
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitle('Your calm progress ritual is ready', textColor),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.warmAlabaster,
                      AppColors.cardBackground,
                      AppColors.champagneGold.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _handleBackNavigation,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardBackground,
                          foregroundColor: AppColors.refinedSlate,
                          side: BorderSide(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'AestheticSkinTracker',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.58),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildProgressDots(textColor),
                  const SizedBox(height: 24),
                  Expanded(child: _buildStepCard(child: content)),
                  const SizedBox(height: 18),
                  if (_step == 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _saving ? null : _skipNameForNow,
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.64),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: textColor.withValues(alpha: 0.34),
                          ),
                        ),
                      ),
                    ),
                  _buildPrimaryButton(
                    label: _step == (_totalSteps - 1)
                        ? 'Begin My Journey'
                        : 'Continue',
                    onPressed: _saving
                        ? null
                        : _step == (_totalSteps - 1)
                        ? _completeOnboarding
                        : _next,
                    shimmer: _step == (_totalSteps - 1),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(color: AppColors.mutedSage),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// camera screen added below
