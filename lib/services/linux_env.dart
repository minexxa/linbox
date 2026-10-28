import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:linbox/models/linux_instance.dart';

/// 本机 Linux（proot）环境的部署状态（针对「当前正在部署」的实例）。
enum LinuxEnvState {
  unknown,
  missing,
  downloading,
  extracting,
  ready,
  failed,
}

/// 部署失败时的错误（直接展示给用户，toString 不带前缀）。
class LinuxEnvException implements Exception {
  LinuxEnvException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 本机 Linux 环境（proot + rootfs）。
///
/// 每个 [LinuxInstance] 拥有独立目录 `files/linux/<id>/rootfs`，互不干扰。
/// 全部使用实例自身的配置（发行版 / 版本 / 镜像 / DNS），无全局默认值。
class LinuxEnv {
  LinuxEnv._();
  static final LinuxEnv instance = LinuxEnv._();

  /// 与 Android 侧 `MainActivity` 对应的通道，用于取 nativeLibraryDir。
  static const MethodChannel _channel = MethodChannel('linbox/proot');

  /// 部署完成标记（写在 rootfs 根目录）。
  static const String _markerName = '.linbox-installed';

  final ValueNotifier<LinuxEnvState> stateNotifier =
      ValueNotifier(LinuxEnvState.unknown);
  final ValueNotifier<double> progressNotifier = ValueNotifier(0);
  final ValueNotifier<String> messageNotifier = ValueNotifier('');

  String? error;
  LinuxEnvState get state => stateNotifier.value;
  double get progress => progressNotifier.value;
  String get message => messageNotifier.value;

  bool _installing = false;

  void _setState(LinuxEnvState s, {String msg = '', double? progress}) {
    stateNotifier.value = s;
    messageNotifier.value = msg;
    if (progress != null) progressNotifier.value = progress;
  }

  /// nativeLibraryDir：proot 以 `libproot.so` 打包在这里，
  /// 因为 targetSdk 36 下应用私有目录不允许 exec 可执行文件。
  Future<String> nativeLibraryDir() async {
    try {
      final dir =
          await _channel.invokeMethod<String>('getNativeLibraryDir');
      if (dir != null && dir.isNotEmpty) return dir;
    } catch (e) {
      debugPrint('getNativeLibraryDir failed: $e');
    }
    return '';
  }

  /// proot 可执行文件路径，不存在返回 null。
  Future<String?> prootPath() async {
    if (!Platform.isAndroid) return null;
    final dir = await nativeLibraryDir();
    if (dir.isEmpty) return null;
    final path = '$dir/libproot.so';
    return File(path).existsSync() ? path : null;
  }

  /// proot loader 路径（nativeLibraryDir 下才允许执行）。
  Future<String?> loaderPath() async {
    if (!Platform.isAndroid) return null;
    final dir = await nativeLibraryDir();
    if (dir.isEmpty) return null;
    final path = '$dir/libproot-loader.so';
    return File(path).existsSync() ? path : null;
  }

  /// 存放该实例 rootfs 的父目录（`<files>/linux/<id>`）。
  Future<Directory> linuxDir(LinuxInstance i) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/linux/${i.id}');
  }

  Future<Directory> rootfsDir(LinuxInstance i) async {
    final base = await linuxDir(i);
    return Directory('${base.path}/rootfs');
  }

  /// proot 的临时目录（宿主侧路径，必须可写）。
  ///
  /// proot 启动时要在这里建 glue rootfs（把 /dev /proc /sys 等宿主路径
  /// 接进容器）。它取 `PROOT_TMP_DIR`，回退 `TMPDIR`，最后是 `/tmp` ——
  /// Android 上 `/tmp` 不存在也不可写，于是报
  /// `can't create temporary directory: Permission denied` / `can't create
  /// glue rootfs`。这里给一个应用自己可写的目录。
  Future<Directory> prootTmpDir(LinuxInstance i) async {
    final base = await linuxDir(i);
    return Directory('${base.path}/ptmp');
  }

  Future<String> ensureProotTmpDir(LinuxInstance i) async {
    final dir = await prootTmpDir(i);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// rootfs 是否可用（标记文件存在且核心二进制存在）。
  Future<bool> isInstalled(LinuxInstance i) async {
    final dir = await rootfsDir(i);
    if (!File('${dir.path}/$_markerName').existsSync()) return false;
    // busybox(Alpine) 或 apt(Ubuntu/Debian) 实体文件确认 rootfs 完整。
    return File('${dir.path}/bin/busybox').existsSync() ||
        File('${dir.path}/usr/bin/apt').existsSync();
  }

  /// rootfs 占用字节数（递归统计，可能较慢）。
  Future<int> sizeBytes(LinuxInstance i) async {
    final dir = await rootfsDir(i);
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      try {
        if (entity is File) total += await entity.length();
      } catch (_) {}
    }
    return total;
  }

