import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game/engine.dart';

void main() => runApp(const BlockApp());

const _bg = Color(0xFF0F1420);
const _panel = Color(0xFF1A2133);
const _boardBg = Color(0xFF0E1424);

const pieceColors = <int, Color>{
  1: Color(0xFF4DD0E1),
  2: Color(0xFFFFD54F),
  3: Color(0xFFBA68C8),
  4: Color(0xFF81C784),
  5: Color(0xFFE57373),
  6: Color(0xFF64B5F6),
  7: Color(0xFFFFB74D),
  8: Color(0xFFF06292),
  9: Color(0xFFAED581),
  10: Color(0xFF4DB6AC),
  garbageColor: Color(0xFF5C6370),
};

class BlockApp extends StatelessWidget {
  const BlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cascada de Bloques',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      // Ignora el tamaño de letra del sistema: evita desbordes en la interfaz.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final engine = GameEngine();
  final _focus = FocusNode();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  bool _started = false;
  int _startLevel = 1;
  int _best = 0;
  int _seenLevelUps = 0;
  String? _banner;
  Timer? _bannerTimer;

  // Arrastre táctil sobre el tablero.
  double _dragX = 0;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _bannerTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;
    if (!_started) return;
    engine.update(min(dt, 100.0));
    _afterAction();
  }

  void _afterAction() {
    if (engine.levelUps > _seenLevelUps) {
      _seenLevelUps = engine.levelUps;
      _showBanner(
        'NIVEL ${engine.level}\n${LevelRules.changesAt(engine.level).join('\n')}',
      );
    }
    if (engine.gameOver) _best = max(_best, engine.score);
    setState(() {});
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    _banner = text;
    _bannerTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _start() {
    engine.reset(startLevel: _startLevel);
    _seenLevelUps = 0;
    _started = true;
    _showBanner('NIVEL ${engine.level}\n¡A jugar!');
    _focus.requestFocus();
    setState(() {});
  }

  void _toMenu() {
    setState(() {
      _started = false;
      _banner = null;
    });
  }

  void _act(VoidCallback f) {
    if (!_started) return;
    f();
    _afterAction();
  }

  // ---------- Teclado ----------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final isRepeat = e is KeyRepeatEvent;

    if (!_started || engine.gameOver) {
      if (!isRepeat &&
          (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space)) {
        _start();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final repeatable = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowLeft: engine.moveLeft,
      LogicalKeyboardKey.arrowRight: engine.moveRight,
      LogicalKeyboardKey.arrowDown: engine.softDrop,
    };
    final single = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowUp: engine.rotate,
      LogicalKeyboardKey.keyX: engine.rotate,
      LogicalKeyboardKey.keyZ: () => engine.rotate(-1),
      LogicalKeyboardKey.space: engine.hardDrop,
      LogicalKeyboardKey.keyC: engine.holdPiece,
      LogicalKeyboardKey.shiftLeft: engine.holdPiece,
      LogicalKeyboardKey.keyP: engine.togglePause,
      LogicalKeyboardKey.escape: engine.togglePause,
    };

    final f = repeatable[k] ?? (isRepeat ? null : single[k]);
    if (f == null) {
      return repeatable.containsKey(k) || single.containsKey(k)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    _act(f);
    return KeyEventResult.handled;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1440), Color(0xFF0C1226), Color(0xFF081A24)],
          ),
        ),
        child: SafeArea(
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          // Lienzo con un tamaño mínimo de diseño (560x740) que se escala
          // para que el juego ocupe toda la ventana, sin bandas vacías.
          child: LayoutBuilder(builder: (context, box) {
            // Pantallas verticales (teléfono): diseño propio a tamaño real.
            if (box.maxWidth < box.maxHeight * 0.75) {
              return _portraitLayout();
            }
            const minW = 560.0, minH = 740.0;
            final s = min(box.maxWidth / minW, box.maxHeight / minH);
            return FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: box.maxWidth / s,
                height: box.maxHeight / s,
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.topRight,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 220),
                                  child: _leftPanel(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Center(
                              child: AspectRatio(
                                aspectRatio:
                                    GameEngine.cols / GameEngine.rows,
                                child: _boardArea(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 220),
                                  child: _rightPanel(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ExcludeFocus(child: _controls()),
                  ],
                ),
              ),
            );
          }),
        ),
        ),
      ),
    );
  }

  BoxDecoration _glass({Color? tint}) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withValues(alpha: 0.10),
            (tint ?? Colors.white).withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      );

  Widget _portraitLayout() {
    final active = _started;
    final rules = active ? engine.rules : LevelRules(_startLevel);
    final preview = active ? engine.preview : const <PieceDef>[];
    final every = rules.garbageEvery;
    final level = active ? engine.level : _startLevel;
    final progress = active
        ? 1 - engine.linesToNextLevel / GameEngine.linesPerLevel
        : 0.0;

    Widget label(String t) => Text(t,
        maxLines: 1,
        style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            color: Colors.white54,
            fontWeight: FontWeight.w700));

    // Anillo de nivel con el progreso hacia el siguiente.
    final levelRing = SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 6,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          SizedBox(
            width: 92,
            height: 92,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: Colors.tealAccent,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NIVEL',
                  style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: Colors.white60,
                      fontWeight: FontWeight.w700)),
              Text('$level',
                  style: const TextStyle(
                      fontSize: 32,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );

    final holdCard = Container(
      width: 72,
      height: 92,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('GUARDAR'),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: MiniPiecePainter(active ? engine.hold : null,
                  dim: engine.holdUsed),
            ),
          ),
        ],
      ),
    );

    // La primera pieza se ve grande; las siguientes, más pequeñas.
    final nextCard = Expanded(
      child: Container(
        height: 92,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
        decoration: _glass(tint: Colors.tealAccent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('SIGUIENTE'),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: MiniPiecePainter(
                          preview.isNotEmpty ? preview[0] : null),
                    ),
                  ),
                  for (var i = 1; i < rules.previewCount; i++)
                    Expanded(
                      flex: 3,
                      child: Opacity(
                        opacity: 0.7,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: MiniPiecePainter(
                              i < preview.length ? preview[i] : null),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    Widget pill(IconData icon, String text, {Color? color, bool big = false}) {
      final c = color ?? Colors.white70;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: big ? 7 : 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: big ? 16 : 13, color: c),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    fontSize: big ? 15 : 11,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600,
                    color: big ? Colors.white : c)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              levelRing,
              const SizedBox(width: 8),
              holdCard,
              const SizedBox(width: 8),
              nextCard,
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                pill(Icons.star_rounded, '${active ? engine.score : 0}',
                    color: Colors.amberAccent, big: true),
                pill(Icons.view_headline_rounded,
                    '${active ? engine.lines : 0} líneas'),
                pill(Icons.bolt_rounded,
                    '×${rules.speedFactor.toStringAsFixed(1)}',
                    color: Colors.lightBlueAccent),
                if (every != null)
                  pill(Icons.vertical_align_top_rounded, 'basura c/$every',
                      color: Colors.orangeAccent),
                if (rules.extraPiecesEnabled)
                  pill(Icons.category_rounded, 'piezas extra',
                      color: Colors.pinkAccent),
                if (!rules.ghostEnabled)
                  pill(Icons.visibility_off_rounded, 'sin fantasma',
                      color: Colors.redAccent),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: GameEngine.cols / GameEngine.rows,
                child: _boardArea(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExcludeFocus(child: _controls()),
        ],
      ),
    );
  }

  Widget _boardArea() {
    return LayoutBuilder(builder: (context, c) {
      final cell = c.maxWidth / GameEngine.cols;
      return GestureDetector(
        onTap: () => _act(engine.rotate),
        onPanStart: (_) => _dragX = _dragY = 0,
        onPanUpdate: (d) {
          _dragX += d.delta.dx;
          _dragY += d.delta.dy;
          while (_dragX > cell) {
            _dragX -= cell;
            _act(engine.moveRight);
          }
          while (_dragX < -cell) {
            _dragX += cell;
            _act(engine.moveLeft);
          }
          while (_dragY > cell) {
            _dragY -= cell;
            _act(engine.softDrop);
          }
        },
        onPanEnd: (d) {
          if (d.velocity.pixelsPerSecond.dy > 1500) _act(engine.hardDrop);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: BoardPainter(engine, showPiece: _started),
              ),
            ),
            if (_banner != null && _started && !engine.gameOver)
              IgnorePointer(child: Center(child: _bannerCard(_banner!))),
            if (!_started) _menuOverlay(),
            if (_started && engine.paused) _pauseOverlay(),
            if (_started && engine.gameOver) _gameOverOverlay(),
          ],
        ),
      );
    });
  }

  Widget _bannerCard(String text) {
    final lines = text.split('\n');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lines.first,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.tealAccent)),
          for (final l in lines.skip(1))
            Text(l,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _overlay(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  Widget _menuOverlay() {
    return _overlay([
      const Text('CASCADA',
          style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.tealAccent)),
      const Text('de bloques', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 20),
      const Text('Nivel inicial'),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _startLevel > 1
                ? () => setState(() => _startLevel--)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$_startLevel',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: _startLevel < 15
                ? () => setState(() => _startLevel++)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Jugar'),
      ),
      const SizedBox(height: 16),
      const Text(
        '← → mover · ↑/X girar · Z girar al revés\n'
        '↓ bajar · Espacio soltar · C guardar · P pausa\n'
        'Táctil: toca para girar, arrastra para mover,\n'
        'desliza rápido hacia abajo para soltar.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Colors.white54),
      ),
      const SizedBox(height: 12),
      const Text(
        'Cada 10 líneas subes de nivel.\n'
        'N4: sube basura · N6: piezas nuevas\n'
        'N8: menos vista previa · N10: sin fantasma',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Colors.white54),
      ),
    ]);
  }

  Widget _pauseOverlay() {
    return _overlay([
      const Text('PAUSA',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => _act(engine.togglePause),
        child: const Text('Continuar'),
      ),
      TextButton(onPressed: _toMenu, child: const Text('Menú')),
    ]);
  }

  Widget _gameOverOverlay() {
    return _overlay([
      const Text('FIN DEL JUEGO',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.redAccent)),
      const SizedBox(height: 12),
      Text('Puntos: ${engine.score}', style: const TextStyle(fontSize: 18)),
      Text('Nivel ${engine.level} · ${engine.lines} líneas'),
      Text('Récord: $_best', style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.replay),
        label: const Text('Reintentar'),
      ),
      TextButton(onPressed: _toMenu, child: const Text('Menú')),
    ]);
  }

  Widget _box(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _stat(String title, String value) => _box(
        title,
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _leftPanel() {
    final active = _started;
    return SingleChildScrollView(
      child: Column(
        children: [
          _box(
            'GUARDADA',
            SizedBox(
              height: 48,
              child: CustomPaint(
                size: Size.infinite,
                painter: MiniPiecePainter(active ? engine.hold : null,
                    dim: engine.holdUsed),
              ),
            ),
          ),
          _stat('PUNTOS', active ? '${engine.score}' : '0'),
          _stat('NIVEL', active ? '${engine.level}' : '$_startLevel'),
          _stat('LÍNEAS', active ? '${engine.lines}' : '0'),
          _box(
            'PRÓXIMO NIVEL',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: active
                      ? 1 - engine.linesToNextLevel / GameEngine.linesPerLevel
                      : 0,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Text(
                    'faltan ${active ? engine.linesToNextLevel : GameEngine.linesPerLevel}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          _stat('RÉCORD', '$_best'),
        ],
      ),
    );
  }

  Widget _rightPanel() {
    final rules = _started ? engine.rules : LevelRules(_startLevel);
    final preview = _started ? engine.preview : const <PieceDef>[];
    final every = rules.garbageEvery;
    Widget rule(IconData icon, String text, bool on) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: on ? Colors.orangeAccent : Colors.white30),
              const SizedBox(width: 4),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 11,
                        color: on ? Colors.white : Colors.white38)),
              ),
            ],
          ),
        );
    return SingleChildScrollView(
      child: Column(
        children: [
          _box(
            'SIGUIENTE',
            Column(
              children: [
                for (var i = 0; i < rules.previewCount; i++)
                  SizedBox(
                    height: i == 0 ? 48 : 34,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: MiniPiecePainter(
                          i < preview.length ? preview[i] : null),
                    ),
                  ),
              ],
            ),
          ),
          _box(
            'DIFICULTAD',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rule(Icons.speed,
                    'Vel. ×${rules.speedFactor.toStringAsFixed(1)}', true),
                rule(Icons.vertical_align_top,
                    every == null ? 'Sin basura' : 'Basura c/$every', every != null),
                rule(Icons.category, 'Piezas extra', rules.extraPiecesEnabled),
                rule(Icons.visibility_off, 'Sin fantasma', !rules.ghostEnabled),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlButton(Icons.inventory_2_outlined, () => _act(engine.holdPiece)),
          _CtrlButton(Icons.arrow_back, () => _act(engine.moveLeft),
              repeat: true),
          _CtrlButton(Icons.arrow_downward, () => _act(engine.softDrop),
              repeat: true),
          _CtrlButton(Icons.arrow_forward, () => _act(engine.moveRight),
              repeat: true),
          _CtrlButton(Icons.rotate_right, () => _act(engine.rotate)),
          _CtrlButton(
              Icons.vertical_align_bottom, () => _act(engine.hardDrop)),
          _CtrlButton(engine.paused ? Icons.play_arrow : Icons.pause,
              () => _act(engine.togglePause)),
        ],
      ),
    );
  }
}

