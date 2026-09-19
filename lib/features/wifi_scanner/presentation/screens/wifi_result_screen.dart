import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/wifi_credential.dart';
import '../../data/services/wifi_service.dart';
import '../../domain/services/wifi_input_validator.dart';
import '../widgets/connection_status_card.dart';

/// OCR 결과를 확인/수정하고 Wi-Fi 연결을 요청하는 화면.
class WifiResultScreen extends StatefulWidget {
  const WifiResultScreen({
    super.key,
    required this.credential,
    this.rawText,
    this.manualEntry = false,
    this.wifiService = const WifiService(),
  });

  final WifiCredential credential;

  /// 디버그 빌드에서만 보여주는 OCR 원문.
  final String? rawText;

  /// 촬영 없이 직접 입력으로 들어온 경우.
  final bool manualEntry;

  final WifiService wifiService;

  @override
  State<WifiResultScreen> createState() => _WifiResultScreenState();
}

class _WifiResultScreenState extends State<WifiResultScreen> {
  late final _ssid = TextEditingController(text: widget.credential.ssid ?? '');
  late final _password = TextEditingController(text: widget.credential.password ?? '');

  /// OCR로 아무것도 찾지 못했을 때 사용자가 "직접 입력"을 눌렀는지.
  late bool _editing = widget.manualEntry || !widget.credential.isEmpty;
  bool _obscurePassword = false;
  bool _connecting = false;
  WifiConnectResult? _result;
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
    setState(() {
      _ssidError = null;
      _passwordError = null;
      _result = null;
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
    });
    if (ssidError != null || passwordError != null) return;

    setState(() => _connecting = true);
    final result = await widget.wifiService.connect(ssid: ssid, password: password);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _result = result;
    });
    if (result.isSuccess) HapticFeedback.lightImpact();
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
                autofocus: _isManual || ssidMissing,
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
                autofocus: passwordMissing,
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
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _result == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: ConnectionStatusCard(
                          result: _result!,
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
              TextButton(
                onPressed: _connecting ? null : _close,
                child: const Text('다시 촬영'),
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
    if (result != null && result.isSuccess) {
      return FilledButton(onPressed: _close, child: const Text('완료'));
    }
    final label = switch (result?.status) {
      WifiConnectStatus.cancelled => '다시 연결',
      WifiConnectStatus.failed => '다시 시도',
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
    if (_isManual) return 'Wi-Fi 정보를 입력해주세요';
    if (_found.hasSsid && _found.hasPassword) return 'Wi-Fi를 찾았어요';
    if (_found.hasSsid) return 'Wi-Fi 이름은 찾았지만\n비밀번호를 찾지 못했어요';
    return '비밀번호는 찾았지만\nWi-Fi 이름을 찾지 못했어요';
  }

  String get _subtitle {
    if (_isManual) return '안내문에 적힌 Wi-Fi 이름과 비밀번호를 입력하세요.';
    if (!_found.hasSsid) return '안내문에 적힌 Wi-Fi 이름을 입력해주세요.';
    if (!_found.hasPassword) return '비밀번호를 입력해주세요. 비밀번호가 없는 Wi-Fi라면 비워두고 연결하세요.';
    final uncertain = _found.ssidConfidence < WifiCredential.confidentThreshold ||
        _found.passwordConfidence < WifiCredential.confidentThreshold;
    return uncertain ? '인식이 정확하지 않을 수 있어요. 확인 후 연결해주세요.' : '정보가 맞는지 확인하고 연결하세요.';
  }

  List<String> _alternatives(WifiCandidateType type, String current) => _found
      .candidatesOf(type)
      .map((c) => c.value)
      .where((v) => v != current.trim())
      .take(3)
      .toList();
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
