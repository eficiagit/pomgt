import 'package:flutter/foundation.dart';

class RuntimeDataController extends ChangeNotifier {
  int _revision = 0;
  final Map<String, int> _tableRevisions = {};

  int get revision => _revision;

  int revisionFor(String table) => _tableRevisions[table] ?? 0;

  void tableChanged(String table) {
    _revision++;
    _tableRevisions[table] = _revision;
    notifyListeners();
  }

  void tablesChanged(Iterable<String> tables) {
    final changed = tables.toSet();
    if (changed.isEmpty) return;
    _revision++;
    for (final table in changed) {
      _tableRevisions[table] = _revision;
    }
    notifyListeners();
  }
}
