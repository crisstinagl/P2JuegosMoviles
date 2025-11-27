import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'user_dao.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización FFI para que funcione en Desktop (Windows, Linux, macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

// Enums
enum LetterStatus { initial, correct, inWord, notInWord }
enum GameState { playing, won, lost }

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'DJ Wordle',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}

// Estado de la aplicación
class MyAppState extends ChangeNotifier {
  late String secretWord;
  late String currentHint;
  List<Map<String, dynamic>> _wordBank = [];
  List<List<String>> grid = List.generate(6, (_) => List.filled(5, ''));
  List<List<LetterStatus>> gridStatus = List.generate(6, (_) => List.filled(5, LetterStatus.initial));
  int currentRow = 0;
  int currentCol = 0;
  GameState gameState = GameState.playing;
  bool shouldShowHint = false;
  final Map<String, LetterStatus> keyStatus = {};

  // --- GESTIÓN DE USUARIO ---
  String? currentUser; // Nombre del usuario logueado

  late Future<void> initializationFuture;

  MyAppState() {
    initializationFuture = _initializeGame();
  }

  Future<void> _initializeGame() async {
    await _loadWordBank();
    _generateSecretWord();
  }

  Future<void> _loadWordBank() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/word_bank.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      _wordBank = (jsonMap['words'] as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      print("Error cargando JSON: $e");
      // Fallback
      _wordBank = [{"word": "GAMER", "hint": "Juega mucho"}];
    }
  }

  void _generateSecretWord() {
    if (_wordBank.isNotEmpty) {
      final randomEntry = _wordBank[Random().nextInt(_wordBank.length)];
      secretWord = randomEntry['word'].toString().toUpperCase();
      currentHint = randomEntry['hint'].toString();
      print("Secreto: $secretWord"); // Para depuración
    }
  }

  void setUser(String username) {
    currentUser = username;
    notifyListeners();
  }

  // --- LÓGICA DE JUEGO ---
  void resetGame() {
    grid = List.generate(6, (_) => List.filled(5, ''));
    gridStatus = List.generate(6, (_) => List.filled(5, LetterStatus.initial));
    currentRow = 0;
    currentCol = 0;
    gameState = GameState.playing;
    shouldShowHint = false;
    keyStatus.clear();
    _generateSecretWord();
    notifyListeners();
  }

  void addLetter(String letter) {
    if (gameState == GameState.playing && currentRow < 6 && currentCol < 5) {
      grid[currentRow][currentCol] = letter;
      currentCol++;
      notifyListeners();
    }
  }

  void deleteLetter() {
    if (gameState == GameState.playing && currentCol > 0) {
      currentCol--;
      grid[currentRow][currentCol] = '';
      notifyListeners();
    }
  }

  void submitGuess() async {
    if (gameState != GameState.playing || currentCol != 5 || currentRow >= 6) return;

    final guess = grid[currentRow].join();
    final List<LetterStatus> rowStatus = List.filled(5, LetterStatus.notInWord);
    final List<bool> secretWordUsed = List.filled(5, false);

    // Verificación Exacta (Verde)
    for (int i = 0; i < 5; i++) {
      if (guess[i] == secretWord[i]) {
        rowStatus[i] = LetterStatus.correct;
        keyStatus[guess[i]] = LetterStatus.correct;
        secretWordUsed[i] = true;
      }
    }

    // Verificación Parcial (Amarillo)
    for (int i = 0; i < 5; i++) {
      if (rowStatus[i] != LetterStatus.correct) {
        for (int j = 0; j < 5; j++) {
          if (!secretWordUsed[j] && guess[i] == secretWord[j]) {
            rowStatus[i] = LetterStatus.inWord;
            secretWordUsed[j] = true;
            if (keyStatus[guess[i]] != LetterStatus.correct) {
              keyStatus[guess[i]] = LetterStatus.inWord;
            }
            break;
          }
        }
      }
    }

    // Actualizar Teclado (Gris)
    for (int i = 0; i < 5; i++) {
      if (rowStatus[i] == LetterStatus.notInWord) {
        if (keyStatus[guess[i]] != LetterStatus.correct && keyStatus[guess[i]] != LetterStatus.inWord) {
          keyStatus[guess[i]] = LetterStatus.notInWord;
        }
      }
    }

    gridStatus[currentRow] = rowStatus;

    if (currentRow == 1) shouldShowHint = true;

    // --- LÓGICA DE VICTORIA Y PUNTUACIÓN ---
    if (guess == secretWord) {
      gameState = GameState.won;

      // Calcular puntos
      int points = 0;
      if (currentRow < 6) { // Se usa < 6 para que la última fila dé 1 punto
        points = 6 - currentRow;
      }

      // Guardar en SQLite usando el DAO
      if (currentUser != null && points > 0) {
        await UserDao.instance.addScore(currentUser!, points);
      }

    } else if (currentRow == 5) {
      gameState = GameState.lost;
    }

    currentRow++;
    currentCol = 0;
    notifyListeners();
  }
}

