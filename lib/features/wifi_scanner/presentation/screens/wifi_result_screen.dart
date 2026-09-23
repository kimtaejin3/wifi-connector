import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/saved_wifi.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_history_store.dart';
import '../../data/services/wifi_service.dart';
import '../../domain/services/wifi_input_validator.dart';
import '../widgets/confusable_highlight_controller.dart';
import '../widgets/connection_status_card.dart';

/// OCR 결과를 확인/수정하고 Wi-Fi 연결을 요청하는 화면.
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

  /// 연결 요청이 받아들여지면 여기에 기록한다. null이면 앱 공용 저장소.
  final WifiHistoryStore? historyStore;

  /// 기본 제목("Wi-Fi를 찾았어요") 대신 쓸 제목.
  final String? title;

  /// 아래쪽 보조 버튼 문구. null이면 버튼을 숨긴다 (기록에서 열었을 때).
  final String? retakeLabel;

  /// 디버그 빌드에서만 보여주는 OCR 원문.
  final String? rawText;

  /// 촬영 없이 직접 입력으로 들어온 경우.
  final bool manualEntry;

  final WifiService wifiService;

  @override
  State<WifiResultScreen> createState() => _WifiResultScreenState();
}

class _WifiResultScreenState extends State<WifiResultScreen> {
  late final _ssid = ConfusableHighlightController(
    text: widget.credential.ssid ?? '',
    uncertainIndexes: widget.credential.ssidUncertainIndexes,
  );
  late final _password = ConfusableHighlightController(
    text: widget.credential.password ?? '',
    uncertainIndexes: widget.credential.passwordUncertainIndexes,
  );

  /// OCR로 아무것도 찾지 못했을 때 사용자가 "직접 입력"을 눌렀는지.
  late bool _editing = widget.manualEntry || !widget.credential.isEmpty;