  /// 部署该实例的 rootfs。已部署则直接返回，重复调用安全。
  Future<void> install(LinuxInstance i) async {
    if (_installing) return;
    if (await isInstalled(i)) {
      _setState(LinuxEnvState.ready, msg: '已部署', progress: 1);
      return;
    }

    _installing = true;
    error = null;
    try {
      if (!Platform.isAndroid) {
        throw LinuxEnvException('本机 Linux 仅在 Android 上可用');
      }
      final proot = await prootPath();
      if (proot == null) {
        throw LinuxEnvException('缺少 proot（libproot.so 未随包安装）');
      }
      if (await loaderPath() == null) {
        throw LinuxEnvException(
            '缺少 proot loader（libproot-loader.so 未随包安装）');
      }

      final url = i.rootfsUrl;
      if (url.isEmpty) {
        throw LinuxEnvException(
            '未配置 rootfs 下载地址（Debian 需填写 Rootfs URL）');
      }

      final base = await linuxDir(i);
      if (!base.existsSync()) base.createSync(recursive: true);
      await ensureProotTmpDir(i);
      final rootfs = Directory('${base.path}/rootfs');
      // 上一轮解压不完整时直接重建，避免残留文件干扰。
      if (rootfs.existsSync()) rootfs.deleteSync(recursive: true);
      rootfs.createSync(recursive: true);
      final archive = File('${base.path}/rootfs.tar.gz');

      await _download(url, archive);
      await _extract(archive, rootfs);
      await _configure(rootfs, i);

      if (archive.existsSync()) archive.deleteSync();
      _setState(LinuxEnvState.ready, msg: '部署完成', progress: 1);
    } catch (e, st) {
      debugPrint('linux deploy failed: $e\n$st');
      error = e.toString();
      _setState(LinuxEnvState.failed, msg: e.toString());
    } finally {
      _installing = false;
    }
  }

  /// 清理该实例的 rootfs（下一个部署会重新下载）。
  Future<void> uninstall(LinuxInstance i) async {
    if (_installing) return;
    final base = await linuxDir(i);
    if (base.existsSync()) base.deleteSync(recursive: true);
    error = null;
    _setState(LinuxEnvState.missing, msg: '', progress: 0);
  }

  /// 下载 rootfs，进度写入 [progressNotifier]。
  Future<void> _download(String url, File target) async {
    _setState(LinuxEnvState.downloading, msg: '下载 rootfs…', progress: 0);

    final client = HttpClient();
    HttpClientRequest request;
    try {
      request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'linbox');
    } catch (e) {
      client.close(force: true);
      throw LinuxEnvException('无法连接镜像：$e');
    }

    HttpClientResponse response;
    try {
      response = await request.close();
    } catch (e) {
      client.close(force: true);
      throw LinuxEnvException('下载失败：$e');
    }

    if (response.statusCode != 200) {
      client.close(force: true);
      throw LinuxEnvException('镜像返回 ${response.statusCode}');
    }

