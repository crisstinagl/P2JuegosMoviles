import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

// Enums para el estado
enum LetterStatus { initial, correct, inWord, notInWord }
enum GameState { playing, won, lost }

// Widget principal de la aplicación
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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        ),
        // La clave global hace que el constructor no pueda ser constante
        home: MyHomePage(),
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

  // --- VARIABLES DE RANKING Y NOMBRE ---
  String playerName = '';
  List<ScoreEntry> rankings = [];
  // -------------------------------------

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
      print("Error al cargar el banco de palabras: $e");
      _wordBank = [
        {"word": "FLAME", "hint": "Fuego"},
        {"word": "OCEAN", "hint": "Mucha agua"}
      ];
    }
  }

  void _generateSecretWord() {
    if (_wordBank.isNotEmpty) {
      final randomEntry = _wordBank[Random().nextInt(_wordBank.length)];
      secretWord = randomEntry['word'].toString().toUpperCase();
      currentHint = randomEntry['hint'].toString();
      print('Palabra secreta: $secretWord, Pista: $currentHint');
    }
  }

  void setPlayerName(String name) {
    playerName = name;
    notifyListeners();
  }

  void resetGame() {
    grid = List.generate(6, (_) => List.filled(5, ''));
    gridStatus = List.generate(6, (_) => List.filled(5, LetterStatus.initial));
    currentRow = 0;
    currentCol = 0;
    gameState = GameState.playing;
    shouldShowHint = false;
    keyStatus.clear();
    _generateSecretWord();
    // No reseteamos playerName aquí
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

  // --- LÓGICA PARA AÑADIR AL RANKING ---
  void _addToRanking(GameState result, int attempts) {
    rankings.add(ScoreEntry(
      playerName: playerName,
      result: result,
      word: secretWord,
      attempts: attempts,
      date: DateTime.now(),
    ));

    // Ordenamos por fecha, el más reciente primero (para historial)
    rankings.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }
  // --------------------------------------

  void submitGuess() {
    if (gameState != GameState.playing || currentCol != 5 || currentRow >= 6) return;

    final guess = grid[currentRow].join();
    final List<LetterStatus> rowStatus = List.filled(5, LetterStatus.notInWord);
    final List<bool> secretWordLetterUsed = List.filled(5, false);

    for (int i = 0; i < 5; i++) {
      if (guess[i] == secretWord[i]) {
        rowStatus[i] = LetterStatus.correct;
        keyStatus[guess[i]] = LetterStatus.correct;
        secretWordLetterUsed[i] = true;
      }
    }

    for (int i = 0; i < 5; i++) {
      if (rowStatus[i] != LetterStatus.correct) {
        for (int j = 0; j < 5; j++) {
          if (!secretWordLetterUsed[j] && guess[i] == secretWord[j]) {
            rowStatus[i] = LetterStatus.inWord;
            secretWordLetterUsed[j] = true;
            if (keyStatus[guess[i]] != LetterStatus.correct) {
              keyStatus[guess[i]] = LetterStatus.inWord;
            }
            break;
          }
        }
      }
    }

    for (int i = 0; i < 5; i++) {
      if (rowStatus[i] == LetterStatus.notInWord) {
        if (keyStatus[guess[i]] != LetterStatus.correct && keyStatus[guess[i]] != LetterStatus.inWord) {
          keyStatus[guess[i]] = LetterStatus.notInWord;
        }
      }
    }

    gridStatus[currentRow] = rowStatus;

    if (currentRow == 1) {
      shouldShowHint = true;
    }

    if (guess == secretWord) {
      gameState = GameState.won;
    } else if (currentRow == 5) {
      gameState = GameState.lost;
    }

    // Registrar partida si terminó
    if (gameState != GameState.playing) {
      _addToRanking(gameState, currentRow + 1);
    }

    currentRow++;
    currentCol = 0;
    notifyListeners();
  }
}

// Página principal con navegación
class MyHomePage extends StatefulWidget {
  // CLAVE: Creamos una clave global para poder acceder al estado desde el botón de Ranking
  static final GlobalKey<_MyHomePageState> globalKey = GlobalKey<_MyHomePageState>();

