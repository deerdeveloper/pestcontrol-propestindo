import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:propestindo_teknisi/data/api.dart';
import 'package:propestindo_teknisi/screens/login_screen.dart';
// Diimpor supaya semua layar ikut dikompilasi saat test.
// ignore: unused_import
import 'package:propestindo_teknisi/screens/visit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Layar login tampil', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Api.instance.init();
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Aplikasi Teknisi'), findsOneWidget);
  });
}
