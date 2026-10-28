import 'package:xterm/xterm.dart';

/// 虚拟修饰键（Ctrl / Alt / Shift）输入处理器。
///
/// 逻辑与 server_box 一致：修饰键在虚拟按键条上点选后保持亮起，
/// 之后经 [Terminal.keyInput] 的按键（输入法键盘的字母、物理键盘、
/// 虚拟按键）都会自动带上该修饰键组合。例如点亮 Ctrl 后按输入法
/// 键盘的 c，即发送 Ctrl+C（0x03）。
///
/// 通过 [Terminal.inputHandler] 挂载，事件在交给
/// [defaultInputHandler] 之前把修饰键状态合并进去。
class VirtKeyInputHandler implements TerminalInputHandler {
  VirtKeyInputHandler({this.autoOff = true});

  /// 组合生效一次后自动取消修饰键（对齐 server_box 的
  /// `sshVirtualKeyAutoOff` 设置，默认开启）。
  bool autoOff;

  bool ctrl = false;
  bool alt = false;
  bool shift = false;

  void toggleCtrl() => ctrl = !ctrl;
  void toggleAlt() => alt = !alt;
  void toggleShift() => shift = !shift;

  bool get anyActive => ctrl || alt || shift;

  /// 取消所有修饰键。
  void resetAll() {
    ctrl = false;
    alt = false;
    shift = false;
  }

  /// 仅取消本次事件中实际生效过的修饰键（server_box 同款逻辑）。
  void reset(TerminalKeyboardEvent e) {
    ctrl = e.ctrl ? false : ctrl;
    alt = e.alt ? false : alt;
    shift = e.shift ? false : shift;
  }

  @override
  String? call(TerminalKeyboardEvent event) {
    final e = event.copyWith(
      ctrl: event.ctrl || ctrl,
      alt: event.alt || alt,
      shift: event.shift || shift,
    );
    if (autoOff) reset(e);
    return defaultInputHandler.call(e);
  }
}