// --- LOGIN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  String _errorMessage = '';

  Future<void> _handleLogin() async {
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = "Rellena ambos campos");
      return;
    }

    bool success = await UserDao.instance.loginOrRegister(user, pass);

    if (success) {
      if (mounted) {
        final appState = context.read<MyAppState>();
        appState.setUser(user);
        appState.resetGame();

        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MyHomePage()));
      }
    } else {
      setState(() => _errorMessage = "Contraseña incorrecta para ese usuario");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_person, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 20),
            const Text("DJ Wordle Login", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: "Usuario", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: "Contraseña", border: OutlineInputBorder()),
              obscureText: true,
            ),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _handleLogin,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white
              ),
              child: const Text("ENTRAR / REGISTRARSE"),
            ),
            const SizedBox(height: 10),
            const Text("Si el usuario no existe, se creará automáticamente.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA PRINCIPAL ---
class MyHomePage extends StatefulWidget {
  static final GlobalKey<_MyHomePageState> globalKey = GlobalKey<_MyHomePageState>();
  MyHomePage({Key? key}) : super(key: globalKey);
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 1;

  void _selectPage(int index, {bool shouldCloseDrawer = false}) {
    setState(() {
      selectedIndex = index;
      if (shouldCloseDrawer) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();

    Widget page;
    switch (selectedIndex) {
      case 0: page = const Center(child: Text("Bienvenido")); break;
      case 1: page = const GamePage(); break;
      case 2: page = const Center(child: Text("Opciones")); break;
      case 3: page = const Center(child: Text("Game Over Info")); break;
      case 4: page = const RankingPage(); break;
      default: throw UnimplementedError();
    }

    return Scaffold(
      appBar: AppBar(title: Text('Jugador: ${appState.currentUser}')),
      body: page,
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.deepPurple),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Menú', style: TextStyle(color: Colors.white, fontSize: 24)),
                  Text('${appState.currentUser}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.gamepad), title: const Text('Juego'), onTap: () => _selectPage(1, shouldCloseDrawer: true)),
            ListTile(leading: const Icon(Icons.leaderboard), title: const Text('Ranking'), onTap: () => _selectPage(4, shouldCloseDrawer: true)),
            // Botón de salir
            ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                }
            ),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA DE RANKING ---
class RankingPage extends StatelessWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF5A768F), Color(0xFF2C3E50)],
          radius: 1.2,
        ),
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        // Llama al DAO para obtener el ranking
        future: UserDao.instance.getRanking(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No hay puntuaciones aún", style: TextStyle(color: Colors.white)));
          }

          final users = snapshot.data!;

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("Ranking Global", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: Text("#${index + 1}", style: const TextStyle(color: Colors.black)),
                      ),
                      title: Text(user['username'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      trailing: Text("${user['score']} pts", style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final homeState = MyHomePage.globalKey.currentState;
                          if (homeState != null) {
                            context.read<MyAppState>().resetGame();
                            homeState._selectPage(1);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Volver a Jugar"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text("Cerrar Sesión"),
                        onPressed: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

// --- GAME PAGE ---
class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late MyAppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = context.read<MyAppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appState.addListener(_checkGameState);
    });
  }

  @override
  void dispose() {
    _appState.removeListener(_checkGameState);
    super.dispose();
  }

  void _checkGameState() {
    if (_appState.gameState != GameState.playing) {
      final myHomePageState = MyHomePage.globalKey.currentState;
      if (myHomePageState != null && myHomePageState.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (myHomePageState.selectedIndex != 4) {
            myHomePageState._selectPage(4, shouldCloseDrawer: false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: context.read<MyAppState>().initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          return Consumer<MyAppState>(
              builder: (context, appState, child) {
                return Column(
                  children: [
                    if(appState.shouldShowHint) Padding(padding: const EdgeInsets.all(8.0), child: Text("Pista: ${appState.currentHint}")),
                    const Expanded(child: WordleGrid()),
                    Keyboard(
                      keyStatuses: appState.keyStatus,
                      onLetterPressed: appState.addLetter,
                      onEnterPressed: appState.submitGuess,
                      onDeletePressed: appState.deleteLetter,
                    )
                  ],
                );
              }
          );
        }
    );
  }
}

// --- UI DEL JUEGO ---
//  --- WIDGETS DE WORDLE ---
class GridTileUI extends StatelessWidget {
  final String letter;
  final LetterStatus status;

  const GridTileUI({super.key, required this.letter, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50, height: 50, margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        border: Border.all(color: _getBorderColor(), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(letter.toUpperCase(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _getTextColor()))),
    );
  }

  Color _getBackgroundColor() {
    switch (status) {
      case LetterStatus.correct: return Colors.green;
      case LetterStatus.inWord: return Colors.amber;
      case LetterStatus.notInWord: return Colors.grey.shade800;
      default: return Colors.transparent;
    }
  }
  Color _getBorderColor() => status == LetterStatus.initial ? Colors.grey.shade400 : Colors.transparent;
  Color _getTextColor() => status == LetterStatus.initial ? Colors.black87 : Colors.white;
}

class WordleGrid extends StatelessWidget {
  const WordleGrid({super.key});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (rowIdx) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (colIdx) {
            return GridTileUI(letter: appState.grid[rowIdx][colIdx], status: appState.gridStatus[rowIdx][colIdx]);
          }),
        );
      }),
    );
  }
}