/// Botón de control táctil; con [repeat] se repite mientras se mantiene.
class _CtrlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onAction;
  final bool repeat;

  const _CtrlButton(this.icon, this.onAction, {this.repeat = false});

  @override
  State<_CtrlButton> createState() => _CtrlButtonState();
}

class _CtrlButtonState extends State<_CtrlButton> {
  Timer? _timer;
  bool _down = false;

  void _press() {
    setState(() => _down = true);
    widget.onAction();
    if (widget.repeat) {
      _timer = Timer(const Duration(milliseconds: 250), () {
        _timer = Timer.periodic(
            const Duration(milliseconds: 55), (_) => widget.onAction());
      });
    }
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _down
                ? [Colors.teal.shade400, Colors.teal.shade700]
                : [
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.05),
                  ],
          ),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Icon(widget.icon, size: 22),
      ),
    );
  }
}

void drawCell(Canvas canvas, Rect r, Color color) {
  final box = r.deflate(max(0.8, r.width * 0.04));
  final rr = RRect.fromRectAndRadius(box, Radius.circular(r.width * 0.22));
  // Degradado: más claro arriba-izquierda, más oscuro abajo-derecha.
  canvas.drawRRect(
    rr,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, 0.35)!,
          color,
          Color.lerp(color, Colors.black, 0.25)!,
        ],
      ).createShader(box),
  );
  canvas.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.25),
  );
}