    final total = response.contentLength;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final ratio = total > 0 ? received / total : 0.0;
        progressNotifier.value = 0.85 * ratio.clamp(0.0, 1.0);
        messageNotifier.value = total > 0
            ? '下载：${_humanBytes(received)} / ${_humanBytes(total)}'
            : '下载：${_humanBytes(received)}';
      }
      await sink.flush();
    } catch (e) {
      throw LinuxEnvException('下载中断：$e');
    } finally {
      await sink.close();
      client.close(force: true);
    }

    if (received == 0) throw LinuxEnvException('下载内容为空');
  }

  /// 解压 rootfs：gzip / xz 先由 archive 解压成纯 tar 文件，再统一交给
  /// 设备端 toybox tar 解包。toybox 在 Android 上必然存在，这是
  /// server_box / fl_tty 等成熟项目的通用做法；不再依赖 archive 的 tar
  /// 流式 API（不同版本差异大、易编译失败）。
  Future<void> _extract(File archive, Directory rootfs) async {
    _setState(LinuxEnvState.extracting, msg: '解压 rootfs…', progress: 0.88);

    final detail = <String>[];
    final bytes = await archive.readAsBytes();
    final xz = _isXz(bytes);

    var ok = false;
    Uint8List tarBytes;
    try {
      tarBytes = xz
          ? XzDecoder().decodeBytes(bytes)
          : GZipDecoder().decodeBytes(bytes);
    } on Exception catch (e) {
      // gzip 可能不是标准头（如 alpine 用的 gzip 变体），尝试 toybox 管道。
      if (!xz) {
        final r1 = await _gzPipe(archive, rootfs);
        detail.add('gzip|tar: ${r1 ? 'ok' : 'fail'}');
        ok = r1;
        if (ok) {
          _verifyExtracted(rootfs, detail.join('；'));
          return;
        }
      }
      final info = detail.join('；');
      throw LinuxEnvException('解压失败（${xz ? 'xz' : 'gzip'}：$e；$info）');
    }

    // 解出的 tar 交给 toybox tar 落盘。
    final tarFile = File('${archive.parent.path}/rootfs.tar');
    await tarFile.writeAsBytes(tarBytes);
    ok = await _tarXf(tarFile, rootfs);
    detail.add('${xz ? 'xz' : 'gzip'}→tar: ${ok ? 'ok' : 'fail'}');
    if (!ok) {
      // toybox 不可用时（极端环境）退回 gzip 管道。
      if (!xz) {
        final r1 = await _gzPipe(archive, rootfs);
        detail.add('gzip|tar: ${r1 ? 'ok' : 'fail'}');
        ok = r1;
      }
    }

    _verifyExtracted(rootfs, detail.join('；'));
  }

  /// 校验解压结果：至少存在 busybox(Alpine) 或 apt(Ubuntu/Debian)。
  void _verifyExtracted(Directory rootfs, String info) {
    if (!File('${rootfs.path}/bin/busybox').existsSync() &&
        !File('${rootfs.path}/usr/bin/apt').existsSync()) {
      throw LinuxEnvException('rootfs 不完整：$info');
    }
    progressNotifier.value = 0.95;
  }

  /// toybox 管道：`gzip -dc | tar -xf -`（最快的 gzip 直解路径）。
  Future<bool> _gzPipe(File archive, Directory rootfs) async {
    try {
      final result = await Process.run('/system/bin/sh', [
        '-c',
        '/system/bin/gzip -dc "${archive.path}" | /system/bin/tar -xf - -C "${rootfs.path}"',
      ]);
      if (result.exitCode == 0) {
        return File('${rootfs.path}/bin/busybox').existsSync() ||
            File('${rootfs.path}/usr/bin/apt').existsSync();
      }
      debugPrint('gzPipe failed: ${result.exitCode} ${result.stderr}');
    } catch (e) {
      debugPrint('gzPipe error: $e');
    }
    return false;
  }

  /// 已解出的 .tar 文件交给 toybox tar 解压。
  Future<bool> _tarXf(File tarFile, Directory rootfs) async {
    try {
      final result = await Process.run(
        '/system/bin/tar',
        ['-xf', tarFile.path, '-C', rootfs.path],
      );
      if (result.exitCode == 0) {
        return File('${rootfs.path}/bin/busybox').existsSync() ||
            File('${rootfs.path}/usr/bin/apt').existsSync();
      }
      debugPrint('tar failed: ${result.exitCode} ${result.stderr}');
    } catch (e) {
      debugPrint('tar error: $e');
    }
    return false;
  }

  /// 写入 DNS / 软件源 / hosts，让 apt/apk 与网络开箱可用。
  Future<void> _configure(Directory rootfs, LinuxInstance i) async {
    _setState(LinuxEnvState.extracting, msg: '写入配置…', progress: 0.96);

    final etc = Directory('${rootfs.path}/etc');
    if (!etc.existsSync()) etc.createSync(recursive: true);

    File('${etc.path}/resolv.conf')
        .writeAsStringSync('${i.dnsList.map((d) => 'nameserver $d').join('\n')}\n');

    for (final e in i.distro.repoFiles(i.mirrorUrl, i.version).entries) {
      final f = File('${rootfs.path}${e.key}');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value);
    }

    // rootfs 里可能缺少 hosts，补一个最小的，避免解析 localhost 失败。
    File('${etc.path}/hosts').writeAsStringSync(
      '127.0.0.1\tlocalhost\n'
      '::1\tlocalhost ip6-localhost ip6-loopback\n',
    );

    // proot 下 /tmp 与 /root 必须可写/存在。
    final tmp = Directory('${rootfs.path}/tmp');
    if (!tmp.existsSync()) tmp.createSync(recursive: true);
    final home = Directory('${rootfs.path}/root');
    if (!home.existsSync()) home.createSync(recursive: true);

    // 部署标记（判定是否已安装；bin/sh 是绝对链接，不能用来判断）。
    File('${rootfs.path}/$_markerName')
        .writeAsStringSync('${i.distro.id} ${i.version}\n');
  }

  static bool _isXz(Uint8List bytes) =>
      bytes.length >= 6 &&
      bytes[0] == 0xfd &&
      bytes[1] == 0x37 &&
      bytes[2] == 0x7a &&
      bytes[3] == 0x5a &&
      bytes[4] == 0x00;

  static String _normalize(String name) {
    var n = name;
    if (n.startsWith('./')) n = n.substring(2);
    while (n.startsWith('/')) n = n.substring(1);
    if (n.isEmpty || n.contains('..')) return '';
    return n;
  }
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 供 UI 展示的部署状态文案。
extension LinuxEnvStateX on LinuxEnvState {
  String get label => switch (this) {
        LinuxEnvState.unknown => '检查中',
        LinuxEnvState.missing => '未部署',
        LinuxEnvState.downloading => '下载中',
        LinuxEnvState.extracting => '部署中',
        LinuxEnvState.ready => '已部署',
        LinuxEnvState.failed => '部署失败',
      };
}