  MyHomePage({Key? key}) : super(key: globalKey);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 1;

  // CORRECCIÓN CLAVE: Agregamos un parámetro para indicar si se debe cerrar el Drawer.
  void _selectPage(int index, {bool shouldCloseDrawer = false}) {
    setState(() {
      selectedIndex = index;
      if (shouldCloseDrawer) {
        Navigator.pop(context); // Cierra el Drawer solo si se le indica.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();

    // Flujo de Ingreso de Nombre
    if (appState.playerName.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dj Wordle')),
        body: const Center(child: NameInputPage()), // Muestra la pantalla de nombre
      );
    }

    Widget page;
    switch (selectedIndex) {
      case 0: page = const MainPage(); break;
      case 1: page = const GamePage(); break;
      case 2: page = const OptionsPage(); break;
      case 3: page = const EndGamePage(); break;
      case 4: page = const RankingPage(); break;
      default: throw UnimplementedError('No hay página para el índice $selectedIndex');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Dj Wordle - Jugador: ${appState.playerName}'),
      ),
      body: Center(child: page),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blueAccent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Menú de navegación', style: TextStyle(color: Colors.white, fontSize: 20)),
                  const SizedBox(height: 8),
                  Text('Jugando como: ${appState.playerName}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            // Se añaden los parámetros 'shouldCloseDrawer: true' a todos los ListTiles
            ListTile(leading: const Icon(Icons.home), title: const Text('Menú principal'), onTap: () => _selectPage(0, shouldCloseDrawer: true)),
            ListTile(leading: const Icon(Icons.videogame_asset), title: const Text('Juego'), onTap: () => _selectPage(1, shouldCloseDrawer: true)),
            ListTile(leading: const Icon(Icons.settings), title: const Text('Menú de opciones'), onTap: () => _selectPage(2, shouldCloseDrawer: true)),
            ListTile(leading: const Icon(Icons.crop), title: const Text('Menú Game Over'), onTap: () => _selectPage(3, shouldCloseDrawer: true)),
            ListTile(leading: const Icon(Icons.list), title: const Text('Ranking'), onTap: () => _selectPage(4, shouldCloseDrawer: true)),
          ],
        ),
      ),
    );
  }
}

// --- PÁGINAS DE LA APP ---
class MainPage extends StatelessWidget {
  const MainPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('¡Bienvenido a Wordle!'));
}

class OptionsPage extends StatelessWidget {
  const OptionsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Página de Opciones'));
}

class EndGamePage extends StatelessWidget {
  const EndGamePage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Página de Fin de Juego'));
}

// --- PÁGINA: Ingreso de Nombre ---
class NameInputPage extends StatelessWidget {
  const NameInputPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    final appState = context.read<MyAppState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('¡Bienvenido a DJ Wordle!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 40),
          const Text('Introduce tu nombre para empezar a jugar:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: 'Tu Nombre',
              border: OutlineInputBorder(),
            ),
            maxLength: 15,
            onSubmitted: (name) {
              if (name.trim().isNotEmpty) {
                appState.setPlayerName(name.trim());
              }
            },
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                appState.setPlayerName(name);
              }
            },
            child: const Text('Comenzar Juego', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

// --- PÁGINA: Ranking (Diseño similar a Compose) ---
class RankingPage extends StatelessWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();
    final scores = appState.rankings;

    // Colores del gradiente radial (simulando el de Compose)
    const List<Color> gradientColors = [
      Color(0xFF5A768F), // Gris azulado claro
      Color(0xFF2C3E50), // Gris azulado oscuro
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: gradientColors,
          center: Alignment(0.0, 0.0),
          radius: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Ranking de Partidas",
            style: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16.0),

          // Comprueba si la lista está vacía
          if (scores.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history, size: 80, color: Colors.white70),
                    const SizedBox(height: 20),
                    const Text(
                      'Aún no hay partidas registradas.\n¡Juega una para ver el historial!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: scores.length,
                separatorBuilder: (context, index) => Divider(
                  color: Colors.grey.withOpacity(0.5),
                  height: 1.0,
                ),
                itemBuilder: (context, index) {
                  return ScoreEntryRow(index: index, entry: scores[index]);
                },
              ),
            ),

          const SizedBox(height: 16.0),

          // Botón para volver (simulando el diseño de Compose)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            child: ElevatedButton(
              onPressed: () {
                final myHomePageState = MyHomePage.globalKey.currentState;
                if (myHomePageState != null) {
                  // 1. Resetear el juego ANTES de navegar
                  context.read<MyAppState>().resetGame();
                  // 2. Volver a la página de Juego (índice 1) SIN cerrar el cajón (porque no está abierto)
                  myHomePageState._selectPage(1, shouldCloseDrawer: false);
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                backgroundColor: const Color(0xFF3498DB), // Azul de Compose
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Jugar de Nuevo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }
}