class BoardPainter extends CustomPainter {
  final GameEngine e;
  final bool showPiece;

  BoardPainter(this.e, {required this.showPiece});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / GameEngine.cols;
    canvas.drawRect(Offset.zero & size, Paint()..color = _boardBg);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var x = 1; x < GameEngine.cols; x++) {
      canvas.drawLine(Offset(x * c, 0), Offset(x * c, size.height), grid);
    }
    for (var y = 1; y < GameEngine.rows; y++) {
      canvas.drawLine(Offset(0, y * c), Offset(size.width, y * c), grid);
    }

    Rect rectAt(int x, int y) => Rect.fromLTWH(x * c, y * c, c, c);

    for (var y = 0; y < GameEngine.rows; y++) {
      for (var x = 0; x < GameEngine.cols; x++) {
        final v = e.board[y][x];
        if (v != 0) drawCell(canvas, rectAt(x, y), pieceColors[v]!);
      }
    }

    final p = e.current;
    if (!showPiece || p == null) return;
    final color = pieceColors[p.def.color]!;

    if (e.rules.ghostEnabled && !e.gameOver) {
      final ghost = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final (x, y) in p.cellsAt(e.ghostY())) {
        if (y < 0) continue;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                rectAt(x, y).deflate(2), Radius.circular(c * 0.18)),
            ghost);
      }
    }
    for (final (x, y) in p.cells) {
      if (y < 0) continue;
      drawCell(canvas, rectAt(x, y), color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MiniPiecePainter extends CustomPainter {
  final PieceDef? def;
  final bool dim;

  MiniPiecePainter(this.def, {this.dim = false});

  @override
  void paint(Canvas canvas, Size size) {
    final d = def;
    if (d == null) return;
    final xs = d.cells.map((c) => c.$1);
    final ys = d.cells.map((c) => c.$2);
    final minX = xs.reduce(min), maxX = xs.reduce(max);
    final minY = ys.reduce(min), maxY = ys.reduce(max);
    final w = maxX - minX + 1, h = maxY - minY + 1;
    final c = min(size.width / max(w, 3.2), size.height / max(h, 2.0));
    final ox = (size.width - w * c) / 2, oy = (size.height - h * c) / 2;
    var color = pieceColors[d.color]!;
    if (dim) color = color.withValues(alpha: 0.35);
    for (final (x, y) in d.cells) {
      drawCell(canvas,
          Rect.fromLTWH(ox + (x - minX) * c, oy + (y - minY) * c, c, c), color);
    }
  }

  @override
  bool shouldRepaint(covariant MiniPiecePainter old) =>
      old.def != def || old.dim != dim;
}
