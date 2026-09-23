import 'package:flutter/material.dart';

import '../../data/models/saved_wifi.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_history_store.dart';
import 'wifi_result_screen.dart';

/// 인식해서 연결한 Wi-Fi 목록. 항목을 누르면 다시 연결할 수 있다.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.store});

  final WifiHistoryStore? store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final WifiHistoryStore _store = widget.store ?? wifiHistoryStore;
  List<SavedWifi>? _entries;

  @override
  void initState() {
    super.initState();
    _store.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _store.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final entries = await _store.load();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _open(SavedWifi entry) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WifiResultScreen(
        credential: WifiCredential(
          ssid: entry.ssid,
          password: entry.password,
          ssidConfidence: 1,
          passwordConfidence: 1,
          candidates: [
            WifiCandidate(value: entry.ssid, type: WifiCandidateType.ssid, score: 1),
            WifiCandidate(value: entry.password, type: WifiCandidateType.password, score: 1),
          ],
        ),
        title: '저장된 Wi-Fi',
        historyStore: _store,
      ),
    ));
  }

  Future<void> _remove(SavedWifi entry) async {
    await _store.remove(entry.ssid);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${entry.ssid} 기록을 지웠어요.')));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록을 모두 지울까요?'),
        content: const Text('저장된 Wi-Fi 이름과 비밀번호가 이 기기에서 삭제됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('모두 지우기')),
        ],
      ),
    );
    if (confirmed == true) await _store.clear();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('인식 기록'),
        actions: [
          if (entries != null && entries.isNotEmpty)
            TextButton(onPressed: _clearAll, child: const Text('모두 지우기')),
        ],
      ),
      body: switch (entries) {
        null => const Center(child: CircularProgressIndicator.adaptive()),
        [] => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 52, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    '아직 기록이 없어요',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '안내문이나 QR을 인식해서 연결하면\n여기에 저장돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        _ => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurface,
                  child: Icon(entry.isOpen ? Icons.wifi_rounded : Icons.wifi_lock_rounded),
                ),
                title: Text(entry.ssid, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${entry.isOpen ? '비밀번호 없음' : '비밀번호 저장됨'} · ${_formatDate(entry.savedAt)}',
                ),
                trailing: IconButton(
                  tooltip: '기록 삭제',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _remove(entry),
                ),
                onTap: () => _open(entry),
              );
            },
          ),
      },
    );
  }

  static String _formatDate(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    if (sameDay) return '오늘 ${two(local.hour)}:${two(local.minute)}';
    return '${local.year}.${two(local.month)}.${two(local.day)}';
  }
}
