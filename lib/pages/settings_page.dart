import 'package:flutter/material.dart';

import 'package:linbox/models/linux_instance.dart';
import 'package:linbox/pages/linux_edit_page.dart';
import 'package:linbox/pages/virt_keys_settings_page.dart';
import 'package:linbox/services/linux_env.dart';
import 'package:linbox/services/linux_store.dart';
import 'package:linbox/services/settings_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsStore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('外观'),
          ListTile(
            title: const Text('主题'),
            subtitle: Text(switch (_settings.themeMode) {
              AppThemeMode.system => '跟随系统',
              AppThemeMode.light => '浅色',
              AppThemeMode.dark => '深色',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context),
          ),
          ListTile(
            title: const Text('终端字号'),
            subtitle: Text('${_settings.fontSize.toStringAsFixed(0)}'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _settings.fontSize,
                min: 10,
                max: 22,
                divisions: 12,
                label: _settings.fontSize.toStringAsFixed(0),
                onChanged: (v) => _settings.setFontSize(v),
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('Linux 实例'),
          const _InstanceManager(),
          const Divider(),
          const _SectionHeader('终端'),
          SwitchListTile(
            title: const Text('终端退出确认'),
            subtitle: const Text('Linux 连接中返回时弹出确认'),
            value: _settings.confirmExitTerminal,
            onChanged: (v) => _settings.setConfirmExitTerminal(v),
          ),
          SwitchListTile(
            title: const Text('显示虚拟按键'),
            subtitle: const Text('底部 Ctrl / Esc / 方向键等'),
            value: _settings.showVirtKeys,
            onChanged: (v) => _settings.setShowVirtKeys(v),
          ),
          SwitchListTile(
            title: const Text('修饰键自动取消'),
            subtitle: const Text('Ctrl 等组合生效一次后自动熄灭'),
            value: _settings.virtKeyAutoOff,
            onChanged: (v) => _settings.setVirtKeyAutoOff(v),
          ),
          ListTile(
            title: const Text('自定义虚拟按键'),
            subtitle: Text(
              '已选 ${_settings.virtKeyIds.length} 键 · 每行 ${_settings.virtKeysPerRow}',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: _settings.showVirtKeys,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const VirtKeysSettingsPage(),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('关于'),
          const ListTile(
            title: Text('Linbox'),
            subtitle: Text('v1.0.0 · proot + xterm'),
          ),
          const ListTile(
            title: Text('说明'),
            subtitle: Text(
              '在 Android 上以 proot 运行 Alpine / Ubuntu / Debian。'
              '实例与 rootfs 保存在本地，不会上传。',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context) async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in AppThemeMode.values)
              ListTile(
                title: Text(switch (mode) {
                  AppThemeMode.system => '跟随系统',
                  AppThemeMode.light => '浅色',
                  AppThemeMode.dark => '深色',
                }),
                trailing: _settings.themeMode == mode
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, mode),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _settings.setThemeMode(selected);
    }
  }
}

/// 实例管理区：添加入口 + 列表（含状态 / 占用 / 编辑 / 删除）。
class _InstanceManager extends StatefulWidget {
  const _InstanceManager();

  @override
  State<_InstanceManager> createState() => _InstanceManagerState();
}

class _InstanceManagerState extends State<_InstanceManager> {
  final _store = LinuxStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final instances = _store.instances;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('添加实例'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinuxEditPage()),
            );
          },
        ),
        for (final i in instances)
          _InstanceTile(key: ValueKey(i.id), instance: i),
      ],
    );
  }
}

class _InstanceTile extends StatefulWidget {
  const _InstanceTile({super.key, required this.instance});

  final LinuxInstance instance;

  @override
  State<_InstanceTile> createState() => _InstanceTileState();
}

class _InstanceTileState extends State<_InstanceTile> {
  late final Future<bool> _deployed = LinuxEnv.instance.isInstalled(widget.instance);
  late final Future<int> _size = LinuxEnv.instance.sizeBytes(widget.instance);

  Future<void> _confirmDelete(BuildContext context) async {
    final size = await _size;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除实例'),
        content: Text(
          '确定删除「${widget.instance.name}」？'
          '${size > 0 ? ' 将清理约 ${(size / 1024 / 1024).toStringAsFixed(0)} MB 的 rootfs。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LinuxEnv.instance.uninstall(widget.instance);
      LinuxStore.instance.remove(widget.instance.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.computer_outlined, color: scheme.onSecondaryContainer),
      ),
      title: Text(widget.instance.name),
      subtitle: FutureBuilder<bool>(
        future: _deployed,
        builder: (ctx, snap) {
          final deployed = snap.data == true;
          return Text(
            '${widget.instance.distroLabel} ${widget.instance.version}'
            ' · ${deployed ? '已部署' : '未部署'}',
          );
        },
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LinuxEditPage(instance: widget.instance),
              ),
            );
          } else if (v == 'delete') {
            _confirmDelete(context);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除并清理')),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LinuxEditPage(instance: widget.instance),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
