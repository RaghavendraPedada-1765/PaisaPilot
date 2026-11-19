import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../data/photo_store.dart';
import 'format.dart';
import 'theme.dart';

/// A transaction's details: who, how much, when, where, its category
/// (optionally for everything from the same payee), receipt photos, the
/// original alert, and delete. Slides up in 240 ms and away in 200 ms.
Future<void> showCategorySheet(BuildContext context, AppDatabase db, ActivityResult row) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: Duration(milliseconds: 240), reverseDuration: Duration(milliseconds: 200)),
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _CategorySheet(db: db, row: row),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.db, required this.row});
  final AppDatabase db;
  final ActivityResult row;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  // Off by default: relabelling a whole payee is a deliberate choice, and the
  // switch shows how many payments it would touch.
  var _forPayee = false;
  late final Future<int>? _payeeCount =
      widget.row.t.payeeId == null ? null : widget.db.payeeChangeCount(widget.row.t);

  Future<void> _pick(int? categoryId) async {
    final row = widget.row;
    if (_forPayee && row.t.payeeId != null) {
      final count = await widget.db.payeeChangeCount(row.t);
      if (!mounted) return;
      final rows = count == 1 ? '1 transaction' : '$count transactions';
      final payee = row.payee ?? 'this payee';
      final apply = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(categoryId == null ? 'Move $rows to Unsorted?' : 'Apply category to $rows?'),
        content: Text(categoryId == null
            ? '$payee will no longer have a default category.'
            : 'This also sets the default category for $payee.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ));
      if (apply != true || !mounted) return;
    }
    await widget.db.setCategory(widget.row.t, categoryId, forPayee: _forPayee);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final t = widget.row.t;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text('${widget.row.payee ?? 'Unknown'} · ${inr(t.amount)} · ${dayLabel(t.txnDate)}\n\n'
            'This cannot be undone. A later sync or import can add it again if its SMS, email or statement '
            'row is read again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    for (final name in await widget.db.deleteTxn(t.id)) {
      await photoStore.remove(name);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 2000);
    if (picked == null) return;
    final name = await photoStore.save(picked.path);
    await widget.db.addAttachment(widget.row.t.id, name);
  }

  Future<void> _openPhoto(Attachment photo) async {
    final file = await photoStore.file(photo.fileName);
    if (!mounted) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain))),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Delete photo',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ),
    );
    if (remove != true) return;
    await widget.db.deleteAttachment(photo.id);
    await photoStore.remove(photo.fileName);
  }

  Widget _photos() => StreamBuilder<List<Attachment>>(
        stream: widget.db.watchAttachments(widget.row.t.id),
        builder: (context, snap) {
          final photos = snap.data ?? const <Attachment>[];
          return SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _openPhoto(p),
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder(
                        future: photoStore.file(p.fileName),
                        builder: (context, f) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: f.hasData
                              ? Image.file(f.data!, width: 76, height: 76, fit: BoxFit.cover, cacheWidth: 228)
                              : const SizedBox(width: 76, height: 76),
                        ),
                      ),
                    ),
                  ),
                _addButton(Icons.photo_camera_outlined, 'Camera', () => _addPhoto(ImageSource.camera)),
                const SizedBox(width: 8),
                _addButton(Icons.photo_library_outlined, 'Gallery', () => _addPhoto(ImageSource.gallery)),
              ],
            ),
          );
        },
      );

  Widget _addButton(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, color: teal), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 12))],
          ),
        ),
      );

  static const _sources = {'sms': 'SMS alert', 'statement': 'Bank statement', 'manual': 'Pasted alert'};

  Widget _fact(String label, String value, {Color? color}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label, style: text.bodyMedium?.copyWith(color: textFaint))),
          Expanded(child: Text(value, style: text.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final t = row.t;
    final isCredit = t.direction == 'CR';
    final text = Theme.of(context).textTheme;
    final payee = row.payee ?? 'Unknown';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, scroll) => FrostedSheet(
        child: StreamBuilder<List<Category>>(
          stream: widget.db.watchCategories(),
          builder: (context, snap) {
            final cats = snap.data ?? const <Category>[];
            return ListView(
              controller: scroll,
              // Clear of the gesture bar at the end of the list.
              padding: EdgeInsets.fromLTRB(20, 10, 20, 28 + MediaQuery.paddingOf(context).bottom),
              children: [
                Center(
                  child: Semantics(
                    label: 'Drag to resize or close',
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(isCredit ? 'Received from' : 'Paid to', style: text.labelLarge?.copyWith(color: textMuted)),
                Text(payee, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Semantics(
                  label: '${isCredit ? 'Received' : 'Paid'} ${inr(t.amount)}',
                  excludeSemantics: true,
                  child: Text(
                    signedInr(t.amount, credit: isCredit),
                    style: money(text.headlineLarge)?.copyWith(
                      color: isCredit ? credit : debit,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _fact('When', [dayLabel(t.txnDate), ?timeLabel(t.txnTime)].join(', ')),
                _fact('Account', row.account),
                _fact('Category', row.category ?? 'Unsorted', color: row.category == null ? unsortedColor : null),
                _fact('Source', _sources[t.source] ?? t.source),
                if (t.upiRef != null) _fact('UPI ref', t.upiRef!),
                const SizedBox(height: 16),
                const SectionLabel('Receipt photos'),
                Text('A bill or what you bought. Kept only on this phone.',
                    style: text.bodySmall?.copyWith(color: textFaint)),
                const SizedBox(height: 8),
                _photos(),
                const SizedBox(height: 20),
                const SectionLabel('Category'),
                if (_payeeCount != null)
                  FutureBuilder<int>(
                    future: _payeeCount,
                    builder: (context, count) {
                      final n = count.data;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _forPayee,
                        onChanged: (v) => setState(() => _forPayee = v),
                        title: Text('Apply to every payment to $payee'),
                        subtitle: Text(n == null
                            ? 'Counting payments…'
                            : 'Affects ${n == 1 ? '1 payment' : '$n payments'}; ones you labelled one by one are kept'),
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats) _option(c.name, c.id, selected: c.id == t.categoryId),
                    _option('Unsorted', null, selected: t.categoryId == null),
                  ],
                ),
                if (t.rawText != null) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: const Text('Original alert'),
                    subtitle: Text('The message this was read from', style: text.bodySmall?.copyWith(color: textFaint)),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: listFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: glassEdge),
                        ),
                        child: SelectableText(t.rawText!, style: text.bodySmall?.copyWith(color: textMuted)),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline, color: debit),
                  title: const Text('Delete transaction', style: TextStyle(color: debit)),
                  subtitle: const Text('For duplicates or wrong rows'),
                  onTap: _delete,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _option(String name, int? id, {required bool selected}) => ChoiceChip(
        label: Text(name),
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        avatar: Icon(Icons.circle, size: 10, color: categoryColor(id)),
        onSelected: (_) => _pick(id),
      );
}
