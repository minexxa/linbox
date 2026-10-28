import 'dart:ui' show View;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:linbox/models/linux_instance.dart';
import 'package:linbox/services/linux_env.dart';
import 'package:linbox/services/linux_session.dart';
import 'package:linbox/services/settings_store.dart';
import 'package:linbox/services/virt_key_input_handler.dart';
import 'package:linbox/widgets/selection_handles.dart';
import 'package:linbox/widgets/virt_keys.dart';
import 'package:xterm/xterm.dart';

/// 本机 Linux（proot）终端页：部署 + 渲染 + 虚拟按键 + 重连。
///
/// 与 server_box 对齐的交互：
/// - 长按选词，拖动选区两端手柄可调整范围；
/// - 仅「单击」终端才弹出输入法，长按/选择文本不会弹键盘；
/// - 虚拟按键条随手机输入法键盘一同显示/消失（输入法弹出时位于其上方）；
/// - Ctrl / Alt / Shift 点亮后与输入法键盘的字母等按键组合。
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.instance});

  final LinuxInstance instance;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  late final LinuxSession _session;
  final _terminalKey = GlobalKey<TerminalViewState>();
  final _focusNode = FocusNode();

  /// 终端滚动控制器：选区手柄需要监听滚动以跟随位置。
  final _scrollController = ScrollController();

  /// 修饰键状态机，同时挂载到 [Terminal.inputHandler]。
  late final VirtKeyInputHandler _inputHandler = VirtKeyInputHandler();

  /// 手机输入法键盘当前是否弹出。虚拟按键条随之显示/消失。
  bool _imeVisible = false;

  /// 有选区时显示浮动工具条（复制 / 全选 / 粘贴）。
  bool _showCopyBar = false;

  final _settings = SettingsStore.instance;
  final _linuxEnv = LinuxEnv.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
    _session = LinuxSession(widget.instance);
    // 修饰键经 inputHandler 生效：输入法键盘/物理键盘的按键都会带上。
    _session.terminal.inputHandler = _inputHandler;
    _session.stateNotifier.addListener(_onState);
    _session.controller.addListener(_onSelectionChanged);
    _settings.addListener(_onSettings);
    _linuxEnv.stateNotifier.addListener(_onLinux);
    _linuxEnv.progressNotifier.addListener(_onLinux);
    _linuxEnv.messageNotifier.addListener(_onLinux);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLinux();
      _focusWithoutKeyboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange);
    _session.stateNotifier.removeListener(_onState);
    _session.controller.removeListener(_onSelectionChanged);
    _settings.removeListener(_onSettings);
    _linuxEnv.stateNotifier.removeListener(_onLinux);
    _linuxEnv.progressNotifier.removeListener(_onLinux);
    _linuxEnv.messageNotifier.removeListener(_onLinux);
    _session.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLinux() {
    if (!mounted) return;
    setState(() {});
    // 部署（可能由设置页添加后回到首页点进）完成后自动进入 shell。
    if (_linuxEnv.state == LinuxEnvState.ready &&
        _session.state != LinuxSessionState.connected &&
        _session.state != LinuxSessionState.connecting) {
      _session.connect();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 输入法弹出/收起会改变底部 viewInsets。
    final visible = View.of(context).viewInsets.bottom > 0;
    if (visible != _imeVisible && mounted) {
      setState(() => _imeVisible = visible);
    }
  }

  /// 焦点失去即键盘收起，立即同步隐藏虚拟按键条。
  void _onFocusChange() {
    if (!_focusNode.hasFocus && _imeVisible && mounted) {
      setState(() => _imeVisible = false);
    }
  }

  /// 选区出现/消失时显示/隐藏浮动工具条。
  void _onSelectionChanged() {
    final has = _session.controller.selection != null;
    if (has != _showCopyBar && mounted) {
      setState(() => _showCopyBar = has);
    }
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  /// 聚焦终端但不唤起输入法键盘（server_box 的 `keyboard: false` 行为）。
  void _focusWithoutKeyboard() {
    _focusNode.requestFocus();
    // 聚焦会顺势打开输入连接，延迟一帧后收起键盘。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  /// 切换手机输入法键盘（server_box 的 IME 键）。
  void _toggleIme() {
    if (_imeVisible) {
      _focusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  /// 先确保 rootfs 已部署，再连会话。
  Future<void> _prepareLinux() async {
    if (_linuxEnv.state == LinuxEnvState.ready) {
      await _session.connect();
      return;
    }
    await _linuxEnv.install(widget.instance);
    if (!mounted) return;
    if (_linuxEnv.state == LinuxEnvState.ready) {
      await _session.connect();
    }
  }

  Future<void> _reconnect() async {
    await _session.reconnect();
  }

  /// 长按终端：有选区复制，无选区粘贴（server_box 同款逻辑）。
  Future<void> _onClipboardAction() async {
    final selection = _session.controller.selection;
    if (selection != null) {
      await _copySelection();
      return;
    }
    await _pasteFromClipboard();
  }

  /// 复制当前选区到剪贴板（工具条“复制”按钮与长按共用）。
  Future<void> _copySelection() async {
    final selection = _session.controller.selection;
    if (selection == null) return;
    final text = _selectedText(selection);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    _session.controller.clearSelection();
  }

  /// 从剪贴板粘贴（长按无选区时与工具条“粘贴”按钮共用）。
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _session.terminal.paste(text);
    _session.controller.clearSelection();
  }

  /// 全选终端内容（pub 版 xterm 无 selectAll，自建选区）。
  void _selectAll() {
    final buffer = _session.terminal.buffer;
    if (buffer.height == 0) return;
    final lastLine = buffer.lines[buffer.height - 1];
    _session.controller.setSelection(
      buffer.createAnchorFromOffset(const CellOffset(0, 0)),
      buffer.createAnchorFromOffset(
        CellOffset(lastLine.length, buffer.height - 1),
      ),
    );
  }

  /// 从 buffer 中提取选区文本，尊重 soft-wrap（isWrapped）不插入多余换行。
  String _selectedText(BufferRange range) {
    return _session.terminal.buffer.getText(range);
  }

  Future<bool> _onWillPop() async {
    // 仅在已连接时按「终端退出确认」弹窗，其余直接退出。
    if (_session.state != LinuxSessionState.connected) return true;
    if (!_settings.confirmExitTerminal) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接？'),
        content: const Text('当前会话仍在连接中，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开并退出'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = _settings.fontSize;

    final termTheme = isDark ? _darkTheme : _lightTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: termTheme.background,
            appBar: AppBar(
              title: Text(
                widget.instance.name,
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                IconButton(
                  tooltip: '重连',
                  icon: const Icon(Icons.refresh),
                  onPressed: _session.state == LinuxSessionState.connecting
                      ? null
                      : _reconnect,
                ),
                IconButton(
                  tooltip: '断开',
                  icon: const Icon(Icons.link_off),
                  onPressed: _session.state == LinuxSessionState.connected
                      ? () async {
                          await _session.close();
                        }
                      : null,
                ),
              ],
            ),
            body: Column(
              children: [
                // rootfs 尚未部署时先下载解压，再进入 shell。
                if (_linuxEnv.state == LinuxEnvState.downloading ||
                    _linuxEnv.state == LinuxEnvState.extracting)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        minHeight: 2,
                        value: _linuxEnv.progress <= 0 ? null : _linuxEnv.progress,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(
                          '正在部署 ${widget.instance.distroLabel}：'
                          '${_linuxEnv.message.isEmpty ? _linuxEnv.state.label : _linuxEnv.message}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                if (_linuxEnv.state == LinuxEnvState.failed)
                  MaterialBanner(
                    content: Text(_linuxEnv.error ?? '部署失败'),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: _prepareLinux,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                if (_session.state == LinuxSessionState.connecting)
                  const LinearProgressIndicator(minHeight: 2),
                if (_session.state == LinuxSessionState.failed)
                  MaterialBanner(
                    content: Text(
                      _session.errorMessage ?? '连接失败',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: _reconnect,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      TerminalView(
                        _session.terminal,
                        key: _terminalKey,
                        controller: _session.controller,
                        focusNode: _focusNode,
                        scrollController: _scrollController,
                        autofocus: false,
                        keyboardType: TextInputType.text,
                        textStyle: TerminalStyle(
                          fontSize: fontSize,
                          fontFamily: 'monospace',
                        ),
                        theme: termTheme,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        hardwareKeyboardOnly: false,
                        onSecondaryTapUp: (details, offset) =>
                            _onClipboardAction(),
                      ),
                      // 有选区时在选区两端显示可拖动手柄，拖动调整选中范围。
                      if (_showCopyBar)
                        Positioned.fill(
                          child: SelectionHandles(
                            terminalKey: _terminalKey,
                            terminal: _session.terminal,
                            controller: _session.controller,
                            scrollController: _scrollController,
                          ),
                        ),
                    ],
                  ),
                ),
                // 虚拟按键条随手机输入法键盘一同显示/消失。
                if (_settings.showVirtKeys && _imeVisible)
                  VirtKeysBar(
                    inputHandler: _inputHandler,
                    onInput: (data) => _session.terminal.textInput(data),
                    onKey: (key) => _session.terminal.keyInput(key),
                    onToggleIme: _toggleIme,
                  ),
              ],
            ),
          ),
          // 悬浮在 AppBar 区域上方，可遮挡标题/按钮，不盖住终端文字
          if (_showCopyBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Center(
                    child: _SelectionToolbar(
                      onCopy: _copySelection,
                      onSelectAll: _selectAll,
                      onPaste: _pasteFromClipboard,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 终端选区浮动工具条：复制 / 全选 / 粘贴。
class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.onCopy,
    required this.onSelectAll,
    required this.onPaste,
  });

  final Future<void> Function() onCopy;
  final VoidCallback onSelectAll;
  final Future<void> Function() onPaste;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.black87, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarAction(
              icon: Icons.content_copy_outlined,
              label: '复制',
              emphasized: true,
              onTap: onCopy,
            ),
            _ToolbarAction(
              icon: Icons.select_all_outlined,
              label: '全选',
              onTap: onSelectAll,
            ),
            _ToolbarAction(
              icon: Icons.content_paste_outlined,
              label: '粘贴',
              onTap: onPaste,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = emphasized ? Colors.black : Colors.black87;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _darkTheme = TerminalTheme(
  cursor: const Color(0xFFAEAFAD),
  selection: const Color(0x40FFFFFF),
  foreground: const Color(0xFFCCCCCC),
  background: const Color(0xFF1E1E1E),
  black: const Color(0xFF000000),
  red: const Color(0xFFCD3131),
  green: const Color(0xFF0DBC79),
  yellow: const Color(0xFFE5E510),
  blue: const Color(0xFF2472C8),
  magenta: const Color(0xFFBC3FBC),
  cyan: const Color(0xFF11A8CD),
  white: const Color(0xFFE5E5E5),
  brightBlack: const Color(0xFF666666),
  brightRed: const Color(0xFFF14C4C),
  brightGreen: const Color(0xFF23D18B),
  brightYellow: const Color(0xFFF5F543),
  brightBlue: const Color(0xFF3B8EEA),
  brightMagenta: const Color(0xFFD670D6),
  brightCyan: const Color(0xFF29B8DB),
  brightWhite: const Color(0xFFE5E5E5),
  searchHitBackground: const Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: const Color(0xFF31FF26),
  searchHitForeground: const Color(0xFF000000),
);

final _lightTheme = TerminalTheme(
  cursor: const Color(0xFF000000),
  selection: const Color(0x40000000),
  foreground: const Color(0xFF333333),
  background: const Color(0xFFFAFAFA),
  black: const Color(0xFF000000),
  red: const Color(0xFFCD3131),
  green: const Color(0xFF00BC00),
  yellow: const Color(0xFF949800),
  blue: const Color(0xFF0451A5),
  magenta: const Color(0xFFBC05BC),
  cyan: const Color(0xFF0598BC),
  white: const Color(0xFF555555),
  brightBlack: const Color(0xFF666666),
  brightRed: const Color(0xFFCD3131),
  brightGreen: const Color(0xFF14CE14),
  brightYellow: const Color(0xFFB5B00),
  brightBlue: const Color(0xFF0451A5),
  brightMagenta: const Color(0xFFBC05BC),
  brightCyan: const Color(0xFF0598BC),
  brightWhite: const Color(0xFFA5A5A5),
  searchHitBackground: const Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: const Color(0xFF31FF26),
  searchHitForeground: const Color(0xFF000000),
);
