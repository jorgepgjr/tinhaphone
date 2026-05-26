import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const TinhaphoneApp());
}

class TinhaphoneApp extends StatelessWidget {
  const TinhaphoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tinhaphone',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      navigatorObservers: const [],
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
