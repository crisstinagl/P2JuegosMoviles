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
        home: const MyHomePage(),
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

    currentRow++;
    currentCol = 0;
    notifyListeners();
  }
}

// Página principal con navegación
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
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
      appBar: AppBar(title: const Text('Dj Wordle')),
      body: Center(child: page),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(decoration: BoxDecoration(color: Colors.blueAccent), child: Text('Menú de navegación', style: TextStyle(color: Colors.white, fontSize: 20))),
            ListTile(leading: const Icon(Icons.home), title: const Text('Menú principal'), onTap: () => _selectPage(0)),
            ListTile(leading: const Icon(Icons.videogame_asset), title: const Text('Juego'), onTap: () => _selectPage(1)),
            ListTile(leading: const Icon(Icons.settings), title: const Text('Menú de opciones'), onTap: () => _selectPage(2)),
            ListTile(leading: const Icon(Icons.crop), title: const Text('Menú Game Over'), onTap: () => _selectPage(3)),
            ListTile(leading: const Icon(Icons.list), title: const Text('Ranking'), onTap: () => _selectPage(4)),
          ],
        ),
      ),
    );
  }

  void _selectPage(int index) {
    setState(() {
      selectedIndex = index;
      Navigator.pop(context);
    });
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

class RankingPage extends StatelessWidget {
  const RankingPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Página de Ranking'));
}

// Página del juego
class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyAppState>().addListener(_showEndGameDialogIfNeeded);
    });
  }

  @override
  void dispose() {
    if (mounted) {
      context.read<MyAppState>().removeListener(_showEndGameDialogIfNeeded);
    }
    super.dispose();
  }

  void _showEndGameDialogIfNeeded() {
    final appState = context.read<MyAppState>();
    if (appState.gameState != GameState.playing) {
      _showEndGameDialog(appState.gameState, appState.secretWord);
    }
  }

  void _showEndGameDialog(GameState gameState, String secretWord) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(gameState == GameState.won ? '¡Has ganado!' : '¡Has perdido!'),
          content: Text(gameState == GameState.lost ? 'La palabra era: $secretWord' : '¡Felicidades!'),
          actions: <Widget>[
            TextButton(child: const Text('JUGAR DE NUEVO'), onPressed: () {
              Navigator.of(context).pop();
              context.read<MyAppState>().resetGame();
            }),
          ],
        );
      },
    );
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
