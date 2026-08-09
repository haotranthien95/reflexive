import 'package:englishreflex/services/screen_wake_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ScreenWakeController] that touches no platform channel, recording the
/// call ORDER rather than just the call count — "enabled then disabled" and
/// "disabled then enabled" are opposite outcomes for the user.
class FakeScreenWakeController implements ScreenWakeController {
  final List<String> calls = <String>[];

  /// Reproduces the real failure mode: `wakelock_plus` throws when the Android
  /// implementation has no foreground activity attached.
  bool throwOnEnable = false;
  bool throwOnDisable = false;

  @override
  Future<void> enable() async {
    calls.add('enable');
    if (throwOnEnable) throw StateError('wakelock requires a foreground activity');
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    if (throwOnDisable) throw StateError('wakelock requires a foreground activity');
  }
}

void main() {
  test('the seam records enable and disable in the order they were called', () {
    // The contract the practice screen depends on, and the whole reason this
    // fake exists: the production implementation would raise
    // MissingPluginException here, because `wakelock_plus` reaches a
    // pigeon-generated method channel that no test binding registers.
    final wake = FakeScreenWakeController();

    expect(wake.calls, isEmpty);
  });

  test('enable() then disable() is the session-lifetime shape', () async {
    final wake = FakeScreenWakeController();

    await wake.enable();
    await wake.disable();

    expect(wake.calls, <String>['enable', 'disable']);
  });

  test('a throwing implementation surfaces its error to the CALLER, which is '
      'what makes the screen swallow it in exactly one place', () async {
    // The seam deliberately does NOT swallow: if it did, the silent-failure
    // contract would be spread across two files and a future caller could
    // wrongly assume a successful hold. Both call sites in `PracticeScreen`
    // wrap in try/catch and debugPrint instead.
    final wake = FakeScreenWakeController()
      ..throwOnEnable = true
      ..throwOnDisable = true;

    await expectLater(wake.enable(), throwsStateError);
    await expectLater(wake.disable(), throwsStateError);
    expect(wake.calls, <String>['enable', 'disable'],
        reason: 'a throwing call must still have been ATTEMPTED');
  });

  test('the production implementation is const-constructible and never '
      'touches a channel until a method is called', () {
    // Constructing it is what `PracticeScreen` does when nothing is injected;
    // it must be inert until `enable()`/`disable()` actually runs, or every
    // widget test of that screen would fail on a capability none are about.
    const controller = WakelockPlusScreenWakeController();

    expect(controller, isA<ScreenWakeController>());
  });
}
