import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_brand.dart';
import 'auth_page.dart';

/// First-launch introduction shown once, between the splash screen and sign-in
/// (see SplashPage._routeNext). Auto-advances on a timer but stays swipeable,
/// and a manual swipe restarts the timer so it doesn't fight the gesture.
class OnboardingCarouselPage extends StatefulWidget {
  const OnboardingCarouselPage({super.key});

  // Versioned so a future content overhaul can force it to show again by
  // bumping to _v2, matching the convention already used for
  // face_scan_capture_instructions_seen_v2 in FaceScanService.
  static const String _seenKey = 'has_seen_onboarding_v1';

  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  static Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  @override
  State<OnboardingCarouselPage> createState() => _OnboardingCarouselPageState();
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingSlide({required this.icon, required this.title, required this.body});
}

class _OnboardingCarouselPageState extends State<OnboardingCarouselPage> {
  static const _slides = [
    _OnboardingSlide(
      icon: Icons.face_retouching_natural,
      title: 'Meet Brilliante',
      body: 'Try on hairstyles with AI before you ever sit in the chair.',
    ),
    _OnboardingSlide(
      icon: Icons.center_focus_weak,
      title: 'See it before you get it',
      body: 'Scan your face, preview styles, and compare side by side.',
    ),
    _OnboardingSlide(
      icon: Icons.event_available,
      title: 'Book with your barber',
      body: 'Pick a barber, a time slot, pay, and you\'re set.',
    ),
    _OnboardingSlide(
      icon: Icons.shield_outlined,
      title: 'Your data, your control',
      body: 'Your scan photos power the preview. Full terms are shown when you sign up.',
    ),
  ];

  static const _autoAdvanceInterval = Duration(seconds: 4);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scheduleAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAutoAdvance() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoAdvanceInterval, (_) {
      if (!mounted) return;
      final next = (_page + 1) % _slides.length;
      _controller.animateToPage(next, duration: AppBrand.medium, curve: AppBrand.ease);
    });
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    // A manual swipe lands here too, so restart the timer from zero instead
    // of letting it fire moments after the user just chose a slide.
    _scheduleAutoAdvance();
  }

  Future<void> _finish() async {
    await OnboardingCarouselPage.markOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  void _goToNext() {
    if (_page >= _slides.length - 1) {
      unawaited(_finish());
      return;
    }
    _controller.animateToPage(_page + 1, duration: AppBrand.medium, curve: AppBrand.ease);
  }

  @override
  Widget build(BuildContext context) {
    final isLastSlide = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppBrand.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: AppBrand.s2, top: AppBrand.s1),
                child: TextButton(
                  onPressed: () => unawaited(_finish()),
                  child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _slideView(_slides[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppBrand.s5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  final active = index == _page;
                  return AnimatedContainer(
                    duration: AppBrand.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? AppBrand.accent : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppBrand.s6, 0, AppBrand.s6, AppBrand.s6),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToNext,
                  style: AppBrand.primaryButton,
                  child: Text(
                    isLastSlide ? 'Get Started' : 'Next',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideView(_OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppBrand.s7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppBrand.accentTint,
              shape: BoxShape.circle,
              border: Border.all(color: AppBrand.accentLine),
            ),
            alignment: Alignment.center,
            child: Icon(slide.icon, color: AppBrand.accent, size: 44),
          ),
          const SizedBox(height: AppBrand.s6),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppBrand.s3),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
