import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'user_dao.dart'; // Asegúrate de que este archivo exista

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

// --- LOGIN (YA MODIFICADO) ---
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
    // Fondo de color #C6A4FE (Lila Claro)
    return Container(
      color: const Color(0xFFC6A4FE),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Circular
              ClipOval(
                child: Image.asset(
                  'assets/DJ Wordle.png', // <--- RUTA DE TU LOGO
                  width: 120, // Buen tamaño para un logo en login
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),

              // Título "Inicio de Sesión" (MODIFICADO)
              const Text(
                  "Inicio de Sesión",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  )
              ),
              const SizedBox(height: 10), // Espacio entre título y subtítulo

              // Subtítulo de bienvenida (NUEVO)
              const Text(
                  "¡Bienvenido! Inicia sesión para empezar a jugar.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  )
              ),
              const SizedBox(height: 40),

              // Campo de Usuario
              TextField(
                controller: _userController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Usuario",
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  // Borde enfocado #976CE1
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF976CE1), width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              // Campo de Contraseña
              TextField(
                controller: _passController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  // Borde enfocado #976CE1
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF976CE1), width: 2)),
                ),
                obscureText: true,
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 30),
              // Botón de Login/Registro #976CE1
              ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: const Color(0xFF976CE1), // Fondo #976CE1
                    foregroundColor: Colors.white
                ),
                child: const Text("ENTRAR / REGISTRARSE"),
              ),
              const SizedBox(height: 10),
              const Text("Si el usuario no existe, se creará automáticamente.", style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- PANTALLA PRINCIPAL (AppBar y Drawer Modificados) ---
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
      // AppBar Modificado: Fondo, título centrado (solo usuario) y hamburguesa de color
      appBar: AppBar(
        backgroundColor: const Color(0xFFC6A4FE), // Fondo igual al de la GamePage
        elevation: 0, // Sin sombra
        centerTitle: true, // Título centrado
        title: Text( // Solo el nombre de usuario
            '${appState.currentUser}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold) // Texto blanco y negrita
        ),
        iconTheme: const IconThemeData(color: Color(0xFF976CE1)), // Icono de menú (hamburguesa) del color de los botones
      ),
      body: Container(
        color: const Color(0xFFC6A4FE), // Fondo de la pantalla de juego: #C6A4FE
        child: page,
      ),
      drawer: Drawer(
        // Fondo completo del Drawer: #976CE1
        child: Container(
          color: const Color(0xFF976CE1),
          child: ListView(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Menú', style: TextStyle(color: Colors.white, fontSize: 24)),
                    // Icono de usuario al lado del nombre (NUEVO)
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text('${appState.currentUser}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
              // Items Juego y Ranking en Blanco
              ListTile(
                  leading: const Icon(Icons.gamepad, color: Colors.white),
                  title: const Text('Juego', style: TextStyle(color: Colors.white)),
                  onTap: () => _selectPage(1, shouldCloseDrawer: true)
              ),
              ListTile(
                  leading: const Icon(Icons.leaderboard, color: Colors.white),
                  title: const Text('Ranking', style: TextStyle(color: Colors.white)),
                  onTap: () => _selectPage(4, shouldCloseDrawer: true)
              ),
              // Botón de salir en Morado Oscuro
              ListTile(
                  leading: const Icon(Icons.logout, color: Color(0xFF4A148C)), // Morado muy oscuro
                  title: const Text('Cerrar Sesión', style: TextStyle(color: Color(0xFF4A148C))), // Morado muy oscuro
                  onTap: () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                  }
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- GAME PAGE (Pista y estilo de cuadrícula/teclado MODIFICADO) ---
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
                    // Pista: más abajo, blanco, negrita, con bombilla (MODIFICADO para evitar overflow)
                    if(appState.shouldShowHint)
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0, bottom: 20.0, left: 16.0, right: 16.0), // Añadir padding horizontal
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.white, size: 24), // Icono de bombilla
                            const SizedBox(width: 8),
                            Expanded( // Usar Expanded para que el texto ocupe el espacio restante y no se desborde
                              child: Text(
                                "Pista: ${appState.currentHint}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
//  --- WIDGETS DE WORDLE (Rectángulos de la cuadrícula MODIFICADO) ---
class GridTileUI extends StatelessWidget {
  final String letter;
  final LetterStatus status;

  const GridTileUI({super.key, required this.letter, required this.status});

  @override
  Widget build(BuildContext context) {
    // Morado oscuro para el borde inicial de los rectángulos
    Color initialBorderColor = const Color(0xFF512DA8); // Morado oscuro

    return Container(
      width: 50, height: 50, margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        border: Border.all(color: _getBorderColor(initialBorderColor), width: 2), // Usar el nuevo color
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
  // Función para obtener el color del borde, ahora usa el morado oscuro para el estado inicial
  Color _getBorderColor(Color initialColor) => status == LetterStatus.initial ? initialColor : Colors.transparent;
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

// --- WIDGETS DEL TECLADO (Botones en morado oscuro MODIFICADO) ---
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
    // Morado oscuro para los botones iniciales del teclado
    Color initialKeyColor = const Color(0xFF512DA8);

    switch (status) {
      case LetterStatus.correct: return Colors.green;
      case LetterStatus.inWord: return Colors.amber;
      case LetterStatus.notInWord: return Colors.grey.shade800;
      default: return initialKeyColor; // Usar morado oscuro para teclas no adivinadas
    }
  }

  Color _getTextColor() => status == LetterStatus.initial ? Colors.white : Colors.white; // Siempre blanco para el teclado
}

// --- PANTALLA DE RANKING (MODIFICADA) ---
class RankingPage extends StatelessWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Colores usados en el Ranking
    Color backgroundColor = const Color(0xFFC6A4FE); // Fondo #C6A4FE
    Color buttonColor = const Color(0xFF976CE1);     // Botones y puntos #976CE1
    Color darkPurpleText = const Color(0xFF4A148C);  // Texto de cerrar sesión (del menú)

    return Container(
      color: backgroundColor, // Fondo completo de la página del ranking
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: UserDao.instance.getRanking(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No hay puntuaciones aún", style: TextStyle(color: Colors.white)));
          }

          final users = snapshot.data!;

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("Ranking", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    bool isFirst = index == 0;
                    return ListTile(
                      // --- ARREGLO DE CÍRCULO Y NÚMERO ---
                      leading: CircleAvatar(
                        backgroundColor: isFirst ? buttonColor : Colors.white, // Círculo: #976CE1 (1º) o Blanco (resto)
                        child: Text(
                          "#${index + 1}",
                          style: TextStyle(
                            color: isFirst ? Colors.white : darkPurpleText, // Texto: Blanco (1º) o Morado Oscuro (resto)
                          ),
                        ),
                      ),
                      title: Text(user['username'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      trailing: Row( // Usar Row para la estrella y los puntos
                        mainAxisSize: MainAxisSize.min, // Ajustar el tamaño al contenido
                        children: [
                          if (isFirst) // Si es el primer puesto, añadir estrella
                            const Icon(Icons.star, color: Colors.amber, size: 20), // Estrella dorada
                          const SizedBox(width: 4), // Espacio entre estrella y puntos
                          Text(
                            "${user['score']} pts",
                            style: TextStyle(color: buttonColor, fontSize: 20, fontWeight: FontWeight.bold), // Puntos en morado #976CE1
                          ),
                        ],
                      ),
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
                          backgroundColor: buttonColor, // Botón en color #976CE1
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Volver a Jugar"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Botón Cerrar Sesión (Mismo estilo que Volver a Jugar)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.logout), // Icono blanco
                        label: const Text("Cerrar Sesión"), // Texto blanco
                        onPressed: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: buttonColor, // Mismo color que "Volver a Jugar"
                          foregroundColor: Colors.white, // Texto e icono blancos
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