import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:linbox/models/linux_instance.dart';

/// 本机 Linux 实例的持久化（SharedPreferences）。
class LinuxStore {
  LinuxStore._();
  static final LinuxStore instance = LinuxStore._();

  static const String _key = 'linux_instances';

  List<LinuxInstance> instances = [];
  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);
  void _notify() {
    for (final fn in List.of(_listeners)) fn();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        instances = [
          for (final e in list)
            if (e is Map) LinuxInstance.fromJson(Map<String, dynamic>.from(e)),
        ];
      } catch (_) {
        instances = [];
      }
    }
    _notify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final i in instances) i.toJson()]),
    );
  }

  void add(LinuxInstance i) {
    instances.add(i);
    _save();
    _notify();
  }

  void update(LinuxInstance i) {
    final idx = instances.indexWhere((e) => e.id == i.id);
    if (idx >= 0) instances[idx] = i;
    _save();
    _notify();
  }

  void remove(String id) {
    instances.removeWhere((e) => e.id == id);
    _save();
    _notify();
  }

  void reorder(List<String> ids) {
    final byId = {for (final i in instances) i.id: i};
    final ordered = <LinuxInstance>[];
    for (final id in ids) {
      final i = byId[id];
      if (i != null) {
        ordered.add(i);
        byId.remove(id);
      }
    }
    for (final i in byId.values) ordered.add(i);
    instances = ordered;
    _save();
    _notify();
  }

  LinuxInstance? byId(String id) =>
      instances.where((e) => e.id == id).firstOrNull;
}
