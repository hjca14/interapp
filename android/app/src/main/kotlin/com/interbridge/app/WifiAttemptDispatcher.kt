package com.interbridge.app

/**
 * Ensures `ProvisionListener` callback bodies — invoked by the Espressif
 * SDK on its own internal executor thread, and which for `wifiConfigSent()`
 * specifically proceed straight into `applyWiFiConfig()` on that same call
 * stack immediately after the callback returns (confirmed in decompiled
 * `ESPDevice.class` bytecode) — never do Flutter/GATT work themselves and
 * never let an exception escape back into that stack. A callback captures
 * only already-decided, sanitized work and hands it to [deliver], which
 * posts it via [poster] (production: `Handler(Looper.getMainLooper())::post`)
 * instead of running it there and then.
 *
 * Also the single point deciding whether a delivery is stale: [beginAttempt]
 * marks a new attempt as the active one, [endAttempt] retires a specific
 * attempt, and [isActive] is what a delivery checks once it actually runs.
 * A [deliver] call for an attempt that is no longer active by then — because
 * a newer attempt has started, or this one already ended (a terminal
 * outcome, or an external disconnect) — becomes a no-op: a late SDK callback
 * can never revive or double-settle an attempt. All of [beginAttempt],
 * [endAttempt], [isActive], and the delivered actions are only ever touched
 * from the poster's own thread (the main thread in production) — [deliver]
 * itself is the only member safe to call from another thread.
 */
class WifiAttemptDispatcher(private val poster: (Runnable) -> Unit) {
    private var activeAttemptId = 0

    /** Call once, synchronously, right before invoking `provision()`. */
    fun beginAttempt(): Int {
        activeAttemptId += 1
        return activeAttemptId
    }

    /** True exactly while [attemptId] is the current, live attempt. */
    fun isActive(attemptId: Int): Boolean = attemptId != 0 && attemptId == activeAttemptId

    /** No-op if [attemptId] is not the current attempt (already superseded). */
    fun endAttempt(attemptId: Int) {
        if (activeAttemptId == attemptId) activeAttemptId = 0
    }

    /** Unconditionally retires whichever attempt is currently active, if any. */
    fun endActiveAttempt() {
        activeAttemptId = 0
    }

    /**
     * Defers [action] to [poster], running it only if [attemptId] is still
     * active at that later point. Called from the SDK's own callback stack —
     * under no circumstances may this throw back into it, so scheduling
     * itself is guarded (silently — this class stays a plain, Android-free
     * unit for testability; the caller's own logging covers the ordinary
     * cases) even though a plain `Handler.post` is not expected to fail.
     */
    fun deliver(attemptId: Int, action: () -> Unit) {
        try {
            poster(Runnable { if (isActive(attemptId)) action() })
        } catch (t: Throwable) {
            // Deliberately swallowed — see the doc above.
        }
    }
}
