import 'package:flutter/material.dart';
import 'package:linbox/models/virt_key_def.dart';
import 'package:linbox/services/settings_store.dart';
import 'package:linbox/services/virt_key_input_handler.dart';
import 'package:xterm/xterm.dart';

/// 底部虚拟按键条：布局由 [SettingsStore] 驱动。
///
/// Ctrl / Alt / Shift 为可切换修饰键：点亮后保持亮起，随后经终端的
/// 按键（输入法键盘的字母、物理键盘、其它虚拟键）自动带上修饰组合，
/// 与 server_box 的行为一致。
class VirtKeysBar extends StatefulWidget {
  const VirtKeysBar({
    super.key,
    required this.inputHandler,
    required this.onInput,
    required this.onKey,
    required this.onToggleIme,
  });

  /// 修饰键状态机（同时挂载在 [Terminal.inputHandler] 上）。
  final VirtKeyInputHandler inputHandler;

  final void Function(String data) onInput;
  final void Function(TerminalKey key) onKey;

  /// 切换手机输入法键盘的显示/隐藏。
  final VoidCallback onToggleIme;

  @override
  State<VirtKeysBar> createState() => _VirtKeysBarState();
}

class _VirtKeysBarState extends State<VirtKeysBar> {
  final _settings = SettingsStore.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  VirtKeyInputHandler get _handler => widget.inputHandler;

  void _tapDef(VirtKeyDef def) {
    switch (def.kind) {
      case VirtKeyKind.modifier:
        setState(() {
          final aid = def.actionId;
          if (aid == 'ctrl' || def.id.startsWith('ctrl')) {
            _handler.toggleCtrl();
          } else if (aid == 'alt' || def.id.startsWith('alt')) {
            _handler.toggleAlt();
          } else if (aid == 'shift' || def.id.startsWith('shift')) {
            _handler.toggleShift();
          }
        });
        return;
      case VirtKeyKind.func:
        if (def.actionId == 'ime' ||
            def.id == 'ime' ||
            def.icon == 'keyboard') {
          widget.onToggleIme();
        }
        return;
      case VirtKeyKind.terminalKey:
        if (def.terminalKey != null) {
          widget.onKey(def.terminalKey!);
        }
        break;
      case VirtKeyKind.char:
        final text = def.sendText;
        if (text.isEmpty) break;
        // 多字符：自定义命令；支持字面量 \n 表示回车
        final raw = text.replaceAll(r'\n', '\n');
        if (raw.length > 1) {
          widget.onInput(raw);
          _resetModifiers();
          break;
        }
        final ch = raw;
        if (_handler.ctrl) {
          final code = ch.toUpperCase().codeUnitAt(0);
          if (code >= 65 && code <= 90) {
            // a-z → 1-26
            widget.onInput(String.fromCharCode(code - 64));
          } else if (code >= 91 && code <= 95) {
            // [ \ ] ^ _ → ESC..US(27-31)，与 xterm 的 CtrlInputHandler 一致
            widget.onInput(String.fromCharCode(code - 91 + 27));
          } else {
            widget.onInput(ch);
          }
          _resetModifiers();
        } else if (_handler.alt) {
          widget.onInput('\x1b$ch');
          _resetModifiers();
        } else {
          widget.onInput(ch);
        }
        break;
    }
    // terminalKey 走 keyInput，修饰组合已在 inputHandler 内生效并按需重置；
    // 这里统一刷新一次，让亮起状态及时熄灭。
    if (mounted) setState(() {});
  }

  /// 虚拟按键条自身的字符输入不经 inputHandler，autoOff 时本地重置。
  void _resetModifiers() {
    if (_handler.autoOff) _handler.resetAll();
  }

  bool _isActive(VirtKeyDef def) {
    final aid = def.actionId;
    if (aid == 'ctrl' || def.id.startsWith('ctrl')) return _handler.ctrl;
    if (aid == 'alt' || def.id.startsWith('alt')) return _handler.alt;
    if (aid == 'shift' || def.id.startsWith('shift')) return _handler.shift;
    return false;
  }

  IconData? _iconOf(VirtKeyDef def) {
    switch (def.icon) {
      case 'keyboard':
        return Icons.keyboard_outlined;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surfaceContainerHighest;
    final keys = _settings.enabledVirtKeys;
    final perRow = _settings.virtKeysPerRow;

    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = <List<VirtKeyDef>>[];
    for (var i = 0; i < keys.length; i += perRow) {
      rows.add(
        keys.sublist(i, i + perRow > keys.length ? keys.length : i + perRow),
      );
    }

    Widget keyBtn(VirtKeyDef def) {
      final active = _isActive(def);
      final isEnter = def.id == 'enter';
      final icon = _iconOf(def);
      return Expanded(
        flex: isEnter ? 14 : 10,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: active ? scheme.primary : bg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _tapDef(def),
              child: SizedBox(
                height: 36,
                child: Center(
                  child: icon != null
                      ? Icon(
                          icon,
                          size: 17,
                          color: scheme.onSurface,
                        )
                      : Text(
                          def.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: active
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      elevation: 4,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in rows)
                Row(
                  children: [
                    for (final k in row) keyBtn(k),
                    // 不足一行时补空位，避免键被拉得过宽
                    for (var i = row.length; i < perRow; i++)
                      const Expanded(flex: 10, child: SizedBox()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
