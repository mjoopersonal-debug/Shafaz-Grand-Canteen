import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'main.dart' show gold, mutedCol, textCol, redAccent;

String _to12(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p[0]) ?? 0;
  final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

String _intervalAt(String hhmm, int mins) {
  final p = hhmm.split(':');
  final total = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0) + mins;
  final t = total % (24 * 60);
  return _to12('${t ~/ 60}:${t % 60}');
}

class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final nameC = TextEditingController();
    final minC = TextEditingController(text: '55');
    TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add movie / show'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Movie name')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: time);
                  if (t != null) setS(() => time = t);
                },
                child: Text('Start time: ${time.format(ctx)}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Interval after (minutes), e.g. 55'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final name = nameC.text.trim();
    final mins = int.tryParse(minC.text.trim());
    nameC.dispose();
    minC.dispose();
    if (ok != true || !context.mounted) return;
    if (name.isEmpty || mins == null || mins <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the movie name and interval minutes.')),
      );
      return;
    }
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    await FirebaseFirestore.instance.collection('movies').add({
      'name': name,
      'start': '$hh:$mm',
      'intervalMin': mins,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Movies & interval')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: gold,
        foregroundColor: const Color(0xFF2A1606),
        icon: const Icon(Icons.add),
        label: const Text('Add movie'),
        onPressed: () => _add(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('movies').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.toList()
            ..sort((a, b) => ((a.data() as Map)['start'] ?? '').toString()
                .compareTo(((b.data() as Map)['start'] ?? '').toString()));
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No movies yet. Tap Add movie. Customers pick their movie on the website.',
                    textAlign: TextAlign.center, style: TextStyle(color: mutedCol)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final start = (d['start'] ?? '00:00').toString();
              final mins = d['intervalMin'] is num ? (d['intervalMin'] as num).toInt() : 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text((d['name'] ?? '').toString(),
                      style: const TextStyle(color: textCol, fontWeight: FontWeight.bold)),
                  subtitle: Text('Starts ${_to12(start)} · Interval at ${_intervalAt(start, mins)} ($mins min)',
                      style: const TextStyle(color: mutedCol)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: redAccent),
                    onPressed: () => docs[i].reference.delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
