import 'package:xterm/xterm.dart';

enum VirtKeyKind {
  /// 可切换的修饰键（Ctrl / Alt / Shift）
  modifier,
  /// 发送 TerminalKey
  terminalKey,
  /// 发送原始字符或自定义文本（payload）
  char,
  /// 功能键（如切换手机输入法）
  func,
}

/// 一枚可配置的虚拟按键（内置目录或用户自定义）。
class VirtKeyDef {
  const VirtKeyDef({
    required this.id,
    required this.label,
    required this.kind,
    this.terminalKey,
    this.char,
    this.icon,
    this.payload,
  });

  final String id;
  final String label;
  final VirtKeyKind kind;
  final TerminalKey? terminalKey;
  final String? char;

  /// func 类按键的图标名（如 IME 切换键）。
  final String? icon;

  /// 自定义文本：按下时发送的完整内容（可多字符，如 `ls\n`）。
  /// [kind] 为 [VirtKeyKind.char] 时优先于 [char]。
  final String? payload;

  /// 是否为用户自定义按键。
  bool get isCustom => id.startsWith('custom_');

  /// 实际发送的文本（自定义用 payload，内置单字符用 char）。
  String get sendText =>
      (payload != null && payload!.isNotEmpty) ? payload! : (char ?? '');

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        if (terminalKey != null) 'terminalKey': terminalKey!.name,
        if (char != null) 'char': char,
        if (icon != null) 'icon': icon,
        if (payload != null) 'payload': payload,
      };

  factory VirtKeyDef.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'char';
    final kind = VirtKeyKind.values.firstWhere(
      (e) => e.name == kindName,
      orElse: () => VirtKeyKind.char,
    );
    TerminalKey? tk;
    final tkName = json['terminalKey'] as String?;
    if (tkName != null) {
      for (final k in TerminalKey.values) {
        if (k.name == tkName) {
          tk = k;
          break;
        }
      }
    }
    return VirtKeyDef(
      id: json['id'] as String? ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: json['label'] as String? ?? '?',
      kind: kind,
      terminalKey: tk,
      char: json['char'] as String?,
      icon: json['icon'] as String?,
      payload: json['payload'] as String?,
    );
  }

  VirtKeyDef copyWith({
    String? id,
    String? label,
    VirtKeyKind? kind,
    TerminalKey? terminalKey,
    String? char,
    String? icon,
    String? payload,
  }) =>
      VirtKeyDef(
        id: id ?? this.id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        terminalKey: terminalKey ?? this.terminalKey,
        char: char ?? this.char,
        icon: icon ?? this.icon,
        payload: payload ?? this.payload,
      );

  /// 从内置目录或已启用列表解析；自定义 id 需由完整配置提供。
  static VirtKeyDef? byId(String id, {List<VirtKeyDef>? extra}) {
    if (extra != null) {
      for (final k in extra) {
        if (k.id == id) return k;
      }
    }
    for (final k in catalog) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// 按行为类型快速创建（用于编辑弹窗）。
  static VirtKeyDef fromAction({
    required String id,
    required String label,
    required String actionId,
    String payload = '',
  }) {
    switch (actionId) {
      case 'ctrl':
        return VirtKeyDef(id: id, label: label, kind: VirtKeyKind.modifier);
      case 'alt':
        return VirtKeyDef(id: id, label: label, kind: VirtKeyKind.modifier);
      case 'shift':
        return VirtKeyDef(id: id, label: label, kind: VirtKeyKind.modifier);
      case 'ime':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.func,
          icon: 'keyboard',
        );
      case 'esc':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.escape,
        );
      case 'tab':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.tab,
        );
      case 'enter':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.enter,
        );
      case 'backspace':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.backspace,
        );
      case 'delete':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.delete,
        );
      case 'up':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.arrowUp,
        );
      case 'down':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.arrowDown,
        );
      case 'left':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.arrowLeft,
        );
      case 'right':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.arrowRight,
        );
      case 'home':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.home,
        );
      case 'end':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.end,
        );
      case 'pgup':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.pageUp,
        );
      case 'pgdn':
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.terminalKey,
          terminalKey: TerminalKey.pageDown,
        );
      case 'send_text':
      default:
        return VirtKeyDef(
          id: id,
          label: label,
          kind: VirtKeyKind.char,
          payload: payload,
          char: payload.length == 1 ? payload : null,
        );
    }
  }

  /// 当前配置对应的行为 id（编辑弹窗用）。
  String get actionId {
    if (kind == VirtKeyKind.char &&
        (payload != null || (char != null && !catalogIds.contains(id)))) {
      // 自定义文本，或单字符但 id 不是内置
      if (isCustom || payload != null) return 'send_text';
    }
    if (kind == VirtKeyKind.modifier) {
      if (id.contains('ctrl') || label.toLowerCase() == 'ctrl') return 'ctrl';
      if (id.contains('alt') || label.toLowerCase() == 'alt') return 'alt';
      if (id.contains('shift') || label.toLowerCase() == 'shift') {
        return 'shift';
      }
    }
    if (kind == VirtKeyKind.func) return 'ime';
    if (kind == VirtKeyKind.terminalKey) {
      switch (terminalKey) {
        case TerminalKey.escape:
          return 'esc';
        case TerminalKey.tab:
          return 'tab';
        case TerminalKey.enter:
          return 'enter';
        case TerminalKey.backspace:
          return 'backspace';
        case TerminalKey.delete:
          return 'delete';
        case TerminalKey.arrowUp:
          return 'up';
        case TerminalKey.arrowDown:
          return 'down';
        case TerminalKey.arrowLeft:
          return 'left';
        case TerminalKey.arrowRight:
          return 'right';
        case TerminalKey.home:
          return 'home';
        case TerminalKey.end:
          return 'end';
        case TerminalKey.pageUp:
          return 'pgup';
        case TerminalKey.pageDown:
          return 'pgdn';
        default:
          break;
      }
    }
    // 内置 id 直接用
    if (catalogIds.contains(id)) return id;
    if (kind == VirtKeyKind.char) return 'send_text';
    return id;
  }

  static const catalog = <VirtKeyDef>[
    VirtKeyDef(id: 'ctrl', label: 'Ctrl', kind: VirtKeyKind.modifier),
    VirtKeyDef(id: 'alt', label: 'Alt', kind: VirtKeyKind.modifier),
    VirtKeyDef(id: 'shift', label: 'Shift', kind: VirtKeyKind.modifier),
    VirtKeyDef(
      id: 'ime',
      label: '键盘',
      kind: VirtKeyKind.func,
      icon: 'keyboard',
    ),
    VirtKeyDef(
      id: 'esc',
      label: 'Esc',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.escape,
    ),
    VirtKeyDef(
      id: 'tab',
      label: 'Tab',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.tab,
    ),
    VirtKeyDef(id: 'dash', label: '—', kind: VirtKeyKind.char, char: '-'),
    VirtKeyDef(id: 'slash', label: '/', kind: VirtKeyKind.char, char: '/'),
    VirtKeyDef(id: 'pipe', label: '|', kind: VirtKeyKind.char, char: '|'),
    VirtKeyDef(id: 'tilde', label: '~', kind: VirtKeyKind.char, char: '~'),
    VirtKeyDef(id: 'dollar', label: '\$', kind: VirtKeyKind.char, char: '\$'),
    VirtKeyDef(id: 'star', label: '*', kind: VirtKeyKind.char, char: '*'),
    VirtKeyDef(id: 'amp', label: '&', kind: VirtKeyKind.char, char: '&'),
    VirtKeyDef(id: 'semi', label: ';', kind: VirtKeyKind.char, char: ';'),
    VirtKeyDef(id: 'gt', label: '>', kind: VirtKeyKind.char, char: '>'),
    VirtKeyDef(id: 'lt', label: '<', kind: VirtKeyKind.char, char: '<'),
    VirtKeyDef(
      id: 'up',
      label: '↑',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowUp,
    ),
    VirtKeyDef(
      id: 'down',
      label: '↓',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowDown,
    ),
    VirtKeyDef(
      id: 'left',
      label: '←',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowLeft,
    ),
    VirtKeyDef(
      id: 'right',
      label: '→',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowRight,
    ),
    VirtKeyDef(
      id: 'home',
      label: 'Home',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.home,
    ),
    VirtKeyDef(
      id: 'end',
      label: 'End',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.end,
    ),
    VirtKeyDef(
      id: 'pgup',
      label: 'PgUp',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.pageUp,
    ),
    VirtKeyDef(
      id: 'pgdn',
      label: 'PgDn',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.pageDown,
    ),
    VirtKeyDef(
      id: 'backspace',
      label: '⌫',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.backspace,
    ),
    VirtKeyDef(
      id: 'delete',
      label: 'Del',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.delete,
    ),
    VirtKeyDef(
      id: 'enter',
      label: 'Enter',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.enter,
    ),
  ];

  static final catalogIds = {for (final k in catalog) k.id};

  /// 默认布局。
  static List<VirtKeyDef> get defaultKeys => [
        for (final id in defaultIds)
          if (byId(id) case final k?) k,
      ];

  static const defaultIds = <String>[
    'ctrl',
    'alt',
    'shift',
    'ime',
    'esc',
    'tab',
    'dash',
    'slash',
    'pipe',
    'up',
    'down',
    'left',
    'right',
    'home',
    'end',
    'backspace',
    'enter',
  ];

  /// 精简布局。
  static const compactIds = <String>[
    'ctrl',
    'esc',
    'tab',
    'ime',
    'up',
    'down',
    'left',
    'right',
    'enter',
  ];

  static List<VirtKeyDef> get compactKeys => [
        for (final id in compactIds)
          if (byId(id) case final k?) k,
      ];

  /// 编辑弹窗可选行为（与 ShellBox 类似分组）。
  static const actionOptions = <(String id, String name, String group)>[
    ('up', '↑ 上', '方向'),
    ('down', '↓ 下', '方向'),
    ('left', '← 左', '方向'),
    ('right', '→ 右', '方向'),
    ('pgup', 'PgUp', '功能'),
    ('pgdn', 'PgDn', '功能'),
    ('home', 'Home', '功能'),
    ('end', 'End', '功能'),
    ('esc', 'Esc', '功能'),
    ('tab', 'Tab', '功能'),
    ('enter', 'Enter', '功能'),
    ('backspace', 'Backspace', '功能'),
    ('delete', 'Delete', '功能'),
    ('ctrl', 'Ctrl', '修饰'),
    ('alt', 'Alt', '修饰'),
    ('shift', 'Shift', '修饰'),
    ('ime', '切换键盘', '其他'),
    ('send_text', '自定义文本', '其他'),
  ];
}
