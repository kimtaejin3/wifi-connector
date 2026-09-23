import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/saved_wifi.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_history_store.dart';
import '../../data/services/wifi_service.dart';
import '../../domain/services/wifi_input_validator.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/credential_card.dart';

/// 인식 결과를 확인하고 Wi-Fi 연결을 요청하는 화면.
/// 값은 먼저 읽기 전용으로 보여주고, [수정하기]를 누르면 같은 카드 안에서 편집한다.
class WifiResultScreen extends StatefulWidget {
  const WifiResultScreen({
    super.key,
    required this.credential,
    this.rawText,
    this.manualEntry = false,
    this.wifiService = const WifiService(),
    this.historyStore,
    this.title,
    this.retakeLabel = '다시 촬영',
  });

  final WifiCredential credential;

  /// 디버그 빌드에서만 보여주는 OCR 원문.
  final String? rawText;

  /// 촬영 없이 직접 입력으로 들어온 경우.
  final bool manualEntry;

  final WifiService wifiService;

  /// 연결 요청이 받아들여지면 여기에 기록한다. null이면 앱 공용 저장소.
  final WifiHistoryStore? historyStore;

  /// 기본 제목("Wi-Fi를 찾았어요") 대신 쓸 제목.
  final String? title;

  /// 아래쪽 보조 버튼 문구. null이면 "닫기"만 보여준다 (기록에서 열었을 때).
  final String? retakeLabel;

  @override
  State<WifiResultScreen> createState() => _WifiResultScreenState();
}

class _WifiResultScreenState extends State<WifiResultScreen> {
  late final _ssid = TextEditingController(text: widget.credential.ssid ?? '');
  late final _password = TextEditingController(text: widget.credential.password ?? '');

  /// OCR로 아무것도 찾지 못했을 때 사용자가 "직접 입력"을 눌렀는지.
  late bool _showForm = widget.manualEntry || !widget.credential.isEmpty;

  /// 값을 고칠 수 있는 상태. 직접 입력이거나 빠진 값이 있으면 바로 편집 상태로 시작한다.
  late bool _editable = _isManual || !widget.credential.hasSsid || !widget.credential.hasPassword;

  bool _connecting = false;
  WifiConnectResult? _result;

  /// 요청 승인 뒤 실제 연결 확인 상태.
  bool _verifying = false;
  WifiConnectionCheck? _check;

  /// 값을 고치거나 다시 요청하면 이전 확인 결과를 버리기 위한 일련번호.
  int _attempt = 0;
  String? _ssidError;
  String? _passwordError;

  WifiCredential get _found => widget.credential;
  bool get _isManual => widget.manualEntry || _found.isEmpty;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onEdited(String _) {
    _attempt++;
    setState(() {
      _ssidError = null;
      _passwordError = null;
      _result = null;
      _check = null;
      _verifying = false;
    });
  }

  void _useCandidate(TextEditingController controller, String value) {
    controller.text = value;
    _onEdited(value);
  }

  void _startEditing() => setState(() => _editable = true);

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final ssid = _ssid.text.trim();
    final password = _password.text.trim();
    final ssidError = WifiInputValidator.ssidError(ssid);
    final passwordError = WifiInputValidator.passwordError(password);
    setState(() {
      _ssidError = ssidError;
      _passwordError = passwordError;
      _result = null;
      _check = null;
      _verifying = false;
      if (ssidError != null || passwordError != null) _editable = true;
    });
    if (ssidError != null || passwordError != null) return;

