/// 镜像（rootfs 下载基址 / 软件源基址）。
class Mirror {
  const Mirror(this.id, this.label, this.url);

  final String id;
  final String label;
  final String url;

  @override
  String toString() => '$label ($url)';
}

/// 一个受支持的 Linux 发行版。
///
/// Alpine 与 Ubuntu 的 rootfs 为官方单文件 tarball，可直接下载；
/// Debian 没有统一稳定的官方单文件 tarball，因此由用户填写 rootfs URL，
/// 这里只负责 apt 软件源。
class DistroDef {
  const DistroDef({
    required this.id,
    required this.label,
    required this.shell,
    required this.packageManager,
    required this.versions,
    required this.mirrors,
    required this.defaultDns,
    required this.arch,
    this.supportsRootfsMirror = true,
  });

  final String id;
  final String label;

  /// 进入环境后启动的 shell。
  final String shell;

  /// 包管理器：`apk` 或 `apt`。
  final String packageManager;

  /// 可选版本（新 → 旧）。
  final List<String> versions;

  /// 可选镜像（rootfs 下载基址 / apt 源基址）。
  final List<Mirror> mirrors;

  final List<String> defaultDns;

  final String arch;

  /// 是否支持「镜像下拉」（rootfs 来自镜像）。
  /// false 时（Debian）rootfs 由用户填写完整 URL。
  final bool supportsRootfsMirror;

  String get defaultVersion => versions.first;
  Mirror get defaultMirror => mirrors.first;
  List<String> get defaultDnsList => defaultDns;

  /// 主版本号：`3.22.5` → `v3.22`。
  static String majorOf(String version) {
    final parts = version.split('.');
    if (parts.length < 2) return version;
    return '${parts[0]}.${parts[1]}';
  }

  /// rootfs 压缩包地址（Debian 不适用）。
  String rootfsUrl(String mirrorUrl, String version) {
    switch (id) {
      case 'alpine':
        final major = 'v${majorOf(version)}';
        return '$mirrorUrl/alpine/$major/releases/$arch/'
            'alpine-minirootfs-$version-$arch.tar.gz';
      case 'ubuntu':
        return '$mirrorUrl/releases/$version/release/'
            'ubuntu-base-$version-base-$arch.tar.gz';
      default:
        return '';
    }
  }

  /// 需要写入 rootfs 的软件源文件（相对 rootfs 的路径 → 内容）。
  Map<String, String> repoFiles(String mirrorUrl, String version) {
    switch (id) {
      case 'alpine':
        final major = 'v${majorOf(version)}';
        return {
          '/etc/apk/repositories':
              '$mirrorUrl/alpine/$major/main\n$mirrorUrl/alpine/$major/community\n',
        };
      case 'ubuntu':
        final codename = _ubuntuCodename(version);
        // arm64 的 apt 源在 ubuntu-ports。
        const apt = 'http://ports.ubuntu.com/ubuntu-ports';
        return {
          '/etc/apt/sources.list':
              'deb $apt $codename main universe\n'
              'deb $apt $codename-updates main universe\n'
              'deb $apt $codename-security main universe\n',
        };
      case 'debian':
        final codename = _debianCodename(version);
        return {
          '/etc/apt/sources.list':
              'deb $mirrorUrl $codename main\n'
              'deb $mirrorUrl $codename-updates main\n'
              'deb $mirrorUrl $codename-security main\n',
        };
      default:
        return {};
    }
  }

  static String _ubuntuCodename(String version) {
    return const {
      '24.04.5': 'noble',
      '24.04': 'noble',
      '22.04': 'jammy',
    }[version] ?? 'noble';
  }

  static String _debianCodename(String version) {
    return const {
      '12 (bookworm)': 'bookworm',
      '11 (bullseye)': 'bullseye',
    }[version] ?? 'bookworm';
  }
}

/// 所有受支持的发行版。
class LinuxDistro {
  LinuxDistro._();

  static const String arch = 'aarch64';

  static const DistroDef alpine = DistroDef(
    id: 'alpine',
    label: 'Alpine',
    shell: '/bin/sh',
    packageManager: 'apk',
    arch: arch,
    versions: ['3.22.5', '3.22.4', '3.22.3', '3.22.2', '3.21.7'],
    defaultDns: ['1.1.1.1', '8.8.8.8'],
    mirrors: [
      Mirror('official', '官方 (dl-cdn)', 'https://dl-cdn.alpinelinux.org'),
      Mirror('tuna', '清华', 'https://mirrors.tuna.tsinghua.edu.cn/alpine'),
      Mirror('aliyun', '阿里', 'https://mirrors.aliyun.com/alpine'),
      Mirror('ustc', '中科大', 'https://mirrors.ustc.edu.cn/alpine'),
    ],
  );

  static const DistroDef ubuntu = DistroDef(
    id: 'ubuntu',
    label: 'Ubuntu',
    shell: '/bin/sh',
    packageManager: 'apt',
    arch: arch,
    versions: ['24.04.5', '22.04'],
    defaultDns: ['1.1.1.1', '8.8.8.8'],
    mirrors: [
      Mirror('official', '官方 (cdimages)', 'https://cdimages.ubuntu.com/ubuntu-base'),
    ],
  );

  static const DistroDef debian = DistroDef(
    id: 'debian',
    label: 'Debian',
    shell: '/bin/sh',
    packageManager: 'apt',
    arch: arch,
    supportsRootfsMirror: false,
    versions: ['12 (bookworm)', '11 (bullseye)'],
    defaultDns: ['1.1.1.1', '8.8.8.8'],
    mirrors: [
      Mirror('official', '官方 (deb.debian.org)', 'https://deb.debian.org/debian'),
      Mirror('tuna', '清华', 'https://mirrors.tuna.tsinghua.edu.cn/debian'),
      Mirror('aliyun', '阿里', 'https://mirrors.aliyun.com/debian'),
    ],
  );

  static const List<DistroDef> all = [alpine, ubuntu, debian];

  static DistroDef? byId(String? id) =>
      all.where((d) => d.id == id).firstOrNull;
}
