import 'package:flutter/foundation.dart';

class FeatureSelectionController extends ChangeNotifier {
  String? _selectedId;
  int _revision = 0;
  String? get selectedId => _selectedId;
  int get revision => _revision;

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void refresh() {
    _revision++;
    notifyListeners();
  }

  void clear() => select(null);
}

class CustomersController extends FeatureSelectionController {}

class OrdersController extends FeatureSelectionController {}

class ProductsController extends FeatureSelectionController {}

class MaterialsController extends FeatureSelectionController {}

class BomController extends FeatureSelectionController {}

class RoutingsController extends FeatureSelectionController {
  String? selectedRevisionId;
  String? selectedOperationId;
  void selectRevision(String? id) {
    selectedRevisionId = id;
    selectedOperationId = null;
    notifyListeners();
  }

  void selectOperation(String? id) {
    selectedOperationId = id;
    notifyListeners();
  }
}

class DocumentsController extends FeatureSelectionController {}

class ProductionController extends FeatureSelectionController {}
