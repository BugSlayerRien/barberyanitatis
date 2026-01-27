import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'user/auth_page.dart';
import 'user/splash_page.dart';

// --- 1. Define Custom Colors ---
const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBlackColor = Color(0xFF111111);
const Color kOrangeColor = Color(0xFFF37022);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Allow app to start even if Firebase isn't configured yet.
  }
  runApp(const TatisBarbershopApp());
}

// The main application widget (MaterialApp shell)
class TatisBarbershopApp extends StatelessWidget {
  const TatisBarbershopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.dark().textTheme.apply(fontFamily: 'CenturyGothic');
    return MaterialApp(
      title: 'Tatis Barbershop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'CenturyGothic',
        textTheme: baseTextTheme.copyWith(
          titleSmall: GoogleFonts.montserrat(textStyle: baseTextTheme.titleSmall),
          titleMedium: GoogleFonts.montserrat(textStyle: baseTextTheme.titleMedium),
          titleLarge: GoogleFonts.montserrat(textStyle: baseTextTheme.titleLarge),
          labelSmall: GoogleFonts.montserrat(textStyle: baseTextTheme.labelSmall),
          labelMedium: GoogleFonts.montserrat(textStyle: baseTextTheme.labelMedium),
          labelLarge: GoogleFonts.montserrat(textStyle: baseTextTheme.labelLarge),
        ),
      ),
      home: const SplashPage(),
    );
  }
}


// --- 2. BarbershopDashboardContent Widget (The UI Container) ---
class BarbershopDashboardContent extends StatelessWidget {
  const BarbershopDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Main background color
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // --- 1. Header with Logo and Buttons ---
            _buildHeader(context),
            const SizedBox(height: 50),

            // --- 2. Premium Grooming Experience Section ---
            _buildPremiumGroomingSection(),
            const SizedBox(height: 50),

            // --- 3. Powered by AI Section ---
            _buildAIPoweredSection(context),
            const SizedBox(height: 50),

            // --- 4. Our Premium & Exclusive Services Section (INTERACTIVE) ---
            _buildServicesSection(),
            const SizedBox(height: 50),
            
            // NOTE: The problematic About Section is REMOVED here to ensure compilation.
            
          ],
        ),
      ),
    );
  }

  // --- 2.1. Header Widget ---
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // Logo and Barbershop Name
          Row(
            children: <Widget>[
              // Tatis Logo (FIXED PATH: using TATIS.png)
              Image.asset(
                'assets/images/TATIS.png', 
                height: 30, 
                color: Colors.white, 
              ),
              const SizedBox(width: 8),
              const Text(
                'BARBERYA NI TATIS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          // Login and Book Now Buttons
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () {
                  // Open login screen
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthPage()));
                },
                child: const Text('SIGN IN', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  // Book Now should require login for now — open login screen
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthPage()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGoldColor, 
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                child: const Text('BOOK NOW', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 2.2. Premium Grooming Section Widget ---
  Widget _buildPremiumGroomingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Render each word on its own line to avoid unexpected wrapping
                    const Text(
                      'PREMIUM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'GROOMING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'EXPERIENCE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Logo and text in a row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Image.asset(
                          'assets/images/TATIS.png',
                          height: 40,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Where traditional craftsmanship meets modern style. Experience the art of '
                            'barbering with precision and passion.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 2.3. AI Powered Section Widget ---
  Widget _buildAIPoweredSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'POWERED BY AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Where traditional craftsmanship meets modern style. Experience the art of '
                  'barbering with precision and passion.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                // AI Haircut Recommendation Card
                _buildAICard(context),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Placeholder for the large B&W Barbershop Image
          const Expanded(
            flex: 1,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack( // Using Stack here for the EXCLUSIVE text overlay
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        image: DecorationImage(
                          image: AssetImage('assets/images/tatishaircut.jpg'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: kGoldColor,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: Text(
                          'EXCLUSIVE\nFOR YOU',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget for AI Recommendation Card (FIXED IMAGE PATH/TITLE)
  Widget _buildAICard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: kDarkBlackColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // --- Image Container (UPDATED TO USE JEO IMAGE) ---
          Container(
            height: 120,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              image: DecorationImage(
                image: AssetImage('assets/images/jeo ai haircut.jpg'), // <-- THE FIX
                fit: BoxFit.cover,
              ),
            ),
          ),
          // ---------------------------------
          const SizedBox(height: 10),
          // CORRECTED TITLE
          const Text('Modern Mullet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), // <-- THE FIX
          const Text('Digital Scalp Analysis, 98% Match', style: TextStyle(color: kGoldColor, fontSize: 12)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  // Require login before trying AI simulator — open login page
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthPage()));
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kGoldColor),
                  foregroundColor: kGoldColor,
                ),
                child: const Text('Try Now'),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Learn More', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 2.4. Services Section Widget (Uses INTERACTIVE CARD) ---
  Widget _buildServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            'OUR PREMIUM & EXCLUSIVE SERVICES',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            'Discover our range of professional grooming services, enhanced by cutting-edge AI technology and traditional barbering expertise.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 160, // Height accommodates the hover lift effect
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            children: const <Widget>[
              // 1. Modern Fade (using 'mordern_fade.jpg')
              InteractiveServiceCard(imagePath: 'assets/images/mordern_fade.jpg', title: 'Modern Fade'),
              SizedBox(width: 15),
              // 2. Kids Cut (using 'kids_cut.jpg')
              InteractiveServiceCard(imagePath: 'assets/images/kids_cut.jpg', title: 'Kids Cut'),
              SizedBox(width: 15),
              // 3. Amazing Hair (using 'amazing_hair.jpg')
              InteractiveServiceCard(imagePath: 'assets/images/amazing_hair.jpg', title: 'Amazing Hair'), 
            ],
          ),
        ),
      ],
    );
  }
} // End of BarbershopDashboardContent


// --- 3. Interactive Service Card Widget for Hover Effect ---
class InteractiveServiceCard extends StatefulWidget {
  final String imagePath;
  final String title;

  const InteractiveServiceCard({
    required this.imagePath,
    required this.title,
    super.key,
  });

  @override
  State<InteractiveServiceCard> createState() => _InteractiveServiceCardState();
}

class _InteractiveServiceCardState extends State<InteractiveServiceCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        // The card 'lifts' 10 pixels up when hovering
        transform: Matrix4.identity()..translate(0.0, _isHovering ? -10.0 : 0.0),
        // Adding shadow to enhance the 'pop-up' feel
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: kGoldColor.withOpacity(_isHovering ? 0.5 : 0.0),
              blurRadius: 15.0,
              spreadRadius: 2.0,
            ),
          ],
        ),
        child: Container(
          width: 120,
          height: 150,
          decoration: BoxDecoration(
            color: kDarkBlackColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.imagePath,
                  fit: BoxFit.cover,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        shadows: [
                          Shadow(
                            color: _isHovering ? kGoldColor.withOpacity(0.8) : Colors.transparent,
                            blurRadius: 5,
                          ),
                        ],
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