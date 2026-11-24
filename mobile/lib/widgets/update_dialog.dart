import 'package:material_ui/material_ui.dart';
import 'package:ota_update/ota_update.dart';

import '../data/api.dart';
import '../data/app_update.dart';

/// Cek update aplikasi. Jika [silent], tidak ada pesan apa pun saat tidak ada update
/// atau saat gagal (dipakai saat aplikasi dibuka).
Future<void> checkAppUpdate(BuildContext context, {bool silent = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  AppUpdateInfo? info;
  try {
    info = await AppUpdater.instance.check();
  } on ApiException catch (e) {
    if (!silent) messenger.showSnackBar(SnackBar(content: Text('Gagal cek update: ${e.message}')));
    return;
  } catch (e) {
    if (!silent) messenger.showSnackBar(SnackBar(content: Text('Gagal cek update: $e')));
    return;
  }
  if (info == null) return;
  if (!info.available) {
    if (!silent) messenger.showSnackBar(SnackBar(content: Text('Aplikasi sudah versi terbaru (${info.current})')));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => UpdateDialog(info: info!));
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});
  final AppUpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _running = false;
  int _percent = 0;
  String? _message;

  void _start() {
    setState(() {
      _running = true;
      _percent = 0;
      _message = null;
    });
    try {
      OtaUpdate()
          .execute(widget.info.url,
              destinationFilename: 'propestindo-teknisi.apk', sha256checksum: widget.info.sha256)
          .listen(_onEvent, onError: (Object e) => _fail('$e'));
    } catch (e) {
      _fail('$e');
    }
  }

  void _onEvent(OtaEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        setState(() => _percent = int.tryParse(e.value ?? '') ?? _percent);
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        setState(() {
          _percent = 100;
          _running = false;
          _message = 'Unduhan selesai. Ikuti layar pemasangan Android, lalu buka lagi aplikasinya.';
        });
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Izinkan "Pasang aplikasi tidak dikenal" untuk aplikasi ini di Pengaturan, lalu coba lagi.');
      case OtaStatus.CHECKSUM_ERROR:
        _fail('File rusak saat diunduh (checksum tidak cocok). Coba lagi.');
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _fail('Unduhan update sedang berjalan.');
      case OtaStatus.CANCELED:
        _fail('Unduhan dibatalkan.');
      default:
        _fail('Gagal: ${e.value ?? e.status.name}');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _message = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final mb = info.size > 0 ? ' · ${(info.size / 1048576).toStringAsFixed(1)} MB' : '';
    return AlertDialog(
      title: const Text('Update aplikasi tersedia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versi terpasang: ${info.current}\nVersi baru: ${info.latest}$mb'),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.notes, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_running) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _percent > 0 ? _percent / 100 : null),
              const SizedBox(height: 4),
              Text('Mengunduh... $_percent%'),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
            const SizedBox(height: 12),
            Text('Data laporan yang belum terkirim tetap aman setelah update.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        if (!_running) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nanti')),
        if (!_running) FilledButton(onPressed: _start, child: Text(_message == null ? 'Update sekarang' : 'Coba lagi')),
        if (_running)
          TextButton(
            onPressed: () {
              OtaUpdate().cancel();
            },
            child: const Text('Batal'),
          ),
      ],
    );
  }
}
