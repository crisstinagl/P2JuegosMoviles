import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(MyApp());
}

// Widget principal
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'DJ Wordle',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor:
          Colors.blueAccent),
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

// Permite cambiar el estado de la aplicacion
class MyAppState extends ChangeNotifier {
  var current = WordPair.random();

  // Lista de favoritos - SE PUEDE BORRAR
  final List<WordPair> favorites = [];

  //Para poder cambiar la palabra aleatoria
  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }
  // Añade o elimina la palabra actual de favoritos - SE PUEDE BORRAR
  void toggleFavorite() {
    if (favorites.contains(current)) {
      favorites.remove(current);
    } else {
      favorites.add(current);
    }
    notifyListeners();
  }
}


// Pagina con navegación lateral
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex =
  0
  ;
  @override
  // Constructor de las paginas
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const MainPage();
        break;
      case 1:
        page = const GamePage();
        break;
      case 2:
        page = const OptionsPage();
        break;
      case 3:
        page = const EndGamePage();
        break;
      case 4:
        page = const RankingPage();
        break;
      default:
        throw UnimplementedError('No hay página para el índice $selectedIndex'); }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dj Wordle'),
      ),
      body: Center(child: page),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blueAccent),
              child: Text('Menú de navegación',
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Menú principal'),
              onTap: () {
                setState(() {
                  selectedIndex = 0;
                  Navigator.pop(context);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.videogame_asset),
              title: const Text('Juego'),
              onTap: () {
                setState(() {
                  selectedIndex = 1;
                  Navigator.pop(context);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Menú de opciones'),
              onTap: () {
                setState(() {
                  selectedIndex = 2;
                  Navigator.pop(context);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('Menú Game Over'),
              onTap: () {
                setState(() {
                  selectedIndex = 3;
                  Navigator.pop(context);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Ranking'),
              onTap: () {
                setState(() {
                  selectedIndex = 4;
                  Navigator.pop(context);
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Página principal
class MainPage extends StatelessWidget {
  const MainPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            // Aqui van las llamadas a widgets
          ],
        ),
      ],
    );
  }
}

// Página del juego
class GamePage extends StatelessWidget {
  const GamePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const RandomWordCard(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            FavoriteIcon(),
            SizedBox(width: 20),
            NextButton(),
          ],
        ),
      ],
    );
  }
}

// Página del menu de opciones
class OptionsPage extends StatelessWidget {
  const OptionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            // Aqui van las llamadas a widgets
          ],
        ),
      ],
    );
  }
}

// Página del menu game over
class EndGamePage extends StatelessWidget {
  const EndGamePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            // Aqui van las llamadas a widgets
          ],
        ),
      ],
    );
  }
}

// Página del ranking
class RankingPage extends StatelessWidget {
  const RankingPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            // Aqui van las llamadas a widgets
          ],
        ),
      ],
    );
  }
}

// FUNCION QUE GENERA PALABRAS ALEATORIAS (SE PUEDE REUTILIZAR)
// Widget que muestra la palabra aleatoria en un cuadro rojo
class RandomWordCard extends StatelessWidget {
  const RandomWordCard({super.key});
  @override
  Widget build(BuildContext context) {
    var word = context.watch<MyAppState>().current;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        word.asPascalCase,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// Widget del botón para generar nueva palabra
class NextButton extends StatelessWidget {
  const NextButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        context.read<MyAppState>().getNext();
      },
      child: const Text('Next'),
    );
  }
}



//// CLASES ÚTILES PARA REUTILIZAR

// Página de favoritos (las palabras que se marcaban con favoritos aparecen aqui)
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    var favorites = context.watch<MyAppState>().favorites;
    if (favorites.isEmpty) {
      return const Text('No hay favoritos aún.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Tus palabras favoritas:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        for (var pair in favorites)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(pair.asPascalCase),
            ),
          ),
      ],
    );
  }
}

// Icono dinámico de favoritos
class FavoriteIcon extends StatelessWidget {
  const FavoriteIcon({super.key});
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var isFavorite = appState.favorites.contains(appState.current);
    return IconButton(
      iconSize: 32,
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Colors.red : Colors.grey,
      ),
      onPressed: () {
        appState.toggleFavorite();
      },
      tooltip: isFavorite ? 'Eliminar de favoritos' : 'Añadir a favoritos',
    );
  }
}

