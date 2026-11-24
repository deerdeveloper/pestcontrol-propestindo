import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'data/api.dart';
import 'data/local_db.dart';
import 'data/sync.dart';
import 'screens/login_screen.dart';
import 'screens/visit_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  await Api.instance.init();
  await LocalDb.instance.init();
  await SyncService.instance.init();
  runApp(const PropestindoApp());
}

class PropestindoApp extends StatelessWidget {
  const PropestindoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Propestindo Teknisi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A3A)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      ),
      home: Api.instance.token == null ? const LoginScreen() : const VisitListScreen(),
    );
  }
}
