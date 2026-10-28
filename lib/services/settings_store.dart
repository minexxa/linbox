import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:linbox/models/virt_key_def.dart';

enum AppThemeMode { system, light, dark }

/// 应用设置（全局选项，不再包含服务器 / 本机终端）。
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _themeKey = 'theme_mode';
  static const _fontSizeKey = 'font_size';
  static const _virtKeysKey = 'virt_keys';
  static const _virtKeyIdsKey = 'virt_key_ids';
  static const _virtKeysConfigKey = 'virt_keys_config';
  static const _virtKeyRowsKey = 'virt_key_per_row';
  static const _virtKeyAutoOffKey = 'virt_key_auto_off';
  static const _showVirtKeysKey = 'show_virt_keys';
  static const _exitConfirmKey = 'terminal_exit_confirm';

  AppThemeMode themeMode = AppThemeMode.system;
  double fontSize = 14;
  bool showVirtKeys = true;

  /// 修饰键（Ctrl/Alt/Shift）组合生效一次后自动取消亮起。
  bool virtKeyAutoOff = true;

  /// Linux 终端退出时是否弹出断开确认（默认开启）。
  bool confirmExitTerminal = true;

  /// 当前启用的虚拟按键 id（有序，兼容旧逻辑 / UI 统计）。
  List<String> virtKeyIds = List.of(VirtKeyDef.defaultIds);

  /// 完整虚拟按键配置（含自定义标签与命令）。
  List<VirtKeyDef> virtKeys = List.of(VirtKeyDef.defaultKeys);

  /// 每行最多几个键。
  int virtKeysPerRow = 7;

  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);
  void _notify() {
    for (final fn in List.of(_listeners)) fn();
  }

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  List<VirtKeyDef> get enabledVirtKeys {
    if (virtKeys.isNotEmpty) return List.unmodifiable(virtKeys);
    // 兼容仅有 id 列表的旧数据
    final keys = [
      for (final id in virtKeyIds)
        if (VirtKeyDef.byId(id) case final k?) k,
    ];
    if (keys.isEmpty) return VirtKeyDef.defaultKeys;
    return keys;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_themeKey);
    themeMode = switch (t) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
    fontSize = prefs.getDouble(_fontSizeKey) ?? 14;
    showVirtKeys = prefs.getBool(_showVirtKeysKey) ?? true;
    virtKeyAutoOff = prefs.getBool(_virtKeyAutoOffKey) ?? true;
    confirmExitTerminal = prefs.getBool(_exitConfirmKey) ?? true;
    virtKeysPerRow = (prefs.getInt(_virtKeyRowsKey) ?? 7).clamp(4, 10);

    final cfgRaw = prefs.getString(_virtKeysConfigKey);
    if (cfgRaw != null && cfgRaw.isNotEmpty) {
      try {
        final list = jsonDecode(cfgRaw) as List<dynamic>;
        final parsed = <VirtKeyDef>[
          for (final e in list)
            if (e is Map)
              VirtKeyDef.fromJson(Map<String, dynamic>.from(e)),
        ];
        if (parsed.isNotEmpty) {
          virtKeys = parsed;
          virtKeyIds = [for (final k in parsed) k.id];
        }
      } catch (_) {
        virtKeys = List.of(VirtKeyDef.defaultKeys);
        virtKeyIds = List.of(VirtKeyDef.defaultIds);
      }
    } else {
      // 兼容旧版只存 id 列表
      final raw = prefs.getString(_virtKeyIdsKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = (jsonDecode(raw) as List).cast<String>();
          if (list.isNotEmpty) {
            virtKeyIds = list;
            virtKeys = [
              for (final id in list)
                if (VirtKeyDef.byId(id) case final k?) k,
            ];
            if (virtKeys.isEmpty) {
              virtKeys = List.of(VirtKeyDef.defaultKeys);
              virtKeyIds = List.of(VirtKeyDef.defaultIds);
            }
          }
        } catch (_) {
          virtKeyIds = List.of(VirtKeyDef.defaultIds);
          virtKeys = List.of(VirtKeyDef.defaultKeys);
        }
      }
    }
    _notify();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeKey,
      switch (mode) {
        AppThemeMode.system => 'system',
        AppThemeMode.light => 'light',
        AppThemeMode.dark => 'dark',
      },
    );
    _notify();
  }

  Future<void> setFontSize(double size) async {
    fontSize = size.clamp(10, 24);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
    _notify();
  }

  Future<void> setShowVirtKeys(bool value) async {
    showVirtKeys = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showVirtKeysKey, value);
    _notify();
  }

  Future<void> setVirtKeyAutoOff(bool value) async {
    virtKeyAutoOff = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_virtKeyAutoOffKey, value);
    _notify();
  }

  Future<void> setConfirmExitTerminal(bool value) async {
    confirmExitTerminal = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exitConfirmKey, value);
    _notify();
  }

  Future<void> setVirtKeyIds(List<String> ids) async {
    virtKeyIds = List.of(ids);
    virtKeys = [
      for (final id in ids)
        if (VirtKeyDef.byId(id, extra: virtKeys) case final k?) k,
    ];
    if (virtKeys.isEmpty) {
      virtKeys = List.of(VirtKeyDef.defaultKeys);
      virtKeyIds = List.of(VirtKeyDef.defaultIds);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_virtKeyIdsKey, jsonEncode(virtKeyIds));
    await prefs.setString(
      _virtKeysConfigKey,
      jsonEncode([for (final k in virtKeys) k.toJson()]),
    );
    _notify();
  }

  Future<void> setVirtKeys(List<VirtKeyDef> keys) async {
    virtKeys = List.of(keys);
    virtKeyIds = [for (final k in keys) k.id];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_virtKeyIdsKey, jsonEncode(virtKeyIds));
    await prefs.setString(
      _virtKeysConfigKey,
      jsonEncode([for (final k in virtKeys) k.toJson()]),
    );
    _notify();
  }

  Future<void> setVirtKeysPerRow(int n) async {
    virtKeysPerRow = n.clamp(4, 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_virtKeyRowsKey, virtKeysPerRow);
    _notify();
  }

  Future<void> applyVirtKeyPreset(List<String> ids) => setVirtKeyIds(ids);
}
