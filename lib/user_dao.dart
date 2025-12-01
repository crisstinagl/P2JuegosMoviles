import 'package:sqflite/sqflite.dart';
import 'db/database_helper.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class UserDao {
  // Patrón Singleton para el DAO
  static final UserDao instance = UserDao._init();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  UserDao._init();

  // --- Lógica de Seguridad (Hashing) ---
  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  // --- Métodos CRUD ---

  // Iniciar Sesión o Registrarse
  Future<bool> loginOrRegister(String username, String password) async {
    final db = await _dbHelper.database;
    final hashedPassword = _hashPassword(password);

    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );

    if (result.isNotEmpty) {
      if (result.first['password'] == hashedPassword) {
        return true;
      } else {
        return false;
      }
    } else {
      await db.insert('users', {
        'username': username,
        'password': hashedPassword,
        'score': 0,
      });
      return true;
    }
  }

  // Actualizar Puntuación (Sumar puntos)
  Future<void> addScore(String username, int pointsToAdd) async {
    final db = await _dbHelper.database;

    final user = await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (user.isNotEmpty) {
      int currentScore = user.first['score'] as int;

      await db.update(
        'users',
        {'score': currentScore + pointsToAdd},
        where: 'username = ?',
        whereArgs: [username],
      );
    }
  }

  // Obtener Ranking
  Future<List<Map<String, dynamic>>> getRanking() async {
    final db = await _dbHelper.database;
    return await db.query('users', orderBy: 'score DESC');
  }
}