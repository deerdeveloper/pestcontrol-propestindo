import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Emblem logo Propestindo dalam kotak putih membulat.
class Emblem extends StatelessWidget {
  const Emblem({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .1),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * .3)),
        child: Image.asset('assets/emblem.png'),
      );
}

/// Label kecil huruf kapital untuk judul bagian.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.count, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});
  final String text;
  final int? count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.muted)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)),
              child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink2)),
            ),
          ],
        ]),
      );
}

/// Badge/pil berwarna dengan titik di depan.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, required this.bg, this.dot = true});
  final String text;
  final Color color;
  final Color bg;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

enum Tone { info, warn, danger, success }

/// Kotak pemberitahuan berwarna (kuning/merah/hijau/biru).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.text, this.title, this.tone = Tone.warn, this.trailing});
  final IconData icon;
  final String? title;
  final String text;
  final Tone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, bd) = switch (tone) {
      Tone.warn => (const Color(0xFF6D4C00), AppColors.gold50, const Color(0xFFFBEEBF)),
      Tone.danger => (AppColors.red, AppColors.red50, const Color(0xFFF6CACA)),
      Tone.success => (AppColors.green800, AppColors.green50, const Color(0xFFD9F2E0)),
      Tone.info => (AppColors.blue, AppColors.blue50, const Color(0xFFCFDEF3)),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: bd)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title!, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            Text(text, style: TextStyle(color: fg, fontSize: 13)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Tampilan kosong dengan ikon.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.green50, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: AppColors.green700),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(text!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ]),
      );
}

/// Kartu putih dengan padding.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.title, this.onTap, this.color, this.border});
  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: border ?? AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: title == null
                ? child
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 10),
                    child,
                  ]),
          ),
        ),
      );
}
