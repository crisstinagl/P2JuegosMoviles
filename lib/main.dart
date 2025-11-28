import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const LoginRouter());
}

class LoginRouter extends StatelessWidget {
  const LoginRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DJ Wordle',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFFC6A4FE),
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }

          if (snapshot.hasData) {
            return ChangeNotifierProvider(
              create: (context) => MyAppState(snapshot.data!.email!),
              child: const AppShell(),
            );
          }

          return const LoginScreen();
        },
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();

    if (appState.isModeSelected) {
      return MyHomePage();
    } else {
      return const GameModeSelectionScreen();
    }
  }
}


class GameModeSelectionScreen extends StatelessWidget {
  const GameModeSelectionScreen({super.key});

  void _selectMode(BuildContext context, int wordLength) {
    final appState = context.read<MyAppState>();
    appState.setWordLength(wordLength);
    appState.resetGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC6A4FE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Selecciona un modo de juego',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => _selectMode(context, 5),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
                backgroundColor: const Color(0xFF976CE1),
                foregroundColor: Colors.white,
              ),
              child: const Text('5 Letras'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _selectMode(context, 6),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
                backgroundColor: const Color(0xFF976CE1),
                foregroundColor: Colors.white,
              ),
              child: const Text('6 Letras'),
            ),
          ],
        ),
      ),
    );
  }
}

enum LetterStatus { initial, correct, inWord, notInWord }
enum GameState { playing, won, lost }

class MyAppState extends ChangeNotifier {
  late String secretWord;
  late String currentHint;
  List<Map<String, dynamic>> _wordBank = [];

  int wordLength = 5;
  late List<List<String>> grid;
  late List<List<LetterStatus>> gridStatus;
  int currentRow = 0;
  int currentCol = 0;
  GameState gameState = GameState.playing;
  bool shouldShowHint = false;
  final Map<String, LetterStatus> keyStatus = {};

  final AudioPlayer _audioPlayer = AudioPlayer();

  String currentUser;
  String currentUsername;
  int? lastGamePoints;

  bool isModeSelected = false;

  late Future<void> initializationFuture;

  MyAppState(this.currentUser)
      : currentUsername = currentUser.split('@')[0] {
    grid = List.generate(6, (_) => List.filled(wordLength, ''));
    gridStatus = List.generate(6, (_) => List.filled(wordLength, LetterStatus.initial));
    initializationFuture = _initializeGame();
  }

  Future<void> _initializeGame() async {
    await _loadWordBank();
    _generateSecretWord();

    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('musica.mp3'), volume: 0.4);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void setWordLength(int length) {
    wordLength = length;
    isModeSelected = true;
  }

  void returnToModeSelection() {
    isModeSelected = false;
    notifyListeners();
  }

