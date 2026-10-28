import 'package:flutter/material.dart';

import 'package:linbox/models/linux_instance.dart';
import 'package:linbox/pages/linux_edit_page.dart';
import 'package:linbox/pages/settings_page.dart';
import 'package:linbox/pages/terminal_page.dart';
import 'package:linbox/services/linux_env.dart';
import 'package:linbox/services/linux_store.dart';
import 'package:linbox/services/settings_store.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = LinuxStore.instance;
  final _settings = SettingsStore.instance;
  final _linuxEnv = LinuxEnv.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    _settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<LinuxInstance> get _items => _store.instances;

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final items = _items;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= items.length) return;
    final list = List<LinuxInstance>.from(items);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    _store.reorder(list.map((e) => e.id).toList());
  }

  Future<void> _openTerminal(LinuxInstance i) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalPage(instance: i)),
    );
  }

  Future<void> _addInstance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LinuxEditPage()),
    );
  }

  Future<void> _editInstance(LinuxInstance i) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LinuxEditPage(instance: i)),
    );
  }

  Future<void> _deleteInstance(LinuxInstance i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除实例'),
        content: Text('确定删除「${i.name}」？将清理其 rootfs。'),
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
      await _linuxEnv.uninstall(i);
      _store.remove(i.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    final isEmpty = items.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linbox'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addInstance,
        icon: const Icon(Icons.add),
        label: const Text('添加实例'),
      ),
      body: isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.computer_outlined, size: 72, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    '还没有 Linux 实例',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角添加，支持 Alpine / Ubuntu / Debian',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: items.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(animation.value);
                    return Material(
                      elevation: 2 + 4 * t,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                _onReorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final i = items[index];
                return Padding(
                  key: ValueKey(i.id),
                  padding:
                      EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 8),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: _InstanceTile(
                      instance: i,
                      onTap: () => _openTerminal(i),
                      onEdit: () => _editInstance(i),
                      onDelete: () => _deleteInstance(i),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile({
    required this.instance,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final LinuxInstance instance;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.computer_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    _InstanceStatus(instance: instance),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实例副标题：发行版 / 版本 / 部署状态。
class _InstanceStatus extends StatefulWidget {
  const _InstanceStatus({super.key, required this.instance});

  final LinuxInstance instance;

  @override
  State<_InstanceStatus> createState() => _InstanceStatusState();
}

class _InstanceStatusState extends State<_InstanceStatus> {
  late final Future<bool> _deployed =
      LinuxEnv.instance.isInstalled(widget.instance);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<bool>(
      future: _deployed,
      builder: (ctx, snap) {
        final deployed = snap.data == true;
        final color = deployed ? scheme.primary : scheme.outline;
        return Row(
          children: [
            Icon(
              deployed
                  ? Icons.check_circle_outline
                  : Icons.cloud_download_outlined,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.instance.distroLabel} ${widget.instance.version}'
              ' · ${deployed ? '已部署' : '未部署（点击部署）'}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ],
        );
      },
    );
  }
}
