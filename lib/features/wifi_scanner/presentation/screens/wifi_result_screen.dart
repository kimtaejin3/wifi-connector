import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/saved_wifi.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_history_store.dart';
import '../../data/services/wifi_service.dart';
import '../../domain/services/wifi_input_validator.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/flat_card.dart';

/// 인식 결과를 확인하고 Wi-Fi 연결을 요청하는 화면.
/// 값은 먼저 읽기 전용으로 보여주고, [수정하기]를 누르면 같은 카드 안에서 편집한다.
class WifiResultScreen extends StatefulWidget {
  const WifiResultScreen({
    super.key,
    required this.credential,
    this.manualEntry = false,
    this.wifiService = const WifiService(),
    this.historyStore,
    this.title,
    this.retakeLabel = '다시 촬영',
  });

  final WifiCredential credential;

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        _Heading(title: 'Wi-Fi 정보를 찾지 못했어요', subtitle: '안내문이 화면에 잘 보이도록 다시 촬영해주세요.'),
        const SizedBox(height: 24),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.wifi_find_rounded, color: p.accent, size: 26),
              ),
              const SizedBox(height: 18),
              Text('잘 찍는 요령', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
              const SizedBox(height: 6),
              Text(
                '글자가 정사각형 영역 안에 들어오게 맞추고, 반사되는 빛을 피해 정면에서 비춰주세요.',
                style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  FilledButton(onPressed: _close, child: const Text('다시 촬영')),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _showForm = true;
                      _editable = true;
                    }),
                    child: const Text('직접 입력'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 확인 / 수정

  Widget _buildForm(BuildContext context) {
    final p = AppPalette.of(context);
    final ssidMissing = !_isManual && !_found.hasSsid;
    final passwordMissing = !_isManual && _found.hasSsid && !_found.hasPassword;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _Heading(title: _title, subtitle: _subtitle),
        const SizedBox(height: 24),
        FlatCard(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          borderColor: (_ssidError ?? _passwordError) != null ? p.danger : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldRow(
                label: '네트워크',
                controller: _ssid,
                editable: _editable,
                autofocus: _editable && (_isManual || ssidMissing),
                hint: 'Wi-Fi 이름',
                textInputAction: TextInputAction.next,
                onChanged: _onEdited,
              ),
              if (_ssidError != null) _ErrorText(_ssidError!),
              _CandidateChips(
                values: _alternatives(WifiCandidateType.ssid, _ssid.text),
                onSelected: (v) => _useCandidate(_ssid, v),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Divider()),
              FieldRow(
                label: '비밀번호',
                controller: _password,
                editable: _editable,
                autofocus: _editable && passwordMissing,
                hint: _editable ? '없으면 비워두세요' : '비밀번호 없음',
                textInputAction: TextInputAction.done,
                onChanged: _onEdited,
                onSubmitted: (_) {
                  if (_canConnect) _connect();
                },
              ),
              if (_passwordError != null) _ErrorText(_passwordError!),
              _CandidateChips(
                values: _alternatives(WifiCandidateType.password, _password.text),
                onSelected: (v) => _useCandidate(_password, v),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _buildPrimaryButton(),
                  if (!_editable) ...[
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _connecting ? null : _startEditing,
                      child: const Text('수정하기'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _result == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ConnectionStatusCard(
                    result: _result!,
                    check: _check,
                    verifying: _verifying,
                    onOpenWifiSettings: widget.wifiService.openWifiSettings,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _connecting ? null : _close,
            child: Text(widget.retakeLabel ?? '닫기'),
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
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.of(context).onAccent),
            ),
            const SizedBox(width: 10),
            const Text('연결 요청 중'),
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

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: p.ink, letterSpacing: -0.3),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: p.muted, height: 1.5)),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(color: p.danger, fontSize: 13, fontWeight: FontWeight.w500)),
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
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('후보', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
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