  Future<void> _loadWordBank() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/word_bank.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);

      final List<dynamic> gameModes = jsonMap['game_modes'];
      final List<Map<String, dynamic>> allWords = [];
      for (var mode in gameModes) {
        if (mode['words'] is List) {
          allWords.addAll((mode['words'] as List).cast<Map<String, dynamic>>());
        }
      }
      _wordBank = allWords;

      if (_wordBank.isEmpty) {
        print("Advertencia: No se encontraron palabras en 'assets/word_bank.json'. Usando palabra de emergencia.");
        _wordBank = [{"word": "GAMER", "hint": "Juega mucho"}];
      }

    } catch (e) {
      print("Error cargando el banco de palabras desde JSON: $e");
      _wordBank = [{"word": "GAMER", "hint": "Juega mucho"}];
    }
  }


  void _generateSecretWord() {
    if (_wordBank.isNotEmpty) {
      final filteredWords = _wordBank
          .where((entry) => entry['word'].toString().length == wordLength)
          .toList();

      if (filteredWords.isNotEmpty) {
        final randomEntry = filteredWords[Random().nextInt(filteredWords.length)];
        secretWord = randomEntry['word'].toString().toUpperCase();
        currentHint = randomEntry['hint'].toString();
        print("Secreto ($wordLength letras): $secretWord");
      } else {
        print("No se encontraron palabras de $wordLength letras. Revisa tu archivo 'word_bank.json'");
        secretWord = ''.padRight(wordLength, '!');
        currentHint = "No hay palabras para este modo";
      }
    }
  }

  void resetGame() {
    grid = List.generate(6, (_) => List.filled(wordLength, ''));
    gridStatus = List.generate(6, (_) => List.filled(wordLength, LetterStatus.initial));
    currentRow = 0;
    currentCol = 0;
    gameState = GameState.playing;
    shouldShowHint = false;
    keyStatus.clear();
    lastGamePoints = null;
    _generateSecretWord();
    notifyListeners();
  }

  void addLetter(String letter) {
    if (gameState == GameState.playing && currentRow < 6 && currentCol < wordLength) {
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
    if (gameState != GameState.playing || currentCol != wordLength || currentRow >= 6) return;

    final guess = grid[currentRow].join();
    
    final List<LetterStatus> rowStatus = List.filled(wordLength, LetterStatus.notInWord);
    final List<bool> secretWordUsed = List.filled(wordLength, false);

    for (int i = 0; i < wordLength; i++) {
      if (guess[i] == secretWord[i]) {
        rowStatus[i] = LetterStatus.correct;
        keyStatus[guess[i]] = LetterStatus.correct;
        secretWordUsed[i] = true;
      }
    }

    for (int i = 0; i < wordLength; i++) {
      if (rowStatus[i] != LetterStatus.correct) {
        for (int j = 0; j < wordLength; j++) {
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

    for (int i = 0; i < wordLength; i++) {
      if (rowStatus[i] == LetterStatus.notInWord) {
        if (keyStatus[guess[i]] != LetterStatus.correct && keyStatus[guess[i]] != LetterStatus.inWord) {
          keyStatus[guess[i]] = LetterStatus.notInWord;
        }
      }
    }

    gridStatus[currentRow] = rowStatus;

    if (currentRow == 1) shouldShowHint = true;

    if (guess == secretWord) {
      gameState = GameState.won;
      int points;
      if (wordLength == 6) {
        points = 7 - currentRow;
      } else {
        points = 6 - currentRow;
      }
      lastGamePoints = points;
      final userDoc = FirebaseFirestore.instance.collection('users').doc(currentUser);
      await userDoc.update({'score': FieldValue.increment(points)});
    } else if (currentRow == 5) {
      gameState = GameState.lost;
      lastGamePoints = 0;
    }

    currentRow++;
    currentCol = 0;
    notifyListeners();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = "Rellena email y contraseña");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
          await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.email!).set({
            'username': email.split('@')[0],
            'score': 0,
          });
        } on FirebaseAuthException catch (e) {
          if (e.code == 'weak-password') {
            setState(() => _errorMessage = "La contraseña es muy débil");
          } else {
            setState(() => _errorMessage = "Error en el registro: ${e.message}");
          }
        }
      } else {
        setState(() => _errorMessage = "Error: ${e.message}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFC6A4FE),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipOval(
                child: Image.asset('assets/DJ_Wordle.png', width: 120, height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(height: 20),
              const Text("Inicio de Sesión", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 10),
              const Text("Usa tu email para entrar o registrarte", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Email",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF976CE1), width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Contraseña",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF976CE1), width: 2)),
                ),
                obscureText: true,
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center,),
                ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: const Color(0xFF976CE1),
                    foregroundColor: Colors.white),
                child: const Text("ENTRAR / REGISTRARSE"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      case 1: page = const GamePage(); break;
      case 4: page = const RankingPage(); break;
      default: page = const GamePage();
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFC6A4FE),
        elevation: 0,
        centerTitle: true,
        title: Text(appState.currentUsername, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFF976CE1)),
      ),
      body: Container(
        color: const Color(0xFFC6A4FE),
        child: page,
      ),
      drawer: Drawer(
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
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(appState.currentUsername, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
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
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.white),
                title: const Text('Cambiar Modo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  context.read<MyAppState>().returnToModeSelection();
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                  leading: const Icon(Icons.logout, color: Color(0xFF4A148C)),
                  title: const Text('Cerrar Sesión', style: TextStyle(color: Color(0xFF4A148C))),
                  onTap: () {
                    FirebaseAuth.instance.signOut();
                  }
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    _appState.addListener(_checkGameState);
  }

  @override
  void dispose() {
    _appState.removeListener(_checkGameState);
    super.dispose();
  }

  void _checkGameState() {
    if (!mounted) return;
    if (_appState.gameState != GameState.playing) {
      final myHomePageState = MyHomePage.globalKey.currentState;
      if (myHomePageState != null && myHomePageState.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (myHomePageState.mounted && myHomePageState.selectedIndex != 4) {
            myHomePageState._selectPage(4);
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
                    if(appState.shouldShowHint)
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0, bottom: 20.0, left: 16.0, right: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.white, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Pista: ${appState.currentHint}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Expanded(child: WordleGrid()),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Keyboard(
                        keyStatuses: appState.keyStatus,
                        onLetterPressed: appState.addLetter,
                        onEnterPressed: appState.submitGuess,
                        onDeletePressed: appState.deleteLetter,
                      ),
                    )
                  ],
                );
              }
          );
        }
    );
  }
}

