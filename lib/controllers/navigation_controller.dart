import 'package:flutter/foundation.dart';

enum AppSection {
  dashboard,
  customers,
  orders,
  products,
  materials,
  bom,
  routings,
  production,
  documents,
  masterData,
  schema,
}

class NavigationController extends ChangeNotifier {
  AppSection _section = AppSection.dashboard;
  AppSection get section => _section;
  bool _sidebarCollapsed = false;
  bool get sidebarCollapsed => _sidebarCollapsed;

  void go(AppSection section) {
    if (_section == section) return;
    _section = section;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarCollapsed = !_sidebarCollapsed;
    notifyListeners();
  }
}
