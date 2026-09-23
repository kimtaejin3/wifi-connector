import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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
      body: SafeArea(
        bottom: false,
        child: switch (entries) {
          null => const Center(child: CircularProgressIndicator.adaptive()),
          [] => _Empty(onClear: null, header: _header(p, 0)),
          _ => ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                _header(p, entries.length, onClear: _clearAll),
                const SizedBox(height: 20),
                _RecentCard(entry: entries.first, onTap: () => _open(entries.first)),
                for (final entry in entries.skip(1)) ...[
                  const SizedBox(height: 12),
                  _EntryCard(entry: entry, onTap: () => _open(entry), onRemove: () => _remove(entry)),
                ],
                if (entries.length == 1) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _remove(entries.first),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('기록 삭제'),
                    ),
                  ),
                ],
              ],
            ),
        },
      ),
    );
  }

  Widget _header(AppPalette p, int count, {VoidCallback? onClear}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '기록',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                count == 0 ? '연결한 Wi-Fi가 여기에 남아요' : '$count개 네트워크',
                style: TextStyle(fontSize: 14, color: p.muted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        if (onClear != null)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: onClear,
            child: const Text('모두 지우기'),
          ),
      ],
    );
  }
}

/// 가장 최근에 연결한 네트워크. 강조 카드로 보여준다.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.entry, required this.onTap});

  final SavedWifi entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: p.accent,
      borderRadius: BorderRadius.circular(AppPalette.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppPalette.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppPalette.cardRadius),
            boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.ssid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.onAccent, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '최근 연결 · ${formatSavedAt(entry.savedAt)}',
                      style: TextStyle(color: p.onAccent.withValues(alpha: 0.72), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_rounded, color: p.onAccent, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap, required this.onRemove});

  final SavedWifi entry;
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
        child: Icon(Icons.delete_outline_rounded, color: p.onAccent),
      ),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(AppPalette.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppPalette.cardRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppPalette.cardRadius),
              boxShadow: p.cardShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatSavedAt(entry.savedAt),
                        style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Icon(entry.isOpen ? Icons.wifi_rounded : Icons.wifi_lock_rounded, color: p.accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.header, this.onClear});

  final Widget header;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Spacer(),
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: p.cardShadow,
                  ),
                  child: Icon(Icons.wifi_rounded, size: 40, color: p.accent),
                ),
                const SizedBox(height: 22),
                Text(
                  '아직 기록이 없어요',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  '안내문을 인식해서 연결하면\n여기에 저장돼요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.muted, height: 1.45),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
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
