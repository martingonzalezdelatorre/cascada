import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tetris_app/game/engine.dart';

void main() {
  final o = basePieces.firstWhere((p) => p.id == 'O');

  test('limpiar dos líneas suma puntos y líneas', () {
    final e = GameEngine(random: Random(1));
    for (final y in [18, 19]) {
      for (var x = 0; x < GameEngine.cols; x++) {
        if (x != 4 && x != 5) e.board[y][x] = 3;
      }
    }
    e.current = ActivePiece(o, 4, 0);
    e.hardDrop();
    expect(e.lines, 2);
    expect(e.score, 300 + 2 * 18);
    expect(e.board[19].every((c) => c == 0), isTrue);
  });

  test('cada 10 líneas sube de nivel', () {
    final e = GameEngine(random: Random(2));
    e.lines = 9;
    for (final y in [18, 19]) {
      for (var x = 0; x < GameEngine.cols; x++) {
        if (x != 4 && x != 5) e.board[y][x] = 3;
      }
    }
    e.current = ActivePiece(o, 4, 0);
    e.hardDrop();
    expect(e.level, 2);
    expect(e.levelUps, 1);
  });

  test('la dificultad aumenta con el nivel', () {
    expect(
      const LevelRules(5).gravityMs,
      lessThan(const LevelRules(1).gravityMs),
    );
    expect(const LevelRules(1).garbageEvery, isNull);
    expect(const LevelRules(4).garbageEvery, isNotNull);
    expect(const LevelRules(6).extraPiecesEnabled, isTrue);
    expect(const LevelRules(8).previewCount, 1);
    expect(const LevelRules(10).ghostEnabled, isFalse);
  });

  test('la gravedad baja la pieza con el tiempo', () {
    final e = GameEngine(random: Random(3));
    final y0 = e.current!.y;
    e.update(LevelRules(1).gravityMs * 3 + 1);
    expect(e.current!.y, y0 + 3);
  });

  test('en pausa el juego no avanza ni responde', () {
    final e = GameEngine(random: Random(4));
    final p = e.current!;
    final y0 = p.y, x0 = p.x;
    e.pause();
    e.pause(); // idempotente
    expect(e.paused, isTrue);
    e.update(LevelRules(1).gravityMs * 5);
    e.moveLeft();
    e.hardDrop();
    expect(e.current, same(p));
    expect(e.current!.y, y0);
    expect(e.current!.x, x0);
    expect(e.score, 0);
    e.togglePause();
    expect(e.paused, isFalse);
  });

  test('pause no hace nada tras el fin de la partida', () {
    final e = GameEngine(random: Random(5));
    e.gameOver = true;
    e.pause();
    expect(e.paused, isFalse);
  });

  test('reset a mitad de partida deja todo como nuevo', () {
    final e = GameEngine(random: Random(6));
    for (final y in [18, 19]) {
      for (var x = 0; x < GameEngine.cols; x++) {
        if (x != 4 && x != 5) e.board[y][x] = 3;
      }
    }
    e.current = ActivePiece(o, 4, 0);
    e.hardDrop();
    e.pause();
    expect(e.score, greaterThan(0));
    e.reset();
    expect(e.score, 0);
    expect(e.lines, 0);
    expect(e.level, 1);
    expect(e.paused, isFalse);
    expect(e.gameOver, isFalse);
    expect(e.board.every((row) => row.every((c) => c == 0)), isTrue);
    expect(e.current, isNotNull);
  });

  test('girar cuatro veces deja la pieza igual', () {
    for (final p in [...basePieces, ...extraPieces]) {
      expect(p.rotated(4), p.cells);
    }
  });
}
