import 'package:flutter/material.dart';
import 'dart:ui';
import 'auth_page.dart';

class HeroPage extends StatefulWidget {
  const HeroPage({super.key});

  @override
  State<HeroPage> createState() => _HeroPageState();
}

class _HeroPageState extends State<HeroPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  int _currentImageIndex = 0;
  
  final List<String> _heroImages = [
    'assets/images/jeo_front.jpg',
    'assets/images/amazing_hair.jpg',
    'assets/images/tatishaircut.jpg',
    'assets/images/mordern_fade.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    
    // Auto-rotate images
    Future.delayed(const Duration(seconds: 3), _rotateImages);
  }
  
  void _rotateImages() {
    if (mounted) {
      setState(() {
        _currentImageIndex = (_currentImageIndex + 1) % _heroImages.length;
      });
      Future.delayed(const Duration(seconds: 3), _rotateImages);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated Background
          _buildAnimatedBackground(),
          
          // Main Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHeroSection(context),
                        _buildFeaturesSection(),
                        _buildGallerySection(),
                        _buildStatsSection(),
                        _buildCallToAction(context),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1000),
      child: Container(
        key: ValueKey<int>(_currentImageIndex),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_heroImages[_currentImageIndex]),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.black.withOpacity(0.9),
                Colors.black,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
              color: const Color(0xFF3a3a3a).withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Logo
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3a3a3a),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Image.asset(
                      'assets/images/TATIS.png',
                      height: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TATIS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'BARBERSHOP',
                          style: TextStyle(
                            color: Color(0xFF3a3a3a),
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Navigation Buttons - Compact for mobile
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPrimaryButton(
                  context,
                  'SIGN IN',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                  ),
                  isOutlined: true,
                  compact: true,
                ),
                const SizedBox(width: 6),
                _buildPrimaryButton(
                  context,
                  'BOOK',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                  ),
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton(BuildContext context, String text, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(BuildContext context, String text, VoidCallback onPressed, {bool isOutlined = false, bool compact = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : const Color(0xFF3a3a3a),
        foregroundColor: Colors.white,
        side: isOutlined ? const BorderSide(color: Color(0xFF3a3a3a), width: 2) : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 24, 
          vertical: compact ? 8 : 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: isOutlined ? 0 : 8,
        shadowColor: const Color(0xFF3a3a3a).withOpacity(0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 20 : 40, 
          vertical: isSmallScreen ? 60 : 100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main Headline
            Text(
              'ELEVATE YOUR',
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallScreen ? 36 : 72,
                fontWeight: FontWeight.w900,
                height: 1.1,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF3a3a3a), Color(0xFF5a5a5a)],
              ).createShader(bounds),
              child: Text(
                'STYLE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 48 : 96,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Subheadline
            Container(
              constraints: BoxConstraints(maxWidth: isSmallScreen ? double.infinity : 600),
              child: Text(
                'Experience premium grooming with AI-powered precision. Where tradition meets innovation for the perfect cut.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: isSmallScreen ? 14 : 18,
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // CTA Buttons
            isSmallScreen
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLargeButton(
                        'BOOK APPOINTMENT',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthPage()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildLargeButton(
                        'EXPLORE STYLES',
                        () {},
                        isSecondary: true,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _buildLargeButton(
                        'BOOK APPOINTMENT',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthPage()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildLargeButton(
                        'EXPLORE STYLES',
                        () {},
                        isSecondary: true,
                      ),
                    ],
                  ),
            
            const SizedBox(height: 40),
            
            // Quick Stats
            Wrap(
              spacing: isSmallScreen ? 30 : 60,
              runSpacing: 20,
              children: [
                
                _buildStatItem('5', 'Expert Barbers'),
                _buildStatItem('AI', 'Powered'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeButton(String text, VoidCallback onPressed, {bool isSecondary = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSecondary ? Colors.white : const Color(0xFF3a3a3a),
        foregroundColor: isSecondary ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 12,
        shadowColor: (isSecondary ? Colors.white : const Color(0xFF3a3a3a)).withOpacity(0.6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF3a3a3a),
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      color: Colors.white,
      child: Column(
        children: [
          const Text(
            'WHY CHOOSE TATIS',
            style: TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Premium Services',
            style: TextStyle(
              color: Colors.black,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 40),
          
          // Make responsive - single column on mobile
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 800) {
                return Column(
                  children: [
                    _buildFeatureCard(
                      Icons.auto_awesome,
                      'AI-Powered',
                      'Advanced AI technology recommends the perfect hairstyle for your face shape and preferences.',
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureCard(
                      Icons.verified_user,
                      'Expert Barbers',
                      'Our certified professionals bring years of experience and passion to every cut.',
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureCard(
                      Icons.schedule,
                      'Easy Booking',
                      'Book your appointment online in seconds. Choose your time, barber, and service.',
                    ),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Expanded(
                      child: _buildFeatureCard(
                        Icons.auto_awesome,
                        'AI-Powered',
                        'Advanced AI technology recommends the perfect hairstyle for your face shape and preferences.',
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _buildFeatureCard(
                        Icons.verified_user,
                        'Expert Barbers',
                        'Our certified professionals bring years of experience and passion to every cut.',
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _buildFeatureCard(
                        Icons.schedule,
                        'Easy Booking',
                        'Book your appointment online in seconds. Choose your time, barber, and service.',
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3a3a3a),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGallerySection() {
    final images = [
      'assets/images/jeo_front.jpg',
      'assets/images/amazing_hair.jpg',
      'assets/images/tatishaircut.jpg',
      'assets/images/mordern_fade.jpg',
      'assets/images/jeoleft.jpg',
      'assets/images/kids_cut.jpg',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80),
      color: Colors.black,
      child: Column(
        children: [
          const Text(
            'OUR WORK',
            style: TextStyle(
              color: Color(0xFF3a3a3a),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Style Gallery',
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 60),
          
          SizedBox(
            height: 400,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 40),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: _buildGalleryItem(images[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryItem(String imagePath) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3a3a3a).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              imagePath,
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 80),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3a3a3a),
            const Color(0xFF5a5a5a),
          ],
        ),
      ),
      child: Column(
        children: [
          // AI Icon
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 48,
              color: Color(0xFF3a3a3a),
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Quote Text
          Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: const Column(
              children: [
                Text(
                  '"',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    height: 0.5,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Our AI technology analyzes your unique facial features, hair type, and personal style to recommend the perfect cut that enhances your natural look.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    height: 1.6,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'DESIGNED BY AI, PERFECTED FOR YOU',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallToAction(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      color: Colors.white,
      child: Center(
        child: Column(
          children: [
            const Text(
              'READY FOR A CHANGE?',
              style: TextStyle(
                color: Color(0xFF3a3a3a),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Book Your Appointment Today',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Experience the difference of premium grooming',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuthPage()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3a3a3a),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 12,
                shadowColor: const Color(0xFF3a3a3a).withOpacity(0.6),
              ),
              child: const Text(
                'GET STARTED NOW',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      color: Colors.black,
      child: Column(
        children: [
          // Simplified footer for mobile
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3a3a3a),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Image.asset(
                      'assets/images/TATIS.png',
                      height: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'TATIS BARBERSHOP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Premium grooming since 2020',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 30),
          
          Text(
            '© 2026 Tatis Barbershop. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 14,
        ),
      ),
    );
  }
}
