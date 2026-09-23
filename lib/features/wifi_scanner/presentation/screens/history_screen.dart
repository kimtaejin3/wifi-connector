import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/saved_wifi.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_history_store.dart';
import '../widgets/flat_card.dart';
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
        retakeLabel: null,
      ),
    ));
  }

  Future<void> _remove(SavedWifi entry) async {
    await _store.remove(entry.ssid);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${entry.ssid} 기록을 지웠어요')));
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
    final p = AppPalette.of(context);
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('와이파이 렌즈')),
      body: switch (entries) {
        null => const Center(child: CircularProgressIndicator.adaptive()),
        _ => ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '기록',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entries.isEmpty ? '연결한 Wi-Fi가 여기에 남아요' : '${entries.length}개 네트워크',
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  if (entries.isNotEmpty)
                    TextButton(onPressed: _clearAll, child: const Text('모두 지우기')),
                ],
              ),
              const SizedBox(height: 24),
              if (entries.isEmpty)
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                        child: Icon(Icons.wifi_rounded, color: p.accent, size: 26),
                      ),
                      const SizedBox(height: 18),
                      Text('아직 기록이 없어요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
                      const SizedBox(height: 6),
                      Text(
                        '안내문을 인식해서 연결하면 여기에 저장돼요. 다음에는 촬영 없이 바로 연결할 수 있어요.',
                        style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _EntryCard(
                    entry: entries[i],
                    recent: i == 0,
                    onTap: () => _open(entries[i]),
                    onRemove: () => _remove(entries[i]),
                  ),
                ],
            ],
          ),
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.recent,
    required this.onTap,
    required this.onRemove,
  });

  final SavedWifi entry;

  /// 가장 최근에 연결한 항목.
  final bool recent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Dismissible(
      key: ValueKey('history-${entry.ssid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: p.danger,
          borderRadius: BorderRadius.circular(AppPalette.cardRadius),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: FlatCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.ssid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(entry.isOpen ? Icons.wifi_rounded : Icons.wifi_lock_rounded, color: p.muted, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${recent ? '최근 연결 · ' : ''}${formatSavedAt(entry.savedAt)}',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (recent)
              FilledButton(onPressed: onTap, child: const Text('다시 연결'))
            else
              OutlinedButton(onPressed: onTap, child: const Text('다시 연결')),
          ],
        ),
      ),
    );
  }
}

String formatSavedAt(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  String two(int v) => v.toString().padLeft(2, '0');
  if (sameDay) return '오늘 ${two(local.hour)}:${two(local.minute)}';
  return '${local.year}.${two(local.month)}.${two(local.day)}';
}
