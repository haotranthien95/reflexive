import 'package:wakelock_plus/wakelock_plus.dart';

/// The screen-wake capability, reduced to what an active session needs (D-30).
///
/// The default OS screen timeout is frequently shorter than one
/// thinking-time-plus-answer-length cycle, so without a wakelock the screen
/// locks mid-answer while the user is still speaking.
///
/// **Why this seam exists at all**, rather than calling `WakelockPlus` directly:
/// the package reaches a pigeon-generated method channel, so an unmediated call
/// raises `MissingPluginException` under `flutter test` — every widget test of
/// the practice screen would fail on a capability none of them are about. The
/// package does expose an `@visibleForTesting` global platform-instance
/// override, but that is a **static global**, a different shape from every other
/// platform dependency in this codebase (`RecorderBackend`,
/// `AudioPlaybackBackend`), and a shared global is order-dependent across tests
/// in a way an injected instance is not. So it is deliberately not used: this is
/// the third seam of the ESTABLISHED shape — abstract contract, private
/// production implementation, injected instance resolved lazily so a test that
/// supplies a fake never constructs a platform channel.
///
/// **Failures here are silent by contract.** Phase 2 introduces no new
/// user-facing failure string, and the UI-SPEC Copywriting Contract states a
/// wakelock failure reaches the debug log only. A screen that times out is a
/// nuisance; an error banner over a working session would be a lie about the
/// microphone. Both call sites wrap in `try`/`catch` and `debugPrint`.
abstract class ScreenWakeController {
  /// Keeps the screen on. Idempotent — the plugin checks the current status
  /// itself, so a redundant enable is not an error.
  Future<void> enable();

  /// Releases the hold and lets the OS screen timeout apply again.
  Future<void> disable();
}

/// The production implementation: `package:wakelock_plus`.
///
/// Android is a `FLAG_KEEP_SCREEN_ON` window flag and iOS is
/// `isIdleTimerDisabled`; neither needs a permission or an entitlement, which is
/// why this dependency leaves the release build's microphone-only posture
/// untouched. See the `wakelock_plus` row in `.claude/CLAUDE.md` for the
/// verification that backs that claim.
class WakelockPlusScreenWakeController implements ScreenWakeController {
  const WakelockPlusScreenWakeController();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
