import 'package:flutter/material.dart';

import 'ai_face_scan_page.dart';
import 'appointments_page.dart';
import 'dashboard_page.dart';

/// Customer home route ([DashboardPage]).
void navigateToCustomerHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const DashboardPage()),
    (route) => false,
  );
}

/// Prefer popping when possible; otherwise open customer home.
void navigateBackToCustomerHome(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  navigateToCustomerHome(context);
}

/// Open a main tab without dropping the dashboard from the stack (avoids blank screens on back).
void openCustomerTab(BuildContext context, CustomerTab tab) {
  final navigator = Navigator.of(context);
  switch (tab) {
    case CustomerTab.home:
      navigateToCustomerHome(context);
      break;
    case CustomerTab.appointments:
      navigator.push(
        MaterialPageRoute(builder: (_) => const AppointmentsPage()),
      );
      break;
    case CustomerTab.scanner:
      navigator.push(
        MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
      );
      break;
  }
}

enum CustomerTab { home, appointments, scanner }