// --- WIDGETS DEL TECLADO ---
class Keyboard extends StatelessWidget {
  final void Function(String) onLetterPressed;
  final VoidCallback onEnterPressed;
  final VoidCallback onDeletePressed;
  final Map<String, LetterStatus> keyStatuses;

  const Keyboard({super.key, required this.onLetterPressed, required this.onEnterPressed, required this.onDeletePressed, required this.keyStatuses});

  static const List<String> _row1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const List<String> _row2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  static const List<String> _row3 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRow(_row1),
        _buildRow(_row2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            KeyButton(letter: 'ENTER', onPressed: (_) => onEnterPressed(), flex: 2, status: LetterStatus.initial),
            ..._row3.map((l) => KeyButton(letter: l, onPressed: onLetterPressed, status: keyStatuses[l] ?? LetterStatus.initial)),
            KeyButton(letter: 'DEL', onPressed: (_) => onDeletePressed(), flex: 2, icon: Icons.backspace_outlined, status: LetterStatus.initial),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildRow(List<String> letters) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters.map((l) => KeyButton(letter: l, onPressed: onLetterPressed, status: keyStatuses[l] ?? LetterStatus.initial)).toList(),
    );
  }
}

class KeyButton extends StatelessWidget {
  final String letter;
  final void Function(String) onPressed;
  final int flex;
  final IconData? icon;
  final LetterStatus status;

  const KeyButton({super.key, required this.letter, required this.onPressed, required this.status, this.flex = 1, this.icon});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _getBackgroundColor(),
            foregroundColor: _getTextColor(),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => onPressed(letter),
          child: icon != null
              ? Icon(icon, size: 20)
              : Text(letter, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (status) {
      case LetterStatus.correct: return Colors.green;
      case LetterStatus.inWord: return Colors.amber;
      case LetterStatus.notInWord: return Colors.grey.shade800;
      default: return Colors.grey.shade300;
    }
  }

  Color _getTextColor() => status == LetterStatus.initial ? Colors.black87 : Colors.white;
}