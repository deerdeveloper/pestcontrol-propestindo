import 'package:material_ui/material_ui.dart';

import 'ui.dart';

/// Dropdown sederhana dari daftar map {id, label}.
class Pick extends StatelessWidget {
  const Pick({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.allowEmpty = false});
  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    final v = items.containsKey(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: v,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (allowEmpty) const DropdownMenuItem<String>(value: null, child: Text('-')),
          for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.value, required this.onChanged, this.maxLines = 1});
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }
}

/// Membuka form di bottom sheet. `build` menerima map yang diedit dan setState lokal.
/// Mengembalikan map hasil jika disimpan, atau null jika dibatalkan.
Future<Map<String, dynamic>?> editSheet(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> initial,
  required List<Widget> Function(Map<String, dynamic> m, void Function(VoidCallback) set) build,
  String? Function(Map<String, dynamic> m)? validate,
}) {
  final m = Map<String, dynamic>.from(initial);
  String? error;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 18),
              ...build(m, set),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Notice(icon: Icons.error_outline, text: error!, tone: Tone.danger),
                ),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: () {
                  final err = validate?.call(m);
                  if (err != null) {
                    set(() => error = err);
                    return;
                  }
                  Navigator.pop(c, m);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
