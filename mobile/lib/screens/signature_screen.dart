import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../data/repository.dart';
import '../theme.dart';

/// Layar tanda tangan. Mengembalikan path file PNG yang tersimpan.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.title});
  final String title;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _ctrl = SignatureController(penStrokeWidth: 3, penColor: const Color(0xFF0B1F3A), exportBackgroundColor: Colors.white);
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      if (_empty != _ctrl.isEmpty && mounted) setState(() => _empty = _ctrl.isEmpty);
    });
  }

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
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.draw_outlined, color: AppColors.green700, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Tanda tangan di area putih di bawah ini', style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFB7C6BD), width: 1.5),
                ),
                child: Stack(children: [
                  Positioned(left: 28, right: 28, bottom: 56, child: Container(height: 1, color: AppColors.line)),
                  if (_empty)
                    const Center(child: Text('Tanda tangan di sini', style: TextStyle(color: Color(0xFFA7B6AD), fontWeight: FontWeight.w600))),
                  Positioned.fill(child: Signature(controller: _ctrl, backgroundColor: Colors.transparent)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _ctrl.clear, child: const Text('Hapus'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton.icon(onPressed: _empty ? null : _save, icon: const Icon(Icons.check), label: const Text('Simpan'))),
            ]),
          ]),
        ),
      ),
    );
  }
}
