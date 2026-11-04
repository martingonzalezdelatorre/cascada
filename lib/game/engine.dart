import 'dart:math';

/// Coordenada (x, y) dentro de una pieza o del tablero.
typedef Cell = (int, int);

/// Definición de una pieza: sus celdas dentro de una caja `size x size`.
class PieceDef {
  final String id;
  final int size;
  final List<Cell> cells;
  final int color;

  const PieceDef(this.id, this.size, this.cells, this.color);

  /// Celdas tras girar `r` cuartos de vuelta en sentido horario.
  List<Cell> rotated(int r) {
    var c = cells;
    for (var i = 0; i < r % 4; i++) {
      c = [for (final (x, y) in c) (size - 1 - y, x)];
    }
    return c;
  }
}

const basePieces = <PieceDef>[
  PieceDef('I', 4, [(0, 1), (1, 1), (2, 1), (3, 1)], 1),
  PieceDef('O', 2, [(0, 0), (1, 0), (0, 1), (1, 1)], 2),
  PieceDef('T', 3, [(1, 0), (0, 1), (1, 1), (2, 1)], 3),
  PieceDef('S', 3, [(1, 0), (2, 0), (0, 1), (1, 1)], 4),
  PieceDef('Z', 3, [(0, 0), (1, 0), (1, 1), (2, 1)], 5),
  PieceDef('J', 3, [(0, 0), (0, 1), (1, 1), (2, 1)], 6),
  PieceDef('L', 3, [(2, 0), (0, 1), (1, 1), (2, 1)], 7),
];

/// Piezas "raras" que entran en juego a partir del nivel 6.
const extraPieces = <PieceDef>[
  PieceDef('+', 3, [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], 8),
  PieceDef('U', 3, [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1)], 9),
  PieceDef('v', 2, [(0, 0), (0, 1), (1, 1)], 10),
];

const garbageColor = 11;

/// Reglas que dependen del nivel: velocidad y complejidad.
class LevelRules {
  final int level;
  const LevelRules(this.level);

  /// Milisegundos que tarda la pieza en bajar una fila.
  double get gravityMs => max(60.0, 800.0 * pow(0.82, level - 1).toDouble());

  /// Cada cuántas piezas sube una fila de basura (null = desactivado).
  int? get garbageEvery => level < 4 ? null : max(4, 14 - level);

  bool get extraPiecesEnabled => level >= 6;

  int get previewCount => level >= 8 ? 1 : 3;

  bool get ghostEnabled => level < 10;

  /// Multiplicador de velocidad respecto al nivel 1.
  double get speedFactor => 800.0 / gravityMs;

  /// Novedades que aparecen al llegar a [level].
  static List<String> changesAt(int level) {
    final out = <String>['Más velocidad'];
    if (level == 4) {
      out.add('¡Empieza a subir basura!');
    } else if (level > 4 && level <= 10) {
      out.add('La basura sube más seguido');
    }
    if (level == 6) out.add('Llegan piezas nuevas');
    if (level == 8) out.add('Solo ves 1 pieza siguiente');
    if (level == 10) out.add('Sin pieza fantasma');
    return out;
  }
}

class ActivePiece {
  final PieceDef def;
  int rot;
  int x;
  int y;

  ActivePiece(this.def, this.x, this.y, [this.rot = 0]);

  Iterable<Cell> cellsAt(int atY) =>
      def.rotated(rot).map((c) => (c.$1 + x, c.$2 + atY));

  Iterable<Cell> get cells => cellsAt(y);
}

/// Lógica del juego, sin dependencias de Flutter.
class GameEngine {
  static const cols = 10;
  static const rows = 20;
  static const lockDelayMs = 500.0;
  static const maxLockResets = 15;
  static const linesPerLevel = 10;

  final Random _rng;
  int startLevel;

  late List<List<int>> board;
  ActivePiece? current;
  final List<PieceDef> _queue = [];
  final List<PieceDef> _bag = [];
  PieceDef? hold;
  bool holdUsed = false;

  int score = 0;
  int lines = 0;
  int level = 1;
  bool gameOver = false;
  bool paused = false;
  int piecesSinceGarbage = 0;

  /// Se incrementa en cada subida de nivel (para que la UI muestre avisos).
  int levelUps = 0;

  double _gravityAcc = 0;
  double _lockAcc = 0;
  int _lockResets = 0;

  GameEngine({Random? random, this.startLevel = 1})
      : _rng = random ?? Random() {
    reset();
  }

  LevelRules get rules => LevelRules(level);

  List<PieceDef> get preview => _queue.take(rules.previewCount).toList();

  int get linesToNextLevel => linesPerLevel - (lines % linesPerLevel);

  void reset({int? startLevel}) {
    if (startLevel != null) this.startLevel = startLevel;
    board = List.generate(rows, (_) => List.filled(cols, 0));
    _queue.clear();
    _bag.clear();
    hold = null;
    holdUsed = false;
    score = 0;
    lines = 0;
    level = this.startLevel;
    gameOver = false;
    paused = false;
    piecesSinceGarbage = 0;
    levelUps = 0;
    _spawn();
  }

  // ---------- Generación de piezas ----------

  PieceDef _draw() {
    if (_bag.isEmpty) {
      _bag.addAll(basePieces);
      if (rules.extraPiecesEnabled) _bag.addAll(extraPieces);
      _bag.shuffle(_rng);
    }
    return _bag.removeLast();
  }

