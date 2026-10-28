import 'package:flutter/material.dart';
import 'package:linbox/models/virt_key_def.dart';
import 'package:linbox/services/settings_store.dart';

/// 虚拟按键设置：排序、预设、新增/编辑/删除（含自定义命令）。
class VirtKeysSettingsPage extends StatefulWidget {
  const VirtKeysSettingsPage({super.key});

  @override
  State<VirtKeysSettingsPage> createState() => _VirtKeysSettingsPageState();
}

class _VirtKeysSettingsPageState extends State<VirtKeysSettingsPage> {
  final _settings = SettingsStore.instance;
  late List<VirtKeyDef> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.of(_settings.enabledVirtKeys);
  }

  Future<void> _persist() async {
    await _settings.setVirtKeys(_keys);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _applyPreset(List<VirtKeyDef> keys) async {
    setState(() => _keys = List.of(keys));
    await _settings.setVirtKeys(_keys);
  }

  Future<void> _editAt(int index) async {
    final result = await showDialog<VirtKeyDef>(
      context: context,
      builder: (_) => _KeyEditDialog(
        initial: _keys[index],
        title: '编辑按键',
      ),
    );
    if (result == null) return;
    setState(() => _keys[index] = result);
  }

  Future<void> _addKey() async {
    final result = await showDialog<VirtKeyDef>(
      context: context,
      builder: (_) => _KeyEditDialog(
        initial: VirtKeyDef.fromAction(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          label: '',
          actionId: 'send_text',
          payload: '',
        ),
        title: '添加按键',
        isNew: true,
      ),
    );
    if (result == null) return;
    setState(() => _keys.add(result));
  }

  void _removeAt(int index) {
    setState(() => _keys.removeAt(index));
  }

  String _actionSubtitle(VirtKeyDef k) {
    final aid = k.actionId;
    if (aid == 'send_text') {
      final t = k.sendText;
      return t.isEmpty ? '自定义文本' : '发送：$t';
    }
    for (final o in VirtKeyDef.actionOptions) {
      if (o.$1 == aid) return o.$2;
    }
    return aid;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('虚拟按键'),
        actions: [
          TextButton(onPressed: _persist, child: const Text('保存')),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '预设',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('完整'),
                  onPressed: () => _applyPreset(VirtKeyDef.defaultKeys),
                ),
                ActionChip(
                  label: const Text('精简'),
                  onPressed: () => _applyPreset(VirtKeyDef.compactKeys),
                ),
                ActionChip(
                  label: const Text('恢复默认'),
                  onPressed: () => _applyPreset(VirtKeyDef.defaultKeys),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('每行键数'),
            subtitle: Text('${_settings.virtKeysPerRow}'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _settings.virtKeysPerRow.toDouble(),
                min: 4,
                max: 10,
                divisions: 6,
                label: '${_settings.virtKeysPerRow}',
                onChanged: (v) async {
                  await _settings.setVirtKeysPerRow(v.round());
                  setState(() {});
                },
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '已启用（长按拖动排序，点按编辑）',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (_keys.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('尚未添加任何按键'),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _keys.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _keys.removeAt(oldIndex);
                  _keys.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final k = _keys[index];
                return ListTile(
                  key: ValueKey('${k.id}_$index'),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(k.label.isEmpty ? '?' : k.label),
                  subtitle: Text(_actionSubtitle(k)),
                  onTap: () => _editAt(index),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: '删除',
                    onPressed: () => _removeAt(index),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: _addKey,
              icon: const Icon(Icons.add),
              label: const Text('添加按键'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '从内置目录添加',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          for (final def in VirtKeyDef.catalog)
            ListTile(
              title: Text(def.label),
              subtitle: Text(def.id),
              leading: Icon(switch (def.kind) {
                VirtKeyKind.modifier => Icons.keyboard_option_key,
                VirtKeyKind.terminalKey => Icons.keyboard,
                VirtKeyKind.char => Icons.text_fields,
                VirtKeyKind.func => Icons.touch_app_outlined,
              }),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  // 允许重复添加同一类内置键（用唯一 id 后缀）
                  final exists = _keys.any((e) => e.id == def.id);
                  if (exists) {
                    final copy = VirtKeyDef(
                      id: '${def.id}_${DateTime.now().millisecondsSinceEpoch}',
                      label: def.label,
                      kind: def.kind,
                      terminalKey: def.terminalKey,
                      char: def.char,
                      icon: def.icon,
                      payload: def.payload,
                    );
                    setState(() => _keys.add(copy));
                  } else {
                    setState(() => _keys.add(def));
                  }
                },
              ),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _persist,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存布局'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// 新增 / 编辑单个虚拟按键。
class _KeyEditDialog extends StatefulWidget {
  const _KeyEditDialog({
    required this.initial,
    required this.title,
    this.isNew = false,
  });

  final VirtKeyDef initial;
  final String title;
  final bool isNew;

  @override
  State<_KeyEditDialog> createState() => _KeyEditDialogState();
}

class _KeyEditDialogState extends State<_KeyEditDialog> {
  late final TextEditingController _label;
  late final TextEditingController _payload;
  late String _actionId;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.initial.label);
    _payload = TextEditingController(text: widget.initial.sendText);
    _actionId = widget.initial.actionId;
    if (!VirtKeyDef.actionOptions.any((e) => e.$1 == _actionId)) {
      _actionId = 'send_text';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _payload.dispose();
    super.dispose();
  }

  void _confirm() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写显示文字')),
      );
      return;
    }
    if (_actionId == 'send_text' && _payload.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写要发送的文本')),
      );
      return;
    }

    // 修饰键 / 功能键 id 需固定，才能切换状态
    String id = widget.initial.id;
    if (_actionId == 'ctrl' ||
        _actionId == 'alt' ||
        _actionId == 'shift' ||
        _actionId == 'ime') {
      id = _actionId;
    } else if (widget.isNew && !id.startsWith('custom_')) {
      id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    }

    final def = VirtKeyDef.fromAction(
      id: id,
      label: label,
      actionId: _actionId,
      payload: _payload.text,
    );
    Navigator.pop(context, def);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: '显示文字',
                hintText: '如：↑、ls、Ctrl',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _actionId,
              decoration: const InputDecoration(
                labelText: '按键行为',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final o in VirtKeyDef.actionOptions)
                  DropdownMenuItem(
                    value: o.$1,
                    child: Text('${o.$2}（${o.$3}）'),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _actionId = v);
              },
            ),
            if (_actionId == 'send_text') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _payload,
                decoration: const InputDecoration(
                  labelText: '发送内容',
                  hintText: r'如：ls -la 或 path/',
                  border: OutlineInputBorder(),
                  helperText: '可多字符；需要回车可在末尾加 \\n（设置里直接敲回车无效）',
                ),
                maxLines: 3,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
