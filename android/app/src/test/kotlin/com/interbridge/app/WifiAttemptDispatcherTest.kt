package com.interbridge.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Records posted [Runnable]s instead of running them — [drain] runs them later, in order. */
private class RecordingPoster : (Runnable) -> Unit {
    private val queued = mutableListOf<Runnable>()

    override fun invoke(runnable: Runnable) {
        queued.add(runnable)
    }

    fun drain() {
        val pending = queued.toList()
        queued.clear()
        pending.forEach { it.run() }
    }
}

class WifiAttemptDispatcherTest {
    @Test
    fun `deliver never runs the action synchronously — only once the poster drains it`() {
        val poster = RecordingPoster()
        val dispatcher = WifiAttemptDispatcher(poster)
        val attemptId = dispatcher.beginAttempt()

        var ran = false
        dispatcher.deliver(attemptId) { ran = true }
        assertFalse("must not run before the poster drains it", ran)

        poster.drain()
        assertTrue(ran)
    }

    @Test
    fun `deliveries for the same attempt run in the order they were scheduled`() {
        val poster = RecordingPoster()
        val dispatcher = WifiAttemptDispatcher(poster)
        val attemptId = dispatcher.beginAttempt()

        val order = mutableListOf<Int>()
        dispatcher.deliver(attemptId) { order.add(1) }
        dispatcher.deliver(attemptId) { order.add(2) }
        dispatcher.deliver(attemptId) { order.add(3) }
        poster.drain()

        assertEquals(listOf(1, 2, 3), order)
    }

    @Test
    fun `a delivery for an attempt that already ended is dropped`() {
        val poster = RecordingPoster()
        val dispatcher = WifiAttemptDispatcher(poster)
        val attemptId = dispatcher.beginAttempt()

        var ran = false
        dispatcher.deliver(attemptId) { ran = true }
        dispatcher.endAttempt(attemptId)
        poster.drain()

        assertFalse(
            "a terminal outcome that already ended the attempt must not be " +
                "revived by a late/queued delivery for it",
            ran,
        )
    }

    @Test
    fun `a late delivery for a superseded attempt is dropped once a new attempt begins`() {
        val poster = RecordingPoster()
        val dispatcher = WifiAttemptDispatcher(poster)

        val firstAttempt = dispatcher.beginAttempt()
        var firstRan = false
        dispatcher.deliver(firstAttempt) { firstRan = true }

        val secondAttempt = dispatcher.beginAttempt()
        var secondRan = false
        dispatcher.deliver(secondAttempt) { secondRan = true }

        poster.drain()

        assertFalse("the superseded attempt's delivery must never run", firstRan)
        assertTrue("the current attempt's delivery must still run normally", secondRan)
    }

    @Test
    fun `endActiveAttempt retires whichever attempt is active without needing its id`() {
        val poster = RecordingPoster()
        val dispatcher = WifiAttemptDispatcher(poster)
        val attemptId = dispatcher.beginAttempt()

        var ran = false
        dispatcher.deliver(attemptId) { ran = true }
        dispatcher.endActiveAttempt()
        poster.drain()

        assertFalse(ran)
    }

    @Test
    fun `an attempt not yet started, or already ended, is never active`() {
        val dispatcher = WifiAttemptDispatcher({})
        assertFalse(dispatcher.isActive(0))

        val attemptId = dispatcher.beginAttempt()
        assertTrue(dispatcher.isActive(attemptId))

        dispatcher.endAttempt(attemptId)
        assertFalse(dispatcher.isActive(attemptId))
    }

    @Test
    fun `deliver never throws back into the caller even if the poster itself throws`() {
        val dispatcher = WifiAttemptDispatcher({ throw RuntimeException("boom") })
        val attemptId = dispatcher.beginAttempt()

        dispatcher.deliver(attemptId) {}
        // Reaching this line is the assertion — deliver() must not propagate
        // an exception back into the SDK's own callback stack.
    }
}