class GridTileUI extends StatelessWidget {
  final String letter;
  final LetterStatus status;

  const GridTileUI({super.key, required this.letter, required this.status});

  @override
  Widget build(BuildContext context) {
    Color initialBorderColor = const Color(0xFF512DA8);
    return Container(
      width: 50, height: 50, margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        border: Border.all(color: _getBorderColor(initialBorderColor), width: 2),
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
          children: List.generate(appState.wordLength, (colIdx) {
            if (appState.grid.length > rowIdx && appState.grid[rowIdx].length > colIdx) {
              return GridTileUI(
                letter: appState.grid[rowIdx][colIdx],
                status: appState.gridStatus[rowIdx][colIdx],
              );
            }
            return Container(); 
          }),
        );
      }),
    );
  }
}

class Keyboard extends StatelessWidget {
  final void Function(String) onLetterPressed;
  final VoidCallback onEnterPressed;
  final VoidCallback onDeletePressed;
  final Map<String, LetterStatus> keyStatuses;

  const Keyboard({super.key, required this.onLetterPressed, required this.onEnterPressed, required this.onDeletePressed, required this.keyStatuses});

  static const List<String> _row1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const List<String> _row2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ñ'];
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
    Color initialKeyColor = const Color(0xFF512DA8);
    switch (status) {
      case LetterStatus.correct: return Colors.green;
      case LetterStatus.inWord: return Colors.amber;
      case LetterStatus.notInWord: return Colors.grey.shade800;
      default: return initialKeyColor;
    }
  }

  Color _getTextColor() => Colors.white;
}

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  int? _pointsToShow;
  double _notificationOpacity = 0.0;
  String? _notificationUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<MyAppState>();
      if (appState.lastGamePoints != null && mounted) {
        setState(() {
          _pointsToShow = appState.lastGamePoints;
          _notificationUser = appState.currentUsername;
          _notificationOpacity = 1.0;
        });

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _notificationOpacity = 0.0);
            appState.lastGamePoints = null;
          }
        });
      }
    });
  }

  Future<List<QueryDocumentSnapshot>> _getFirebaseRanking() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('score', descending: true)
        .limit(50)
        .get();
    return snapshot.docs;
  }

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = const Color(0xFFC6A4FE);
    Color buttonColor = const Color(0xFF976CE1);
    Color darkPurpleText = const Color(0xFF4A148C);

    return Container(
      color: backgroundColor,
      child: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _getFirebaseRanking(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Aún no hay ranking", style: TextStyle(color: Colors.white)));
          }
          final userDocs = snapshot.data!;

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("Ranking Global", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: userDocs.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final userData = userDocs[index].data() as Map<String, dynamic>;
                    final username = userData['username'] ?? 'N/A';
                    final score = userData['score'] ?? 0;
                    bool isFirst = index == 0;
                    bool showPointsForThisUser = username == _notificationUser;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isFirst ? buttonColor : Colors.white,
                        child: Text("#${index + 1}", style: TextStyle(color: isFirst ? Colors.white : darkPurpleText)),
                      ),
                      title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      trailing: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerRight,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isFirst) const Icon(Icons.star, color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                "$score pts",
                                style: TextStyle(color: buttonColor, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (showPointsForThisUser)
                            AnimatedOpacity(
                              opacity: _notificationOpacity,
                              duration: const Duration(milliseconds: 500),
                              child: Transform.translate(
                                offset: const Offset(10, -25),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (_pointsToShow ?? 0) > 0 ? Colors.green : Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
                                  child: Text(
                                    "+${_pointsToShow ?? 0}",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
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
                          backgroundColor: buttonColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Volver a Jugar"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text("Cambiar Modo"),
                        onPressed: () {
                          context.read<MyAppState>().returnToModeSelection();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: buttonColor,
                          foregroundColor: Colors.white,
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
