import 'package:flutter/material.dart';
import 'package:linbox/pages/home_page.dart';
import 'package:linbox/services/linux_store.dart';
import 'package:linbox/services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LinuxStore.instance.load();
  await SettingsStore.instance.load();
  runApp(const LinboxApp());
}

class LinboxApp extends StatefulWidget {
  const LinboxApp({super.key});

  @override
  State<LinboxApp> createState() => _LinboxAppState();
}

class _LinboxAppState extends State<LinboxApp> {
  final _settings = SettingsStore.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linbox',
      debugShowCheckedModeBanner: false,
      themeMode: _settings.materialThemeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF90CAF9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
