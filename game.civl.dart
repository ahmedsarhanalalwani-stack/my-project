import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CivilSimApp());
}

class CivilSimApp extends StatelessWidget {
  const CivilSimApp({super.key});

  @override
  Widget build(BuildContext context) {
    final game = CivilSimGame();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Civil Sim: Structural Integrity',
      home: Scaffold(
        body: GameWidget<CivilSimGame>(
          game: game,
          overlayBuilderMap: {
            GameHud.overlayId: (context, game) => GameHud(game: game),
          },
          initialActiveOverlays: const [GameHud.overlayId],
        ),
      ),
    );
  }
}

enum BuildMode { steelBeam, cable }

enum SimState { build, running, win, fail }

///
/// Civil Sim: Structural Integrity
///
/// ملف واحد فقط يحتوي على:
/// - Flutter app
/// - Flame + Forge2D game
/// - Grid rendering
/// - Anchor nodes
/// - Bridge members
/// - Vehicle
/// - HUD overlay
///
/// ملاحظة هندسية:
/// هذه النسخة مصممة كـ MVP / Portfolio Starter.
/// هي تستخدم Forge2D للجاذبية وحركة المركبة والتصادم، وتستخدم
/// stress approximation مبسط للأعضاء الإنشائية لعرض الألوان والانهيار.
/// لو حبيت نسخة أكثر واقعية لاحقًا، نقدر نحوّل العناصر إلى joint-network.
///
class CivilSimGame extends Forge2DGame with TapCallbacks {
  CivilSimGame() : super(gravity: Vector2(0, 16), zoom: 14);

  final ValueNotifier<int> hudTick = ValueNotifier<int>(0);

  final List<AnchorNode> nodes = [];
  final List<BridgeMember> members = [];

  late final ConstructionGrid grid;

  Vehicle? vehicle;

  BuildMode buildMode = BuildMode.steelBeam;
  SimState simState = SimState.build;

  AnchorNode? selectedNode;

  double totalBudget = 1400;
  double usedBudget = 0;

  String statusText = 'ابدأ في بناء الجسر';
  String levelTitle = 'Civil Sim: Structural Integrity';

  double get remainingBudget =>
      (totalBudget - usedBudget).clamp(0, totalBudget);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.anchor = Anchor.topLeft;

    grid = ConstructionGrid(worldSize: Vector2(90, 50), cellSize: 2);
    add(grid);

    _createTerrain();
    _createAnchorNodes();

