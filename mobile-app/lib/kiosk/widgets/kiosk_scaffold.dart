import 'package:flutter/material.dart';

import '../../user/widgets/app_top_bar.dart';
import '../kiosk_theme.dart';

class KioskScaffold extends StatelessWidget {
  final String? title;
  final Widget body;
  final Widget? bottomBar;
  final bool showBack;

  const KioskScaffold({
    super.key,
    this.title,
    required this.body,
    this.bottomBar,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KioskColors.background,
      appBar: AppTopBar(
        showBack: showBack,
        showCustomerActions: false,
        onBack: showBack ? () => Navigator.of(context).maybePop() : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                title!,
                style: const TextStyle(
                  color: KioskColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(child: body),
          if (bottomBar != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: bottomBar!,
              ),
            ),
        ],
      ),
    );
  }
}
