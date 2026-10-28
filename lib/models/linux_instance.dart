import 'package:uuid/uuid.dart';

import 'package:linbox/models/linux_distro.dart';

/// 一个本机 Linux 实例（proot）。
///
/// 每个实例拥有独立 rootfs 目录，互不干扰，可在首页并存多个。
class LinuxInstance {
  LinuxInstance({
    String? id,
    required this.name,
    required this.flavorId,
    required this.version,
    required this.mirrorUrl,
    this.customRootfsUrl,
    this.dns = '1.1.1.1 8.8.8.8',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final String flavorId;
  String version;
  String mirrorUrl;

  /// Debian 专用：rootfs tarball 的完整 URL（gz / xz 均可）。
  String? customRootfsUrl;

  /// 空格 / 逗号分隔的 DNS 服务器。
  String dns;
  final DateTime createdAt;

  DistroDef get distro => LinuxDistro.byId(flavorId) ?? LinuxDistro.alpine;

  String get distroLabel => distro.label;

  List<String> get dnsList =>
      dns.split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).toList();

  /// 实际用于下载的 rootfs 地址。
  String get rootfsUrl => distro.supportsRootfsMirror
      ? distro.rootfsUrl(mirrorUrl, version)
      : (customRootfsUrl ?? '');

  LinuxInstance copyWith({
    String? name,
    String? flavorId,
    String? version,
    String? mirrorUrl,
    String? customRootfsUrl,
    String? dns,
  }) =>
      LinuxInstance(
        id: id,
        name: name ?? this.name,
        flavorId: flavorId ?? this.flavorId,
        version: version ?? this.version,
        mirrorUrl: mirrorUrl ?? this.mirrorUrl,
        customRootfsUrl: customRootfsUrl ?? this.customRootfsUrl,
        dns: dns ?? this.dns,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'flavorId': flavorId,
        'version': version,
        'mirrorUrl': mirrorUrl,
        if (customRootfsUrl != null) 'customRootfsUrl': customRootfsUrl,
        'dns': dns,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LinuxInstance.fromJson(Map<String, dynamic> json) => LinuxInstance(
        id: json['id'] as String,
        name: json['name'] as String,
        flavorId: json['flavorId'] as String,
        version: json['version'] as String,
        mirrorUrl: json['mirrorUrl'] as String,
        customRootfsUrl: json['customRootfsUrl'] as String?,
        dns: (json['dns'] as String?) ?? '1.1.1.1 8.8.8.8',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