// Composable para cada fila del ranking (adaptado a Flutter)
class ScoreEntryRow extends StatelessWidget {
  final int index;
  final ScoreEntry entry;

  const ScoreEntryRow({super.key, required this.index, required this.entry});

  @override
  Widget build(BuildContext context) {
    // Colores de medalla
    final Color rankColor = [
      const Color(0xFFFFD700), // Oro
      const Color(0xFFC0C0C0), // Plata
      const Color(0xFFCD7F32), // Bronce
      Colors.white70
    ][index.clamp(0, 3)];

    final bool isWin = entry.result == GameState.won;
    final String resultText = isWin ? 'GANÓ' : 'PERDIÓ';
    final Color resultChipColor = isWin ? Colors.green.shade700 : Colors.red.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Posición y Nombre
          Expanded(
            child: Row(
              children: [
                Text(
                  "${index + 1}.",
                  style: TextStyle(
                    color: rankColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.playerName,
                  style: TextStyle(
                    color: rankColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Resultado y Palabra
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Chip(
                label: Text(
                  resultText,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: resultChipColor,
              ),
              const SizedBox(height: 4),
              Text(
                "Palabra: ${entry.word}",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                "Intentos: ${entry.attempts}",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Página del juego
class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // Almacenar una referencia al estado para usarla de forma segura en dispose()
  late MyAppState _appState;

  @override
  void initState() {
    super.initState();
    // Capturamos la instancia del estado
    _appState = context.read<MyAppState>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Añadimos el listener usando la instancia capturada
      _appState.addListener(_showRankingScreenIfNeeded);
    });
  }

  @override
  void dispose() {
    // Usamos la instancia capturada para remover el listener, evitando context.read()
    _appState.removeListener(_showRankingScreenIfNeeded);
    super.dispose();
  }

  // MÉTODO NUEVO: Navega automáticamente a la página de Ranking
  void _showRankingScreenIfNeeded() {
    // Usamos el estado capturado para evitar leer de nuevo del context
    final appState = _appState;

    // Si el juego ha terminado, navegamos a la pantalla de Ranking.
    if (appState.gameState != GameState.playing) {
      final myHomePageState = MyHomePage.globalKey.currentState;
      if (myHomePageState != null && myHomePageState.mounted) {
        // Usamos addPostFrameCallback para ejecutar la navegación de forma segura
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Solo navegar si no estamos ya en la página de Ranking
          if (myHomePageState.selectedIndex != 4) {
            // Navegamos al Ranking sin cerrar el Drawer (porque no está abierto)
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return const Center(child: Text("Error al cargar el juego"));
        } else {
          return Consumer<MyAppState>(
            builder: (context, appState, child) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (appState.shouldShowHint)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text("Pista: ${appState.currentHint}", style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                      ),
                    const Expanded(child: WordleGrid()),
                    Keyboard(
                      keyStatuses: appState.keyStatus,
                      onLetterPressed: appState.addLetter,
                      onEnterPressed: appState.submitGuess,
                      onDeletePressed: appState.deleteLetter,
                    ),
                  ],
                ),
              );
            },
          );
        }
      },
    );
  }
}

// --- WIDGETS DE WORDLE ---
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

// Guardar los datos de una victoria
class ScoreEntry {
  final String playerName;
  final GameState result;
  final String word;
  final int attempts;
  final DateTime date;

  ScoreEntry({required this.playerName, required this.result, required this.word, required this.attempts, required this.date});
}