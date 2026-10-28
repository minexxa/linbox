import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 终端选区两端的可拖动手柄（类似系统文本选择的水滴图标）。
///
/// 放在 [TerminalView] 同一个 [Stack] 里、位于其上方（通常用
/// `Positioned.fill`）。只在有选区时才需要创建。
///
/// - 拖动任一手柄即可调整对应一端的选区；
/// - 手指靠近终端上/下边缘时自动滚动，便于跨屏选择；
/// - 终端滚动、输出变化时手柄位置会跟随更新。
class SelectionHandles extends StatefulWidget {
  const SelectionHandles({
    super.key,
    required this.terminalKey,
    required this.terminal,
    required this.controller,
    required this.scrollController,
    this.color = const Color(0xFF2196F3),
  });

  final GlobalKey<TerminalViewState> terminalKey;
  final Terminal terminal;
  final TerminalController controller;
  final ScrollController scrollController;
  final Color color;

  @override
  State<SelectionHandles> createState() => _SelectionHandlesState();
}

class _SelectionHandlesState extends State<SelectionHandles> {
  static const double _radius = 11;
  static const double _boxW = _radius * 2 + 10;
  static const double _boxH = _radius * 2 + 18;
  static const double _tipMargin = 5;

  bool _frameScheduled = false;