    final attempt = ++_attempt;
    setState(() => _connecting = true);
    final result = await widget.wifiService.connect(ssid: ssid, password: password);
    if (!mounted || attempt != _attempt) return;
    // 이미 저장된 네트워크는 OS가 새로 연결을 시도하지 않으므로 기다리지 않는다
    // (이미 붙어 있거나, 설정에서 직접 골라야 한다).
    final verify = result.needsVerification && !result.alreadySaved;
    setState(() {
      _connecting = false;
      _result = result;
      _verifying = verify;
    });
    if (result.isSuccess) {
      HapticFeedback.lightImpact();
      // OS가 요청을 받아들였으면 기록에 남긴다 (Keychain/Keystore).
      unawaited((widget.historyStore ?? wifiHistoryStore)
          .save(SavedWifi(ssid: ssid, password: password, savedAt: DateTime.now())));
    }
    if (!verify) return;

    // OS가 요청을 받아들였다고 해서 연결된 것은 아니다. 실제 연결을 기다려 알려준다.
    final check = await widget.wifiService.awaitConnection(ssid: ssid);
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _verifying = false;
      _check = check;
    });
    if (check.connected) HapticFeedback.lightImpact();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '닫기',
          icon: const Icon(Icons.close_rounded),
          onPressed: _close,
        ),
      ),
      body: SafeArea(
        top: false,
        child: _showForm ? _buildForm(context) : _buildNotFound(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OCR 실패

  Widget _buildNotFound(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 56),
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: p.cardShadow,
                    ),
                    child: Icon(Icons.wifi_find_rounded, size: 40, color: p.accent),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Wi-Fi 정보를 찾지 못했어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: -0.3),
                ),
                const SizedBox(height: 10),
                Text(
                  '안내문이 화면에 잘 보이도록\n다시 촬영해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: p.muted, height: 1.45),
                ),
                const SizedBox(height: 24),
                _buildDebugRawText(),
              ],
            ),
          ),
          FilledButton(onPressed: _close, child: const Text('다시 촬영')),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => setState(() {
              _showForm = true;
              _editable = true;
            }),
            child: const Text('직접 입력하기'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 확인 / 수정

  Widget _buildForm(BuildContext context) {
    final p = AppPalette.of(context);
    final ssidMissing = !_isManual && !_found.hasSsid;
    final passwordMissing = !_isManual && _found.hasSsid && !_found.hasPassword;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                _title,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2, color: p.ink, letterSpacing: -0.4),
              ),
              const SizedBox(height: 8),
              Text(_subtitle, style: TextStyle(fontSize: 15, color: p.muted, height: 1.45)),
              const SizedBox(height: 28),
              CredentialCard(
                label: '네트워크',
                controller: _ssid,
                icon: Icons.wifi_rounded,
                accent: true,
                editable: _editable,
                autofocus: _editable && (_isManual || ssidMissing),
                hint: 'Wi-Fi 이름',
                error: _ssidError,
                textInputAction: TextInputAction.next,
                onChanged: _onEdited,
              ),
              _CandidateChips(
                values: _alternatives(WifiCandidateType.ssid, _ssid.text),
                onSelected: (v) => _useCandidate(_ssid, v),
              ),
              const SizedBox(height: 16),
              CredentialCard(
                label: '비밀번호',
                controller: _password,
                icon: Icons.key_rounded,
                editable: _editable,
                autofocus: _editable && passwordMissing,
                hint: _editable ? '없으면 비워두세요' : '비밀번호 없음',
                error: _passwordError,
                textInputAction: TextInputAction.done,
                onChanged: _onEdited,
                onSubmitted: (_) {
                  if (_canConnect) _connect();
                },
              ),
              _CandidateChips(
                values: _alternatives(WifiCandidateType.password, _password.text),
                onSelected: (v) => _useCandidate(_password, v),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _result == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: ConnectionStatusCard(
                          result: _result!,
                          check: _check,
                          verifying: _verifying,
                          onOpenWifiSettings: widget.wifiService.openWifiSettings,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              _buildDebugRawText(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Column(
            children: [
              _buildPrimaryButton(),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (!_editable)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _connecting ? null : _startEditing,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('수정하기'),
                      ),
                    ),
                  Expanded(
                    child: TextButton(
                      onPressed: _connecting ? null : _close,
                      child: Text(widget.retakeLabel ?? '닫기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _canConnect => !_connecting && _ssid.text.trim().isNotEmpty;

  Widget _buildPrimaryButton() {
    final result = _result;
    if (_connecting) {
      return FilledButton(
        onPressed: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.of(context).onAccent),
            ),
            const SizedBox(width: 12),
            const Text('연결 요청 중...'),
          ],
        ),
      );
    }
    final check = _check;
    // 확인이 안 됐어도 사용자가 더 기다리지 않고 나갈 수 있게 "완료"를 유지하되,
    // 연결 실패가 의심되면 다시 시도할 수 있게 한다.
    final unconfirmed = check != null && !check.connected;
    if (result != null && result.isSuccess && !unconfirmed) {
      return FilledButton(onPressed: _close, child: const Text('완료'));
    }
    final label = switch (result?.status) {
      WifiConnectStatus.cancelled => '다시 연결',
      WifiConnectStatus.failed => '다시 시도',
      _ when unconfirmed => '다시 시도',
      _ => 'Wi-Fi 연결',
    };
    return FilledButton(onPressed: _canConnect ? _connect : null, child: Text(label));
  }

  Widget _buildDebugRawText() {
    final raw = widget.rawText;
    if (!kDebugMode || raw == null) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('인식된 원문 (debug)', style: TextStyle(fontSize: 14)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(raw.isEmpty ? '(인식된 텍스트 없음)' : raw),
        ),
      ],
    );
  }

  String get _title {
    if (widget.title != null && !_isManual) return widget.title!;
    if (_isManual) return 'Wi-Fi 정보를 입력해주세요';
    if (_found.hasSsid && _found.hasPassword) return 'Wi-Fi를 찾았어요';
    if (_found.hasSsid) return '비밀번호를 찾지 못했어요';
    return 'Wi-Fi 이름을 찾지 못했어요';
  }

  String get _subtitle {
    if (_isManual) return '안내문에 적힌 Wi-Fi 이름과 비밀번호를 입력하세요.';
    if (!_found.hasSsid) return '비밀번호는 찾았어요. 안내문에 적힌 Wi-Fi 이름을 입력해주세요.';
    if (!_found.hasPassword) return 'Wi-Fi 이름은 찾았어요. 비밀번호가 없는 Wi-Fi라면 비워두고 연결하세요.';
    if (_found.isOpenNetwork) return '비밀번호가 없는 Wi-Fi로 인식했어요. 이름만 확인하고 연결하세요.';
    final uncertain = _found.ssidConfidence < WifiCredential.confidentThreshold ||
        _found.passwordConfidence < WifiCredential.confidentThreshold;
    return uncertain ? '안내문과 비교해보고, 다르면 수정하기를 누르세요.' : '정보가 맞으면 바로 연결하세요.';
  }

  /// 1순위와 점수 차가 큰 후보는 잡음일 가능성이 높아 보여주지 않는다.
  static const _chipScoreMargin = 0.2;

  List<String> _alternatives(WifiCandidateType type, String current) {
    final candidates = _found.candidatesOf(type);
    if (candidates.isEmpty) return const [];
    final floor = candidates.first.score - _chipScoreMargin;
    return candidates
        .where((c) => c.score >= floor)
        .map((c) => c.value)
        .where((v) => v.isNotEmpty && v != current.trim())
        .take(3)
        .toList();
  }
}

/// 파서가 찾은 다른 후보. 자동 선택이 틀렸을 때 한 번에 바꿀 수 있게 한다.
class _CandidateChips extends StatelessWidget {
  const _CandidateChips({required this.values, required this.onSelected});

  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('혹시', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
          for (final value in values)
            ActionChip(
              label: Text(value),
              visualDensity: VisualDensity.compact,
              onPressed: () => onSelected(value),
            ),
        ],
      ),
    );
  }
}