  void _fillQueue() {
    while (_queue.length < 5) {
      _queue.add(_draw());
    }
  }

  void _spawn([PieceDef? def]) {
    _fillQueue();
    final d = def ?? _queue.removeAt(0);
    _fillQueue();
    final minY = d.cells.map((c) => c.$2).reduce(min);
    final p = ActivePiece(d, (cols - d.size) ~/ 2, -minY);
    _gravityAcc = 0;
    _lockAcc = 0;
    _lockResets = 0;
    current = p;
    if (!_fits(p.def, p.rot, p.x, p.y)) gameOver = true;
  }

  // ---------- Colisiones y movimiento ----------

  bool _fits(PieceDef d, int rot, int x, int y) {
    for (final (cx, cy) in d.rotated(rot)) {
      final bx = cx + x, by = cy + y;
      if (bx < 0 || bx >= cols || by >= rows) return false;
      if (by >= 0 && board[by][bx] != 0) return false;
    }
    return true;
  }

  bool get _canAct => !gameOver && !paused && current != null;

  bool get _grounded {
    final p = current!;
    return !_fits(p.def, p.rot, p.x, p.y + 1);
  }

  bool _tryMove(int dx, int dy) {
    final p = current!;
    if (_fits(p.def, p.rot, p.x + dx, p.y + dy)) {
      p.x += dx;
      p.y += dy;
      return true;
    }
    return false;
  }

  /// Al mover/girar una pieza apoyada se reinicia el retardo de fijación
  /// (con un límite para que no se pueda alargar indefinidamente).
  void _onManipulated() {
    if (_grounded && _lockResets < maxLockResets) {
      _lockAcc = 0;
      _lockResets++;
    }
  }

  void moveLeft() {
    if (_canAct && _tryMove(-1, 0)) _onManipulated();
  }

  void moveRight() {
    if (_canAct && _tryMove(1, 0)) _onManipulated();
  }

  void rotate([int dir = 1]) {
    if (!_canAct) return;
    final p = current!;
    final nr = (p.rot + dir) % 4;
    const kicks = [(0, 0), (-1, 0), (1, 0), (0, -1), (-2, 0), (2, 0)];
    for (final (kx, ky) in kicks) {
      if (_fits(p.def, nr, p.x + kx, p.y + ky)) {
        p
          ..rot = nr
          ..x += kx
          ..y += ky;
        _onManipulated();
        return;
      }
    }
  }

  void softDrop() {
    if (!_canAct) return;
    if (_tryMove(0, 1)) {
      score += 1;
      _gravityAcc = 0;
    }
  }

  void hardDrop() {
    if (!_canAct) return;
    var d = 0;
    while (_tryMove(0, 1)) {
      d++;
    }
    score += 2 * d;
    _lock();
  }

  void holdPiece() {
    if (!_canAct || holdUsed) return;
    final cur = current!.def;
    final previous = hold;
    hold = cur;
    holdUsed = true;
    _spawn(previous);
  }

  void togglePause() {
    if (!gameOver) paused = !paused;
  }

  /// Fila en la que caería la pieza actual (para la pieza fantasma).
  int ghostY() {
    final p = current!;
    var y = p.y;
    while (_fits(p.def, p.rot, p.x, y + 1)) {
      y++;
    }
    return y;
  }

  /// Avanza el juego `ms` milisegundos.
  void update(double ms) {
    if (!_canAct) return;
    if (_grounded) {
      _lockAcc += ms;
      if (_lockAcc >= lockDelayMs) _lock();
    } else {
      _gravityAcc += ms;
      final g = rules.gravityMs;
      while (_gravityAcc >= g) {
        _gravityAcc -= g;
        if (!_tryMove(0, 1)) {
          _gravityAcc = 0;
          break;
        }
      }
    }
  }

  // ---------- Fijación, líneas y basura ----------

  void _lock() {
    final p = current!;
    var overflow = false;
    for (final (bx, by) in p.cells) {
      if (by < 0) {
        overflow = true;
        continue;
      }
      board[by][bx] = p.def.color;
    }
    if (overflow) {
      gameOver = true;
      return;
    }
    _clearLines();
    holdUsed = false;
    piecesSinceGarbage++;
    final every = rules.garbageEvery;
    if (every != null && piecesSinceGarbage >= every) {
      piecesSinceGarbage = 0;
      _addGarbage();
      if (gameOver) return;
    }
    _spawn();
  }

  void _clearLines() {
    bool full(List<int> row) => row.every((c) => c != 0);
    final cleared = board.where(full).length;
    if (cleared == 0) return;
    board.removeWhere(full);
    while (board.length < rows) {
      board.insert(0, List.filled(cols, 0));
    }
    const table = [0, 100, 300, 500, 800];
    score += table[min(cleared, 4)] * level;
    lines += cleared;
    final newLevel = startLevel + lines ~/ linesPerLevel;
    if (newLevel > level) {
      level = newLevel;
      levelUps++;
    }
  }

  /// Empuja el tablero hacia arriba y añade una fila con un hueco aleatorio.
  void _addGarbage() {
    if (board[0].any((c) => c != 0)) {
      gameOver = true;
      return;
    }
    board.removeAt(0);
    final hole = _rng.nextInt(cols);
    board.add(List.generate(cols, (i) => i == hole ? 0 : garbageColor));
  }
}