  /// 값을 고칠 수 있는 상태. 인식 결과는 먼저 읽기 전용으로 보여주고 [수정하기]로 연다.
  /// 직접 입력이거나 빠진 값이 있으면 바로 편집 상태로 시작한다.
  late bool _editable =
      _isManual || !widget.credential.hasSsid || !widget.credential.hasPassword;
  bool _obscurePassword = false;
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
        child: _editing ? _buildForm(context) : _buildNotFound(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OCR 실패

  Widget _buildNotFound(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 48),
                Icon(Icons.wifi_find_rounded, size: 56, color: muted),
                const SizedBox(height: 24),
                const Text(
                  'Wi-Fi 정보를 찾지 못했어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  '안내문이 화면에 잘 보이도록\n다시 촬영해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                _buildDebugRawText(),
              ],
            ),
          ),
          FilledButton(onPressed: _close, child: const Text('다시 촬영')),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => setState(() => _editing = true),
            child: const Text('직접 입력하기'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 확인 / 수정

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final fieldStyle = TextStyle(
      fontSize: 18,
      // 고정폭 글꼴로 l/1/I, O/0 같은 OCR 오인식을 눈으로 확인하기 쉽게 한다.
      fontFamily: defaultTargetPlatform == TargetPlatform.iOS ? 'Menlo' : 'monospace',
    );
    // 힌트(한글)는 고정폭이면 자간이 어색하므로 기본 글꼴을 쓴다.
    final hintStyle = theme.textTheme.bodyLarge?.copyWith(color: muted);
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
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 8),
              Text(_subtitle, style: TextStyle(fontSize: 15, color: muted, height: 1.4)),
              const SizedBox(height: 32),
              _FieldLabel(
                '네트워크',
                needsCheck: _found.hasSsid && _found.ssidConfidence < WifiCredential.confidentThreshold,
              ),
              TextField(
                controller: _ssid,
                readOnly: !_editable,
                autofocus: _editable && (_isManual || ssidMissing),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                style: fieldStyle,
                decoration: InputDecoration(
                  hintText: 'Wi-Fi 이름 (SSID)',
                  hintStyle: hintStyle,
                  errorText: _ssidError,
                ),
                onChanged: _onEdited,
              ),
              _CandidateChips(
                values: _alternatives(WifiCandidateType.ssid, _ssid.text),
                onSelected: (v) => _useCandidate(_ssid, v),
              ),
              const SizedBox(height: 24),
              _FieldLabel(
                '비밀번호',
                needsCheck: _found.hasPassword &&
                    _found.passwordConfidence < WifiCredential.confidentThreshold,
              ),
              TextField(
                controller: _password,
                readOnly: !_editable,
                autofocus: _editable && passwordMissing,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                style: fieldStyle,
                decoration: InputDecoration(
                  hintText: '비밀번호 (없으면 비워두세요)',
                  hintStyle: hintStyle,
                  errorText: _passwordError,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '비밀번호 보기' : '비밀번호 숨기기',
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onChanged: _onEdited,
                onSubmitted: (_) {
                  if (_canConnect) _connect();
                },
              ),
              if (!_obscurePassword)
                _CandidateChips(
                  values: _alternatives(WifiCandidateType.password, _password.text),
                  onSelected: (v) => _useCandidate(_password, v),
                ),
              if (_hasConfusables)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 4),
                  child: Text(
                    '색으로 표시한 글자는 인식이 불확실하거나 0/O, 1/l/I처럼 헷갈리기 쉬운 글자예요. 안내문과 비교해주세요.',
                    style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _result == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 24),
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
                  if (widget.retakeLabel != null)
                    Expanded(
                      child: TextButton(
                        onPressed: _connecting ? null : _close,
                        child: Text(widget.retakeLabel!),
                      ),
                    ),
                  if (_editable && widget.retakeLabel == null)
                    Expanded(
                      child: TextButton(
                        onPressed: _connecting ? null : _close,
                        child: const Text('닫기'),
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

  void _startEditing() {
    setState(() => _editable = true);
  }

  /// 직접 입력 중이 아니라 OCR 결과를 보고 있을 때만 헷갈리는 글자 안내를 보여준다.
  bool get _hasConfusables =>
      !_isManual && (_ssid.hasHighlights || (!_obscurePassword && _password.hasHighlights));

  Widget _buildPrimaryButton() {
    final result = _result;
    if (_connecting) {
      return const FilledButton(
        onPressed: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('연결 요청 중...'),
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
    if (_found.hasSsid) return 'Wi-Fi 이름은 찾았지만\n비밀번호를 찾지 못했어요';
    return '비밀번호는 찾았지만\nWi-Fi 이름을 찾지 못했어요';
  }

  String get _subtitle {
    if (_isManual) return '안내문에 적힌 Wi-Fi 이름과 비밀번호를 입력하세요.';
    if (widget.title != null && _found.hasSsid && _found.hasPassword) {
      return '정보가 맞는지 확인하고 연결하세요. 틀리면 수정하기를 누르세요.';
    }
    if (!_found.hasSsid) return '안내문에 적힌 Wi-Fi 이름을 입력해주세요.';
    if (!_found.hasPassword) return '비밀번호를 입력해주세요. 비밀번호가 없는 Wi-Fi라면 비워두고 연결하세요.';
    if (_found.isOpenNetwork) return '비밀번호가 없는 Wi-Fi로 인식했어요. 이름만 확인하고 연결하세요.';
    final uncertain = _found.ssidConfidence < WifiCredential.confidentThreshold ||
        _found.passwordConfidence < WifiCredential.confidentThreshold;
    return uncertain
        ? '인식이 정확하지 않을 수 있어요. 안내문과 비교해보고 틀리면 수정하기를 누르세요.'
        : '정보가 맞는지 확인하고 연결하세요. 틀리면 수정하기를 누르세요.';
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.needsCheck});

  final String text;

  /// OCR 신뢰도가 낮은 필드에 "확인 필요" 표시.
  final bool needsCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          if (needsCheck) ...[
            const SizedBox(width: 8),
            Text(
              '확인 필요',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.error),
            ),
          ],
        ],
      ),
    );
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('다른 후보', style: TextStyle(fontSize: 13, color: muted)),
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