    statusText = 'اختَر نقطتين لبناء Beam أو Cable';
    _refreshHud();
  }

  void _createTerrain() {
    addAll([
      GroundPlatform(position: Vector2(10, 39), size: Vector2(22, 4)),
      GroundPlatform(position: Vector2(80, 39), size: Vector2(22, 4)),
    ]);
  }

  void _createAnchorNodes() {
    final foundation = <Vector2>[
      Vector2(20, 30),
      Vector2(20, 26),
      Vector2(20, 22),
      Vector2(20, 18),
      Vector2(70, 30),
      Vector2(70, 26),
      Vector2(70, 22),

      Vector2(70, 18),
    ];

    final middle = <Vector2>[
      Vector2(28, 30),
      Vector2(34, 28),
      Vector2(40, 26),
      Vector2(45, 24),
      Vector2(50, 26),
      Vector2(56, 28),
      Vector2(62, 30),

      Vector2(28, 22),
      Vector2(34, 20),
      Vector2(40, 18),
      Vector2(45, 16),
      Vector2(50, 18),
      Vector2(56, 20),
      Vector2(62, 22),
    ];

    for (final p in foundation) {
      final node = AnchorNode(position: p, isFoundation: true);

      nodes.add(node);
      add(node);
    }

    for (final p in middle) {
      final node = AnchorNode(position: p, isFoundation: false);
      nodes.add(node);
      add(node);
    }
  }

  void _refreshHud() {
    hudTick.value++;
  }

  void selectBuildMode(BuildMode mode) {
    if (simState != SimState.build) return;
    buildMode = mode;
    statusText = mode == BuildMode.steelBeam
        ? 'وضع البناء: Steel Beam'
        : 'وضع البناء: Cable';
    _refreshHud();
  }

  void undoLast() {
    if (simState != SimState.build || members.isEmpty) return;

    final last = members.removeLast();
    usedBudget -= last.cost;
    last.removeFromParent();

    statusText = 'تم حذف آخر عنصر';
    _refreshHud();
  }

  void resetLevel() {
    for (final member in [...members]) {
      member.removeFromParent();
    }
    members.clear();

    vehicle?.removeFromParent();
    vehicle = null;

    for (final node in nodes) {
      node.isSelected = false;
    }

    selectedNode = null;
    usedBudget = 0;
    simState = SimState.build;
    statusText = 'تمت إعادة المستوى. ابدأ البناء من جديد';
    _refreshHud();
  }

  void startSimulation() {
    if (simState != SimState.build) return;

    if (members.isEmpty) {
      statusText = 'ابنِ بعض العناصر أولًا';
      _refreshHud();
      return;
    }

    selectedNode?.isSelected = false;
    selectedNode = null;

    simState = SimState.running;
    statusText = 'بدأت المحاكاة';
    _spawnVehicle();

    _refreshHud();
  }

  void _spawnVehicle() {
    vehicle?.removeFromParent();
    vehicle = Vehicle(position: Vector2(8, 34.2));
    add(vehicle!);
  }

  AnchorNode? _findNearestNode(Vector2 point) {
    AnchorNode? result;
    double bestDistance = double.infinity;

    for (final node in nodes) {
      final d = node.body.position.distanceTo(point);
      if (d < 1.2 && d < bestDistance) {
        bestDistance = d;
        result = node;
      }
    }

    return result;
  }

  void _handleBuildTap(Vector2 worldPoint) {
    if (simState != SimState.build) return;

    final tappedNode = _findNearestNode(worldPoint);
    if (tappedNode == null) return;

    if (selectedNode == null) {
      selectedNode = tappedNode;
      tappedNode.isSelected = true;
      statusText = 'اختَر نقطة النهاية';
      _refreshHud();
      return;
    }

    if (selectedNode == tappedNode) {
      tappedNode.isSelected = false;
      selectedNode = null;
      statusText = 'تم إلغاء الاختيار';
      _refreshHud();
      return;
    }

    final start = selectedNode!;
    final end = tappedNode;

    start.isSelected = false;
    selectedNode = null;

    _tryAddMember(start, end);
    _refreshHud();
  }

  void _tryAddMember(AnchorNode a, AnchorNode b) {
    final exists = members.any(
      (m) =>
          (m.startNode == a && m.endNode == b) ||
          (m.startNode == b && m.endNode == a),
    );

    if (exists) {
      statusText = 'هذا العنصر موجود بالفعل';
      return;
    }

    final length = a.body.position.distanceTo(b.body.position);

    if (length < 1.0) {
      statusText = 'المسافة قصيرة جدًا';
      return;
    }

    if (length > 16.0) {
      statusText = 'المسافة طويلة جدًا على عنصر واحد';
      return;
    }

    final isCable = buildMode == BuildMode.cable;
    final unitCost = isCable ? 8.0 : 15.0;
    final maxStress = isCable ? 70.0 : 115.0;
    final cost = length * unitCost;

    if (remainingBudget < cost) {
      statusText = 'الميزانية غير كافية';
      return;
    }

    final member = BridgeMember(
      startNode: a,
      endNode: b,
      memberType: isCable ? BridgeMemberType.cable : BridgeMemberType.steelBeam,
      maximumStress: maxStress,
      cost: cost,
    );

    members.add(member);
    usedBudget += cost;
    add(member);

    statusText = isCable ? 'تمت إضافة Cable' : 'تمت إضافة Steel Beam';
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    final worldPoint = screenToWorld(event.localPosition);
    _handleBuildTap(worldPoint);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (simState == SimState.running) {
      vehicle?.driveForward();
      _updateStressAndBreaks();
      _checkGameState();
      _refreshHud();
    }
  }

  void _updateStressAndBreaks() {
    final failedMembers = <BridgeMember>[];
    final adjacency = _buildAdjacencyMap();

    for (final member in members) {
      final startDegree = adjacency[member.startNode] ?? 0;
      final endDegree = adjacency[member.endNode] ?? 0;

      member.updateStress(
        vehicle: vehicle,
        startConnections: startDegree,
        endConnections: endDegree,
      );

      if (member.normalizedStress >= 1.0) {
        failedMembers.add(member);
      }
    }

    if (failedMembers.isNotEmpty) {
      for (final failed in failedMembers) {
        failed.removeFromParent();
        members.remove(failed);
      }
      statusText = 'بعض العناصر انهارت تحت الحمل';
    }
  }

  Map<AnchorNode, int> _buildAdjacencyMap() {
    final map = <AnchorNode, int>{};
    for (final n in nodes) {
      map[n] = 0;
    }

    for (final member in members) {
      map[member.startNode] = (map[member.startNode] ?? 0) + 1;
      map[member.endNode] = (map[member.endNode] ?? 0) + 1;
    }

    return map;
  }

  void _checkGameState() {
    final v = vehicle;
    if (v == null) return;

    if (v.body.position.y > 48) {
      simState = SimState.fail;
      statusText = 'فشل المستوى: المركبة سقطت';
      _refreshHud();
      return;
    }

    if (members.isEmpty) {
      simState = SimState.fail;

      statusText = 'فشل المستوى: الجسر انهار بالكامل';
      _refreshHud();
      return;
    }

    if (v.body.position.x > 80) {
      simState = SimState.win;
      statusText = 'نجاح! المركبة عبرت الجسر';
      _refreshHud();
    }
  }
}

