import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/firebase_options.dart';
import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/providers/session_provider.dart';
import 'package:arcbench_mobile/providers/settings_provider.dart';
import 'package:arcbench_mobile/services/offline_queue.dart';
import 'package:arcbench_mobile/providers/spark_provider.dart';
import 'package:arcbench_mobile/screens/connect_screen.dart';
import 'package:arcbench_mobile/screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize Firebase — must succeed before anything else
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Hive.initFlutter();

  final offlineQueue = OfflineQueue();
  try {
    await offlineQueue.init();
  } catch (e) {
    debugPrint('[ArcBench] OfflineQueue init failed: $e');
  }

  final connectionProvider = ConnectionProvider();
  try {
    await connectionProvider.loadSaved();
  } catch (e) {
    debugPrint('[ArcBench] loadSaved failed: $e');
  }

  final sparkProvider = SparkProvider(
    connection: connectionProvider,
    offlineQueue: offlineQueue,
  );
  try {
    await sparkProvider.init();
  } catch (e) {
    debugPrint('[ArcBench] SparkProvider init failed: $e');
  }

  final settingsProvider = SettingsProvider();
  try {
    await settingsProvider.load();
  } catch (e) {
    debugPrint('[ArcBench] Settings load failed: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connectionProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: offlineQueue),
        ChangeNotifierProvider.value(value: sparkProvider),
        ChangeNotifierProxyProvider<ConnectionProvider, SessionProvider>(
          create: (context) => SessionProvider(
            connection: context.read<ConnectionProvider>(),
          ),
          update: (context, conn, previous) {
            if (previous != null) {
              previous.rebindWebSocket();
              return previous;
            }
            return SessionProvider(connection: conn);
          },
        ),
      ],
      child: const ArcBenchApp(),
    ),
  );
}

class ArcBenchApp extends StatelessWidget {
  const ArcBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();

    return MaterialApp(
      title: 'ArcBench',
      debugShowCheckedModeBanner: false,
      theme: ArcBenchTheme.darkTheme,
      home: conn.isAuthenticated ? const HomeShell() : const ConnectScreen(),
    );
  }
}
