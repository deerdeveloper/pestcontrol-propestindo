import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../data/repository.dart';

/// Layar tanda tangan. Mengembalikan path file PNG yang tersimpan.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.title});
  final String title;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _ctrl = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);

  Future<void> _save() async {
    if (_ctrl.isEmpty) return;
    final bytes = await _ctrl.toPngBytes();
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'signatures', '${uuid.v4()}.png'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    if (mounted) Navigator.pop(context, file.path);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        TextButton(onPressed: _ctrl.clear, child: const Text('Hapus')),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
        const SizedBox(width: 8),
      ]),
      body: Column(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Tanda tangan di area putih di bawah ini')),
        Expanded(child: Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey)), child: Signature(controller: _ctrl, backgroundColor: Colors.white))),
      ]),
    );
  }
}
