import 'package:flutter/material.dart';

import 'package:linbox/models/linux_distro.dart';
import 'package:linbox/models/linux_instance.dart';
import 'package:linbox/services/linux_store.dart';

/// 新增 / 编辑一个 Linux 实例。
class LinuxEditPage extends StatefulWidget {
  const LinuxEditPage({super.key, this.instance});

  /// 为 null 表示新增。
  final LinuxInstance? instance;

  @override
  State<LinuxEditPage> createState() => _LinuxEditPageState();
}

class _LinuxEditPageState extends State<LinuxEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController(text: '1.1.1.1 8.8.8.8');

  late DistroDef _flavor;
  late String _version;
  late Mirror _mirror;

  @override
  void initState() {
    super.initState();
    final i = widget.instance;
    if (i != null) {
      _nameCtrl.text = i.name;
      _flavor = i.distro;
      _version = i.version;
      _mirror = _flavor.mirrors.firstWhere(
        (m) => m.url == i.mirrorUrl,
        orElse: () => _flavor.defaultMirror,
      );
      _customUrlCtrl.text = i.customRootfsUrl ?? '';
      _dnsCtrl.text = i.dns;
    } else {
      _flavor = LinuxDistro.alpine;
      _version = _flavor.defaultVersion;
      _mirror = _flavor.defaultMirror;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customUrlCtrl.dispose();
    _dnsCtrl.dispose();
    super.dispose();
  }

  void _onFlavorChanged(DistroDef? f) {
    if (f == null) return;
    setState(() {
      _flavor = f;
      _version = f.defaultVersion;
      _mirror = f.defaultMirror;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final customUrl = _flavor.supportsRootfsMirror
        ? null
        : _customUrlCtrl.text.trim();

    final store = LinuxStore.instance;
    if (widget.instance != null) {
      final updated = widget.instance!.copyWith(
        name: name,
        flavorId: _flavor.id,
        version: _version,
        mirrorUrl: _mirror.url,
        customRootfsUrl: customUrl,
        dns: _dnsCtrl.text.trim(),
      );
      store.update(updated);
    } else {
      store.add(
        LinuxInstance(
          name: name,
          flavorId: _flavor.id,
          version: _version,
          mirrorUrl: _mirror.url,
          customRootfsUrl: customUrl,
          dns: _dnsCtrl.text.trim(),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.instance != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑实例' : '添加实例'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如 My Alpine',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写名称' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<DistroDef>(
              value: _flavor,
              decoration: const InputDecoration(
                labelText: '发行版',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final d in LinuxDistro.all)
                  DropdownMenuItem(value: d, child: Text(d.label)),
              ],
              onChanged: _onFlavorChanged,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _version,
              decoration: const InputDecoration(
                labelText: '版本',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final v in _flavor.versions)
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _version = v);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Mirror>(
              value: _mirror,
              decoration: InputDecoration(
                labelText: _flavor.supportsRootfsMirror ? '镜像' : '软件源',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final m in _flavor.mirrors)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (m) {
                if (m != null) setState(() => _mirror = m);
              },
            ),
            const SizedBox(height: 16),
            if (!_flavor.supportsRootfsMirror)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _customUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rootfs URL',
                      hintText:
                          'Debian aarch64 rootfs tarball（.tar.gz / .tar.xz）',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Debian 需填写 rootfs 地址';
                      if (!t.startsWith('http')) return '需以 http(s) 开头';
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Debian 没有统一的官方单文件 rootfs，请填写一个 '
                    'aarch64 的 rootfs tarball 链接（支持 .tar.gz / .tar.xz）。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            TextFormField(
              controller: _dnsCtrl,
              decoration: const InputDecoration(
                labelText: 'DNS',
                hintText: '空格或逗号分隔，例如 1.1.1.1 8.8.8.8',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '保存后回到首页点击该实例即可部署（首次会下载 rootfs）。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