class ConstructionGrid extends Component {
  ConstructionGrid({required this.worldSize, required this.cellSize});

  final Vector2 worldSize;
  final double cellSize;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final light = Paint()
      ..color = const Color(0xFFDDE5EA)
      ..strokeWidth = 0.04;

    final strong = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 0.07;

    for (double x = 0; x <= worldSize.x; x += cellSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, worldSize.y),
        x % (cellSize * 5) == 0 ? strong : light,
      );
    }

    for (double y = 0; y <= worldSize.y; y += cellSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(worldSize.x, y),

        y % (cellSize * 5) == 0 ? strong : light,
      );
    }
  }
}

class GroundPlatform extends BodyComponent {
  GroundPlatform({required this.position, required this.size});
  @override
  final Vector2 position;
  final Vector2 size;

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: position, type: BodyType.static);

    final body = world.createBody(bodyDef);
    final shape = PolygonShape()..setAsBoxXY(size.x / 2, size.y / 2);

    body.createFixture(FixtureDef(shape, friction: 1.0));

    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.x,
      height: size.y,
    );

    final paint = Paint()..color = const Color(0xFF5D4037);
    canvas.drawRect(rect, paint);
  }
}

class AnchorNode extends BodyComponent {
  AnchorNode({required this.position, required this.isFoundation});
  @override
  final Vector2 position;
  final bool isFoundation;

  bool isSelected = false;

  double get radius => isFoundation ? 0.5 : 0.38;

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: position, type: BodyType.static);

    final body = world.createBody(bodyDef);
    body.createFixture(
      FixtureDef(CircleShape()..radius = radius, friction: 1.0),
    );

    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final color = isSelected
        ? const Color(0xFFFFC107)
        : isFoundation
        ? const Color(0xFF1565C0)
        : const Color(0xFF64B5F6);

    final paint = Paint()..color = color;
    canvas.drawCircle(Offset.zero, radius, paint);

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.08;

    canvas.drawCircle(Offset.zero, radius, border);
  }
}

enum BridgeMemberType { steelBeam, cable }

class BridgeMember extends BodyComponent {
  BridgeMember({
    required this.startNode,
    required this.endNode,
    required this.memberType,
    required this.maximumStress,
    required this.cost,
  });

  final AnchorNode startNode;
  final AnchorNode endNode;
  final BridgeMemberType memberType;
  final double maximumStress;
  final double cost;

  double currentStress = 0;
  double normalizedStress = 0;

  bool get isCable => memberType == BridgeMemberType.cable;

  double get restLength =>
      startNode.body.position.distanceTo(endNode.body.position);

  Vector2 get midpoint => (startNode.body.position + endNode.body.position) / 2;
  @override
  double get angle => math.atan2(
    endNode.body.position.y - startNode.body.position.y,

    endNode.body.position.x - startNode.body.position.x,
  );

