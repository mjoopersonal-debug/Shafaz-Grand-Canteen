import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app_alarm.dart';
import 'foreground_service.dart';
import 'movies_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'sales_screen.dart';

const gold = Color(0xFFF5B942);
const gold2 = Color(0xFFFFD76A);
const bgDark = Color(0xFF0E0606);
const panel = Color(0xFF1A0B0B);
const redAccent = Color(0xFFE0352B);
const textCol = Color(0xFFFFF6E6);
const mutedCol = Color(0xFFBFA892);

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  KeepAlive.init();
  String? startError;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    startError = 'Firebase start failed:\n$e';
  }
  try {
    await AppAlarm.init();
  } catch (e) {
    startError = (startError ?? '') + '\n\nAlarm start failed:\n$e';
  }
  runApp(ShafazApp(startError: startError));
}

class ShafazApp extends StatelessWidget {
  final String? startError;
  const ShafazApp({super.key, this.startError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shafaz Canteen',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        colorScheme: const ColorScheme.dark(primary: gold, secondary: gold2, surface: panel),
        appBarTheme: const AppBarTheme(backgroundColor: panel, foregroundColor: textCol, centerTitle: false),
        cardTheme: CardThemeData(
          color: panel,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: gold.withOpacity(0.3)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: const Color(0xFF2A1606),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: startError != null ? ErrorScreen(message: startError!) : const AuthGate(),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  const ErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup problem')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: SelectableText(message)),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorScreen(message: 'Auth error:\n${snap.error}');
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const HomeScreen();
        return const SignInScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed. Check email and password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Image.asset(
                'assets/logo.png',
                height: 150,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.local_movies, size: 100, color: gold),
              ),
              const SizedBox(height: 12),
              const Text('Owner sign-in', style: TextStyle(color: gold, fontSize: 18)),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: redAccent)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: Text(_busy ? 'Signing in...' : 'Sign in  →',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  StreamSubscription<QuerySnapshot>? _sub;
  bool _firstLoad = true;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    // Keeps the app alive in the background so new-order alarms still ring
    AppAlarm.setup().then((_) => KeepAlive.start());
    _sub = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .listen((snap) {
      if (!_firstLoad) {
        final added = snap.docChanges.where((c) => c.type == DocumentChangeType.added).toList();
        if (added.isNotEmpty) {
          final d = (added.last.doc.data() as Map<String, dynamic>?) ?? {};
          _alertNewOrder(d, snap.size);
        }
      }
      _firstLoad = false;
      _pending = snap.size;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _alertNewOrder(Map<String, dynamic> d, int count) async {
    final seat = (d['seat'] ?? '?').toString();
    final pickup = (d['pickupNo'] ?? '').toString();
    final who = (d['name'] ?? '').toString();
    final how = (d['delivery'] ?? '').toString();
    final items = (d['items'] as List?)?.length ?? 0;
    final total = d['total'] ?? 0;
    await AppAlarm.schedule(
      key: 'order-${DateTime.now().millisecondsSinceEpoch}',
      when: DateTime.now().add(const Duration(seconds: 2)),
      title: 'New order $pickup · Seat $seat',
      body: '$who · $items item(s) · ₹$total · $how · Pending: $count',
    );
    final ctx = navKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('New order for seat $seat!'), duration: const Duration(seconds: 6)),
      );
    }
  }

  Widget _menuTile(String title, String sub, IconData icon, VoidCallback onTap) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(backgroundColor: gold, child: Icon(icon, color: const Color(0xFF2A1606))),
        title: Text(title, style: const TextStyle(color: textCol, fontWeight: FontWeight.bold, fontSize: 17)),
        subtitle: Text(sub, style: const TextStyle(color: mutedCol)),
        trailing: const Icon(Icons.chevron_right, color: gold),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shafaz Canteen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await KeepAlive.stop();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Pending orders', style: TextStyle(color: mutedCol, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('$_pending',
                      style: const TextStyle(color: gold, fontSize: 48, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _menuTile('New orders', 'Pickup number, seat, items, photos and payment screenshot',
              Icons.receipt_long, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()))),
          _menuTile('Manage products', 'Add, edit, photos, prices and stock',
              Icons.inventory_2, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen()))),
          _menuTile('Daily sales', 'Orders, sales total and best sellers',
              Icons.bar_chart, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen()))),
          _menuTile('Movies & interval', 'Movie names, start times and interval minutes',
              Icons.movie, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoviesScreen()))),
          const SizedBox(height: 24),
          Center(
            child: Image.asset(
              'assets/logo.png',
              height: 110,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
