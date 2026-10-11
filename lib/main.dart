import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/storage_service.dart';
import 'services/pin_service.dart';
import 'providers/mesh_provider.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  final pinService = PinService();
  await pinService.init();

  runApp(DeadzoneApp(storage: storage, pinService: pinService));
}

class DeadzoneApp extends StatelessWidget {
  final StorageService storage;
  final PinService pinService;

  const DeadzoneApp({
    super.key,
    required this.storage,
    required this.pinService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MeshProvider(storage: storage)),
        ChangeNotifierProvider.value(value: pinService),
      ],
      child: MaterialApp(
        title: 'Deadzone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const SplashScreen(),
        // The lock sits above every screen in the app.
        builder: (context, child) => AppLock(
          pinService: pinService,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}