  // 拖动状态
  bool _dragBase = false;
  CellOffset? _fixed;
  Offset _grab = Offset.zero;
  Offset? _lastFinger;
  Timer? _autoScroll;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.scrollController.addListener(_refresh);
    widget.terminal.addListener(_refresh);
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    widget.controller.removeListener(_refresh);
    widget.scrollController.removeListener(_refresh);
    widget.terminal.removeListener(_refresh);
    super.dispose();
  }

  /// 滚动 / 输出可能发生在布局阶段，统一延后到帧末再重建，
  /// 这样读到的是最新的布局结果。
  void _refresh() {
    if (!mounted || _frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  RenderTerminal? get _render {
    final state = widget.terminalKey.currentState;
    if (state == null) return null;
    try {
      final r = state.renderTerminal;
      return r.attached ? r : null;
    } catch (_) {
      return null;
    }
  }

  RenderBox? get _self {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return ro;
    return null;
  }

  /// 某个单元格左边界、行底边处的点（本组件坐标系）。
  Offset? _anchorPoint(CellOffset cell) {
    final r = _render;
    final box = _self;
    if (r == null || box == null) return null;
    final local = r.getOffset(cell) + Offset(0, r.lineHeight);
    return box.globalToLocal(r.localToGlobal(local));
  }

  // ───────── 拖动 ─────────

  void _onDragStart(DragStartDetails d, bool isBase) {
    final sel = widget.controller.selection;
    final r = _render;
    if (sel == null || r == null) return;
    _dragBase = isBase;
    _fixed = isBase ? sel.end : sel.begin;
    final moving = isBase ? sel.begin : sel.end;
    final anchorGlobal =
        r.localToGlobal(r.getOffset(moving) + Offset(0, r.lineHeight));
    _grab = d.globalPosition - anchorGlobal;
    _lastFinger = d.globalPosition;
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _autoScrollTick(),
    );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _lastFinger = d.globalPosition;
    _applyDrag();
  }

  void _onDragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _fixed = null;
    _lastFinger = null;
  }

  void _applyDrag() {
    final r = _render;
    final fixed = _fixed;
    final finger = _lastFinger;
    if (r == null || fixed == null || finger == null) return;

    // 手柄“尖角”应该对着的位置 = 手指位置 - 抓取偏移。
    final local = r.globalToLocal(finger - _grab);
    final cw = r.cellSize.width;
    final ch = r.lineHeight;
    if (cw <= 0 || ch <= 0) return;

    // 尖角在行底边：取其上方半行判定所在行；
    // 列取最近的单元格边界（允许到行尾 = viewWidth）。
    final origin = r.getOffset(const CellOffset(0, 0));
    final col = math.max(
      0,
      math.min(((local.dx - origin.dx) / cw).round(), widget.terminal.viewWidth),
    );
    final row = r.getCellOffset(Offset(origin.dx, local.dy - ch / 2)).y;
    final moving = CellOffset(col, row);

    final buf = widget.terminal.buffer;
    widget.controller.setSelection(
      buf.createAnchorFromOffset(_dragBase ? moving : fixed),
      buf.createAnchorFromOffset(_dragBase ? fixed : moving),
    );
  }

  /// 手指靠近上/下边缘时自动滚动，并持续更新选区。
  void _autoScrollTick() {
    final finger = _lastFinger;
    final box = _self;
    final r = _render;
    final sc = widget.scrollController;
    if (finger == null || box == null || r == null || !sc.hasClients) return;

    const edge = 40.0;
    final y = box.globalToLocal(finger).dy;
    double delta = 0;
    if (y < edge) {
      delta = -r.lineHeight * 0.6;
    } else if (y > box.size.height - edge) {
      delta = r.lineHeight * 0.6;
    }
    if (delta == 0) return;

    final pos = sc.position;
    final target = math.max(
      pos.minScrollExtent,
      math.min(pos.pixels + delta, pos.maxScrollExtent),
    );
    if (target == pos.pixels) return;
    sc.jumpTo(target);
    _applyDrag();
  }

  // ───────── 构建 ─────────

  @override
  Widget build(BuildContext context) {
    final sel = widget.controller.selection;
    final box = _self;
    if (sel == null || box == null) {
      return const Stack();
    }

    final startIsBase = sel.isNormalized;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        _buildHandle(
          cell: sel.begin,
          isBase: true,
          isStart: startIsBase,
          boxHeight: box.size.height,
        ),
        _buildHandle(
          cell: sel.end,
          isBase: false,
          isStart: !startIsBase,
          boxHeight: box.size.height,
        ),
      ],
    );
  }

  Widget _buildHandle({
    required CellOffset cell,
    required bool isBase,
    required bool isStart,
    required double boxHeight,
  }) {
    final p = _anchorPoint(cell);
    // 选区端点滚出可视区域时隐藏手柄。
    if (p == null || p.dy < 0 || p.dy > boxHeight) {
      return const SizedBox.shrink();
    }
    // 起点手柄的水滴在尖角左侧，终点手柄在右侧（与系统一致，
    // 选中单个字符时两个手柄不会重叠）。
    final tipX = isStart ? _boxW - _tipMargin : _tipMargin;
    return Positioned(
      key: ValueKey(isBase ? 'base' : 'extent'),
      left: p.dx - tipX,
      top: p.dy,
      width: _boxW,
      height: _boxH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _onDragStart(d, isBase),
        onPanUpdate: _onDragUpdate,
        onPanEnd: (_) => _onDragEnd(),
        onPanCancel: _onDragEnd,
        child: CustomPaint(
          painter: _HandlePainter(
            color: widget.color,
            isStart: isStart,
            tipX: tipX,
            radius: _radius,
          ),
        ),
      ),
    );
  }
}

/// 水滴形手柄：圆 + 靠近尖角的方形象限。
class _HandlePainter extends CustomPainter {
  _HandlePainter({
    required this.color,
    required this.isStart,
    required this.tipX,
    required this.radius,
  });

  final Color color;
  final bool isStart;
  final double tipX;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final cx = isStart ? tipX - radius : tipX + radius;
    final cy = radius;
    canvas.drawCircle(Offset(cx, cy), radius, paint);
    // 尖角所在象限补成直角。
    final rect = isStart
        ? Rect.fromLTRB(cx, 0, cx + radius, radius)
        : Rect.fromLTRB(cx - radius, 0, cx, radius);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_HandlePainter old) =>
      old.color != color ||
      old.isStart != isStart ||
      old.tipX != tipX ||
      old.radius != radius;
}