  Color get stressColor {
    if (normalizedStress < 0.45) return const Color(0xFF43A047);
    if (normalizedStress < 0.75) return const Color(0xFFFDD835);
    if (normalizedStress < 0.92) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  @override
  Body createBody() {
    final p1 = startNode.body.position;
    final p2 = endNode.body.position;

    final mid = (p1 + p2) / 2;
    final len = p1.distanceTo(p2);
    final ang = math.atan2(p2.y - p1.y, p2.x - p1.x);

    final bodyDef = BodyDef(position: mid, angle: ang, type: BodyType.static);

    final body = world.createBody(bodyDef);
    final shape = PolygonShape()..setAsBoxXY(len / 2, isCable ? 0.10 : 0.18);

    body.createFixture(
      FixtureDef(shape, friction: isCable ? 0.7 : 1.2, restitution: 0.0),
    );

    return body;
  }

  ///
  /// Stress approximation:
  /// - Longer pieces are riskier
  /// - Members with weak connectivity at

  //endpoints are riskier
  /// - Vehicle proximity raises load significantly
  /// - Cables are cheaper but less robust
  /// - Very flat or very long members accumulate more load
  ///
  void updateStress({
    required Vehicle? vehicle,
    required int startConnections,
    required int endConnections,
  }) {
    final len = restLength;
    final mid = midpoint;
    final absAngle = angle.abs();

    final lengthStress = len * (isCable ? 3.1 : 2.2);

    final weakStart = math.max(0, 2 - startConnections) * 14.0;
    final weakEnd = math.max(0, 2 - endConnections) * 14.0;
    final supportStress = weakStart + weakEnd;

    final flatness = 1.0 - ((absAngle / (math.pi / 2)).clamp(0.0, 1.0));
    final orientationStress = flatness * (isCable ? 18.0 : 10.0);

    double vehicleStress = 0;
    if (vehicle != null) {
      final d = vehicle.body.position.distanceTo(mid);
      if (d < 10) {
        vehicleStress = (10 - d) * (isCable ? 8.0 : 6.0);
      }
    }

    double materialBias = isCable ? 12.0 : 0.0;

    currentStress =
        lengthStress +
        supportStress +
        orientationStress +
        vehicleStress +
        materialBias;

    normalizedStress = (currentStress / maximumStress).clamp(0.0, 1.4);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final paint = Paint()..color = stressColor;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: restLength,
      height: isCable ? 0.20 : 0.36,
    );

    canvas.drawRect(rect, paint);

    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03;

    canvas.drawRect(rect, outline);
  }
}

class Vehicle extends BodyComponent {
  Vehicle({required this.position});
  @override
  final Vector2 position;

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: position,
      type: BodyType.dynamic,
      angularDamping: 3.0,
      linearDamping: 0.45,
    );

    final body = world.createBody(bodyDef);
    final shape = PolygonShape()..setAsBoxXY(1.5, 0.55);

    body.createFixture(
      FixtureDef(shape, density: 1.3, friction: 1.3, restitution: 0.0),
    );

    return body;
  }

  void driveForward() {
    if (body.linearVelocity.x < 9) {
      //body.applyForceToCenter(Vector2(50, 0));
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final bodyPaint = Paint()..color = const Color(0xFF37474F);
    final wheelPaint = Paint()..color = const Color(0xFF212121);
    final glassPaint = Paint()..color = const Color(0xFF90CAF9);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, 0), width: 3.0, height: 1.1),
        const Radius.circular(0.15),
      ),
      bodyPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.3, -0.45, 1.0, 0.45),
        const Radius.circular(0.10),
      ),
      glassPaint,
    );

    canvas.drawCircle(const Offset(-0.9, 0.7), 0.33, wheelPaint);
    canvas.drawCircle(const Offset(0.9, 0.7), 0.33, wheelPaint);
  }
}

class GameHud extends StatelessWidget {
  const GameHud({super.key, required this.game});

  static const String overlayId = 'game_hud';

  final CivilSimGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudTick,
      builder: (context, _, __) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _panel(
                      'الميزانية: ${game.remainingBudget.toStringAsFixed(0)}',
                    ),
                    _panel('المستخدم: ${game.usedBudget.toStringAsFixed(0)}'),
                    _panel(
                      game.buildMode == BuildMode.steelBeam
                          ? 'الوضع: Steel'
                          : 'الوضع: Cable',
                    ),
                    _panel(switch (game.simState) {
                      SimState.build => 'الحالة: Build',
                      SimState.running => 'الحالة:running',
                      SimState.win => 'الحالة: Win',
                      SimState.fail => 'الحالة: Fail',
                    }),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: game.startSimulation,
                      child: const Text('Play'),
                    ),
                    ElevatedButton(
                      onPressed: game.undoLast,
                      child: const Text('Undo'),
                    ),
                    ElevatedButton(
                      onPressed: game.resetLevel,
                      child: const Text('Reset'),
                    ),

                    ElevatedButton(
                      onPressed: () =>
                          game.selectBuildMode(BuildMode.steelBeam),
                      child: const Text('Steel'),
                    ),
                    ElevatedButton(
                      onPressed: () => game.selectBuildMode(BuildMode.cable),
                      child: const Text('Cable'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    game.statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'طريقة اللعب: اضغط على نقطتين لبناء عنصر. استخدم Steel للقوة وCable للتكلفة الأقل. ثم اضغط Play لتبدأ المركبة العبور.',
                    style: TextStyle(color: Colors.white, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _panel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,

          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
