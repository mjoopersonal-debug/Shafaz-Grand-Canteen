import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'main.dart' show gold, mutedCol, textCol;

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesState();
}

class _SalesState extends State<SalesScreen> {
  DateTime _day = DateTime.now();

  String _label(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(label, style: const TextStyle(color: mutedCol, fontSize: 13)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime(_day.year, _day.month, _day.day);
    final end = start.add(const Duration(days: 1));
    return Scaffold(
      appBar: AppBar(title: const Text('Daily sales')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('time', isLessThan: Timestamp.fromDate(end))
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
            ));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          double total = 0;
          int delivered = 0;
          int pending = 0;
          final qty = <String, int>{};
          final money = <String, double>{};
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            total += (d['total'] as num?)?.toDouble() ?? 0;
            if (d['status'] == 'Delivered') {
              delivered++;
            } else {
              pending++;
            }
            for (final raw in (d['items'] as List?) ?? const []) {
              final it = raw as Map<String, dynamic>;
              final name = (it['name'] ?? '').toString();
              final q = (it['qty'] as num?)?.toInt() ?? 0;
              final price = (it['price'] as num?)?.toDouble() ?? 0;
              qty[name] = (qty[name] ?? 0) + q;
              money[name] = (money[name] ?? 0) + q * price;
            }
          }
          final best = qty.keys.toList()..sort((a, b) => qty[b]!.compareTo(qty[a]!));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: gold),
                  title: Text(_label(_day), style: const TextStyle(color: textCol, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tap to see another day', style: TextStyle(color: mutedCol)),
                  trailing: const Icon(Icons.chevron_right, color: gold),
                  onTap: _pickDay,
                ),
              ),
              Row(children: [
                _stat('Orders', '${snap.data!.docs.length}', gold),
                _stat('Sales', '₹${total.round()}', Colors.greenAccent),
              ]),
              Row(children: [
                _stat('Delivered', '$delivered', Colors.lightBlueAccent),
                _stat('Pending', '$pending', Colors.orangeAccent),
              ]),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text('Best sellers', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (best.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No orders on this day.', style: TextStyle(color: mutedCol)),
                ),
              for (int i = 0; i < best.length; i++)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: i == 0 ? gold : Colors.white12,
                      foregroundColor: i == 0 ? const Color(0xFF2A1606) : textCol,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(best[i], style: const TextStyle(color: textCol, fontWeight: FontWeight.w600)),
                    subtitle: Text('₹${money[best[i]]!.round()}', style: const TextStyle(color: mutedCol)),
                    trailing: Text('x${qty[best[i]]}',
                        style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
