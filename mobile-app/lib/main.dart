import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_navigator.dart';

export 'app_navigator.dart' show navigatorKey, routeObserver;
import 'user/api_config.dart';
import 'user/auth_bootstrap.dart';
import 'user/auth_page.dart';
import 'user/splash_page.dart';
import 'kiosk/kiosk_home_page.dart';
import 'package:app_links/app_links.dart';
import 'user/payment_result_page.dart';
import 'user/scanner/overlay_asset_cache.dart';
import 'app_orientation.dart';

// --- 1. Define Custom Colors ---
const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBlackColor = Color(0xFF111111);
const Color kOrangeColor = Color(0xFFF37022);

const String _appMode = String.fromEnvironment('APP_MODE', defaultValue: 'customer');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_appMode == 'kiosk') {
    await AppOrientation.lockForKiosk();
  } else {
    await AppOrientation.lockForCustomer();
  }
  await ApiConfig.ensureInitialized();
  Uri? startupLink;
  if (!kIsWeb) {
    try {
      startupLink = await AppLinks().getInitialAppLink();
    } catch (_) {}
  }
  if (kIsWeb) {
    // Use path-based routing so OAuth fragments (#access_token=...) are not
    // interpreted as Flutter route paths.
    setUrlStrategy(PathUrlStrategy());
  }

  // OAuth callback ownership diagnostic (debug builds only).
  //
  // Supabase.initialize's own listener prints Level.INFO and above, which is
  // why "supabase.auth: INFO: Signing out user" shows up in the console. The
  // deep-link observer's own breadcrumbs are quieter than that:
  //   'Starting deeplink observer'  -> Level.FINE
  //   'handle deeplink uri: <uri>'  -> Level.FINEST
  //   'handle deeplink uri'         -> Level.INFO
  // Neither of the first two can appear under the default listener, so the
  // console could not distinguish "the SDK observer never received the
  // callback" from "it received it and failed quietly". This listener drops the
  // floor to ALL so that distinction is visible.
  //
  // Diagnostic only -- remove once OAuth callback ownership is settled.
  if (kDebugMode) {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName.startsWith('supabase')) {
        debugPrint(
          '[sdk] ${record.loggerName}: ${record.level.name}: ${record.message}'
          '${record.error != null ? " error=${record.error}" : ""}',
        );
      }
    });
  }

  await Supabase.initialize(
    url: 'https://sergfnujsutcschocuuz.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcmdmbnVqc3V0Y3NjaG9jdXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxODM3NzQsImV4cCI6MjA4OTc1OTc3NH0.tr2aFcXaKYt5LwvWp48VRAi-IS2nI1bur_CnRd7OHCg',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: false,
      // detectSessionInUri: false -- AuthBootstrap owns the code exchange.
      //
      // This is now settled by device logs rather than assumption. With
      // Level.ALL logging the SDK prints "Starting deeplink observer" (FINE) at
      // init, but NEVER prints "handle deeplink uri" (INFO) for any callback --
      // not on the first sign-in, not on the second. Its observer is installed
      // and then never fed.
      //
      // The reason is app_links 3.5.1: `uriLinkStream` is a getter that calls
      // EventChannel.receiveBroadcastStream() afresh on every access, and each
      // call re-registers the platform message handler for that channel. The
      // last subscriber to register wins and the earlier ones are silently
      // disconnected. supabase_flutter subscribes inside Supabase.initialize;
      // AuthBootstrap subscribes afterwards, so AuthBootstrap wins and the SDK
      // observer goes deaf.
      //
      // So ownership was never actually shared -- AuthBootstrap has been the
      // only exchanger all along. Setting this to false makes that explicit
      // instead of accidental, and stops the SDK adding a competing subscriber
      // that can only ever steal the stream from whoever registers before it.
      //
      // History worth keeping: on 2026-09-01 this was set to false so that
      // AuthBootstrap could own the exchange, as an attempted fix for OAuth
      // sign-ins hanging on the splash screen. That hang was a *navigation*
      // timing bug, not an auth bug — the session was being created fine and
      // only appeared after a lifecycle resume flushed the pending route.
      // Taking over the exchange broke working authentication: every OAuth
      // attempt after the first failed with flow_state_not_found. Verified by
      // checking out 3e1976e (2026-08-30), where the stock SDK exchange signs
      // in repeatedly without error.
      //
      // The navigation bug is now fixed properly in AuthBootstrap
      // (AuthFlowEngine + _queueDestination + flushPendingNavigation), so the
      // exchange can go back to the SDK where it worked.
    ),
  );

  await AuthBootstrap.initialize(startupLink: startupLink);

  // Preload haircut overlay PNGs in background (reduces scanner/results lag).
  unawaited(OverlayAssetCache.preload());

  // THE single app_links subscription for the whole app.
  //
  // EventChannel allows one message handler per channel, so the last .listen()
  // call wins and earlier subscribers are silently orphaned. When the Supabase
  // SDK observer, AuthBootstrap and this block each subscribed separately, which
  // one actually received a deep link came down to registration order -- and the
  // auth callback was reaching a listener that then dropped it.
  //
  // This listener is registered last on purpose, so it deterministically owns
  // the channel, and it dispatches explicitly rather than filtering. Restores
  // the working shape from 3e1976e, which forwarded auth links the same way.
  final AppLinks appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    if (uri.scheme == 'io.supabase.flutter' && uri.host == 'login-callback') {
      unawaited(AuthBootstrap.handleAuthCallbackUri(uri));
      return;
    }
    if (uri.scheme == 'tatisapp' && uri.host == 'payment-return') {
      final params = uri.queryParameters;
      try {
        navigatorKey.currentState?.pushNamed('/payment-result', arguments: params);
      } catch (_) {}
    }
  }, onError: (_) {});

  runApp(const TatisBarbershopApp());
}

// The main application widget (MaterialApp shell)
class TatisBarbershopApp extends StatelessWidget {
  const TatisBarbershopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.dark().textTheme.apply(fontFamily: 'CenturyGothic');
    return MaterialApp(
      title: 'Brilliante Barbershop',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'CenturyGothic',
        textTheme: baseTextTheme,
      ),
      home: _appMode == 'kiosk' ? const KioskHomePage() : const SplashPage(),
      routes: {
        '/payment-result': (context) => const PaymentResultPage(),
      },
      onUnknownRoute: (_) =>
          MaterialPageRoute(builder: (_) => const SplashPage()),
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