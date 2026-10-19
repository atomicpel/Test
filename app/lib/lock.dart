import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

String newSalt() {
  final r = math.Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

bool pinEnabled(Store s) => s.local<String>('pinHash', '').isNotEmpty;

bool checkPin(Store s, String pin) =>
    hashPin(pin, s.local<String>('pinSalt', '')) == s.local<String>('pinHash', '');

void setPin(Store s, String? pin) {
  if (pin == null) {
    s.setLocal('pinHash', null);
    s.setLocal('pinSalt', null);
    s.setLocal('bio', null);
    return;
  }
  final salt = newSalt();
  s.setLocal('pinSalt', salt);
  s.setLocal('pinHash', hashPin(pin, salt));
}

/// Вход по отпечатку/лицу. Любая ошибка — просто false (остаётся PIN).
Future<bool> tryBiometric() async {
  try {
    final auth = LocalAuthentication();
    final can = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (!can) return false;
    return await auth.authenticate(
      localizedReason: 'Вход в «Мой цикл»',
      biometricOnly: true,
    );
  } catch (e) {
    debugPrint('biometric: $e');
    return false;
  }
}

Future<bool> biometricAvailable() async {
  try {
    final auth = LocalAuthentication();
    return await auth.canCheckBiometrics;
  } catch (_) {
    return false;
  }
}

/// Блокирует приложение PIN-кодом при запуске и после 30 секунд в фоне.
class LockGate extends StatefulWidget {
  final Store store;
  final Widget child;
  const LockGate({super.key, required this.store, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = pinEnabled(widget.store);
  DateTime? _bg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _bg = DateTime.now();
    if (state == AppLifecycleState.resumed && _bg != null) {
      if (pinEnabled(widget.store) &&
          DateTime.now().difference(_bg!) > const Duration(seconds: 30)) {
        setState(() => _locked = true);
      }
      _bg = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      Positioned.fill(child: AnimatedSwitcher(
        duration: motion(context, 350),
        transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
                scale: Tween<double>(begin: 1.06, end: 1).animate(a), child: c)),
        child: _locked
            ? PinScreen(
                key: const ValueKey('lock'),
                title: 'Введите PIN-код',
                allowBiometric: widget.store.local<bool>('bio', false),
                check: (p) => checkPin(widget.store, p),
                onDone: (_) => setState(() => _locked = false),
              )
            : const SizedBox.shrink(key: ValueKey('open')),
      )),
    ]);
  }
}

/// Экран ввода PIN: точки, цифровая клавиатура, «тряска» при ошибке.
class PinScreen extends StatefulWidget {
  final String title;
  final bool allowBiometric;
  final bool Function(String)? check;
  final ValueChanged<String> onDone;
  final VoidCallback? onCancel;
  const PinScreen(
      {super.key,
      required this.title,
      this.allowBiometric = false,
      this.check,
      required this.onDone,
      this.onCancel});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    if (widget.allowBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _bio() async {
    if (await tryBiometric() && mounted) widget.onDone('');
  }

  void _tap(String d) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        if (widget.check == null || widget.check!(_pin)) {
          widget.onDone(_pin);
        } else {
          HapticFeedback.heavyImpact();
          _shake.forward(from: 0);
          setState(() => _pin = '');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', 'del'];
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(children: [
          if (widget.onCancel != null)
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                  icon: const Icon(Icons.close, size: 30), onPressed: widget.onCancel),
            ),
          const Spacer(),
          Icon(Icons.lock_outline, size: 46, color: accent),
          const SizedBox(height: 14),
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) => Transform.translate(
              offset: Offset(math.sin(_shake.value * math.pi * 6) * 14 * (1 - _shake.value), 0),
              child: child,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 4; i++)
                AnimatedContainer(
                  duration: motion(context, 180),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: i < _pin.length ? 20 : 16,
                  height: i < _pin.length ? 20 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? accent : Colors.transparent,
                    border: Border.all(color: accent, width: 2),
                  ),
                ),
            ]),
          ),
          const Spacer(),
          SizedBox(
            width: 300,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 26,
              children: [
                for (final k in keys)
                  if (k == 'bio' && !widget.allowBiometric)
                    const SizedBox()
                  else
                    Pressable(
                      onTap: () {
                        if (k == 'del') {
                          if (_pin.isNotEmpty) {
                            HapticFeedback.selectionClick();
                            setState(() => _pin = _pin.substring(0, _pin.length - 1));
                          }
                        } else if (k == 'bio') {
                          _bio();
                        } else {
                          _tap(k);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: k == 'del' || k == 'bio'
                              ? Colors.transparent
                              : AppColors.of(context).card,
                          border: k == 'del' || k == 'bio'
                              ? null
                              : Border.all(color: AppColors.of(context).cardBorder),
                        ),
                        alignment: Alignment.center,
                        child: k == 'del'
                            ? const Icon(Icons.backspace_outlined, size: 28)
                            : k == 'bio'
                                ? Icon(Icons.fingerprint, size: 38, color: accent)
                                : Text(k,
                                    style: const TextStyle(
                                        fontFamily: kFont,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w600)),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 36),
        ]),
      ),
    );
  }
}

/// Установка PIN: ввести дважды. Возвращает PIN или null.
Future<String?> setupPin(BuildContext context) async {
  String? first;
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => PinScreen(
        key: ValueKey(first == null ? 'a' : 'b'),
        title: first == null ? 'Придумайте PIN-код' : 'Повторите PIN-код',
        onCancel: () => Navigator.pop(ctx),
        check: first == null ? null : (p) => p == first,
        onDone: (p) {
          if (first == null) {
            set(() => first = p);
          } else {
            Navigator.pop(ctx, p);
          }
        },
      ),
    ),
  ));
}

void showPinHint(BuildContext context) => showSnack(
    context, 'Если забудете PIN, переустановите приложение — данные вернутся с сервера.');
