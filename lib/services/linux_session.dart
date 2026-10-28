import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'package:linbox/models/linux_instance.dart';
import 'package:linbox/services/linux_env.dart';

/// 本机 Linux（proot）shell 会话状态。
enum LinuxSessionState { idle, connecting, connected, disconnected, failed }

/// 本机 Linux（proot + rootfs）shell 会话。
///
/// 与原本机终端同构：真 PTY，支持 resize、交互程序、提示符。
/// 区别是执行的不是 `/system/bin/sh`，而是
/// `libproot.so -r rootfs ... /bin/sh -l`。
class LinuxSession {
  LinuxSession(this.instance);

  final LinuxInstance instance;

  final terminal = Terminal(maxLines: 10000);
  final controller = TerminalController();

  Pty? _pty;
  StreamSubscription<Uint8List>? _outSub;

  LinuxSessionState _state = LinuxSessionState.idle;
  LinuxSessionState get state => _state;

  String? errorMessage;

  final ValueNotifier<LinuxSessionState> stateNotifier =
      ValueNotifier(LinuxSessionState.idle);

  var _exited = false;

  void _setState(LinuxSessionState s) {
    _state = s;
    stateNotifier.value = s;
  }

  /// 传给 proot 的参数（按发行版的 shell 与存在性绑定共享存储）。
  static List<String> _prootArgs(String rootfs, String shell) {
    // 必须绑定：容器内需要可用的 /dev、/proc、/sys。
    final binds = <String>['/dev:/dev', '/proc:/proc', '/sys:/sys'];
    // 共享存储按需绑定：部分设备没有 /sdcard，绑定不存在的目录会让 proot 退出。
    for (final path in const ['/sdcard', '/storage', '/mnt']) {
      if (Directory(path).existsSync()) binds.add('$path:$path');
    }

    return [
      '--kill-on-exit',
      '--link2symlink',
      '-0', // fake root：提示符为 root@，apt/apk 可写 /root
      '-r', rootfs,
      '-w', '/root',
      for (final b in binds) ...['-b', b],
      shell,
      '-l',
    ];
  }

  static const Map<String, String> _env = {
    'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    'HOME': '/root',
    'SHELL': '/bin/sh',
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    'LANG': 'C.UTF-8',
    'PWD': '/root',
    'USER': 'root',
    // 禁用 seccomp，回退到 ptrace 后端：arm64 上 proot 默认用 seccomp
    // 拦截 syscall，会把 ping / nano 等程序的某些 syscall 拦掉并返回
    // ENOSYS（终端表现为 "Bad system call"）。关闭后由 ptrace 透明转发，
    // 这些程序即可正常运行。
    'PROOT_NO_SECCOMP': '1',
    // 注意：TMPDIR 不能写成 '/tmp' —— proot 建 glue rootfs 时读的是
    // 宿主视角的这个变量，Android 上没有可写的 /tmp。真正的值在
    // [connect] 里和 PROOT_TMP_DIR 一起指向应用私有目录。
  };

  Future<void> connect() async {
    if (_state == LinuxSessionState.connecting ||
        _state == LinuxSessionState.connected) {
      return;
    }

    _setState(LinuxSessionState.connecting);
    errorMessage = null;
    _exited = false;

    try {
      final env = LinuxEnv.instance;

      final rootfs = await env.rootfsDir(instance);
      if (!await env.isInstalled(instance)) {
        throw LinuxEnvException('${instance.name} 未部署，请先在设置中部署');
      }
      final proot = await env.prootPath();
      if (proot == null) {
        throw LinuxEnvException('找不到 proot（libproot.so）');
      }
      // proot 必须自带 loader 才能执行 rootfs 里的二进制：
      // targetSdk 29+ 下应用目录不可 exec，loader 在 nativeLibraryDir 才可执行。
      final loader = await env.loaderPath();
      if (loader == null) {
        throw LinuxEnvException('找不到 proot loader（libproot-loader.so）');
      }
      // 宿主机视角的可写临时目录：proot 在这里建 glue rootfs。
      final tmpDir = await env.ensureProotTmpDir(instance);

      final cols = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      final rows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      final pty = Pty.start(
        proot,
        arguments: _prootArgs(rootfs.path, instance.distro.shell),
        environment: {
          ..._env,
          'PROOT_LOADER': loader,
          'PROOT_TMP_DIR': tmpDir,
          'TMPDIR': tmpDir,
        },
        workingDirectory: rootfs.path,
        rows: rows,
        columns: cols,
      );
      _pty = pty;

      // xterm → PTY（utf8.encode 的结果本身就是 Uint8List）
      terminal.onOutput = (data) {
        _pty?.write(utf8.encode(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width > 0 && height > 0) {
          _pty?.resize(height, width);
        }
      };

      _outSub = pty.output.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: _onPtyDone,
        onError: (e) {
          terminal.write('\r\n\x1b[31mpty error: $e\x1b[0m\r\n');
        },
      );

      unawaited(pty.exitCode.then((_) => _onPtyDone()));

      _setState(LinuxSessionState.connected);
    } catch (e, st) {
      debugPrint('linux session failed: $e\n$st');
      errorMessage = e.toString();
      terminal.write('\r\n\x1b[31mLinux 启动失败: $e\x1b[0m\r\n');
      _setState(LinuxSessionState.failed);
      await close();
    }
  }

  void _onPtyDone() {
    if (_exited) return;
    _exited = true;
    if (_state == LinuxSessionState.disconnected) return;
    _setState(LinuxSessionState.disconnected);
  }

  Future<void> close() async {
    await _outSub?.cancel();
    _outSub = null;

    final pty = _pty;
    _pty = null;
    if (pty != null && !_exited) {
      // 先 SIGHUP 进程组，超时再 SIGKILL。
      if (!Platform.isWindows) {
        try {
          Process.killPid(-pty.pid, ProcessSignal.sighup);
        } catch (_) {}
      }
      try {
        pty.kill(ProcessSignal.sighup);
      } catch (_) {}
      Future.delayed(const Duration(seconds: 3), () {
        if (_exited) return;
        try {
          pty.kill(ProcessSignal.sigkill);
        } catch (_) {}
      });
    }

    if (_state != LinuxSessionState.failed) {
      _setState(LinuxSessionState.disconnected);
    }
  }

  Future<void> reconnect() async {
    await close();
    await Future.delayed(const Duration(milliseconds: 100));
    await connect();
  }

  void dispose() {
    close();
    stateNotifier.dispose();
  }
}
