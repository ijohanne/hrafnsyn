package io.hrafnsyn.mobile

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

class NativeFlowTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test fun setupAndUnreachableServerRemainRecoverable() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        fun capture(name: String) {
            compose.waitForIdle()
            val bitmap = instrumentation.uiAutomation.takeScreenshot()
            try { File(context.filesDir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
            finally { bitmap.recycle() }
        }
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra("server", "")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)).use {
            compose.onNodeWithText("Connect to your server").assertIsDisplayed()
            capture("android-setup")
        }
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java).putExtra("server", "http://127.0.0.1:59999")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)).use {
            compose.waitUntil(30_000) { compose.onAllNodesWithText("Could not reach the gRPC server", substring = true).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("Connect", substring = false).assertIsEnabled()
            capture("android-error")
        }
    }

    @Test fun connectInspectAndReturnToMap() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val endpoint = InstrumentationRegistry.getArguments().getString("hrafnsynGrpcEndpoint")
        assumeTrue(!endpoint.isNullOrBlank())
        val context = instrumentation.targetContext
        val intent = Intent(context, MainActivity::class.java).putExtra("server", endpoint)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<MainActivity>(intent).use {
            compose.waitUntil(30_000) { compose.onAllNodesWithContentDescription("Overview").fetchSemanticsNodes().isNotEmpty() }
            // Allow native map tiles to settle; Compose cannot observe MapLibre's renderer.
            Thread.sleep(4000)
            compose.waitForIdle()
            fun capture(name: String) {
                val bitmap = instrumentation.uiAutomation.takeScreenshot()
                try { File(context.filesDir, "$name.png").outputStream().use { stream -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) } }
                finally { bitmap.recycle() }
            }
            capture("android-map")
            val list = compose.onAllNodesWithContentDescription("Show traffic")
            if (list.fetchSemanticsNodes().isNotEmpty()) list.onFirst().performClick()
            compose.onNodeWithText("Search traffic").assertIsDisplayed()
            capture("android-list")
            compose.waitUntil(15_000) { compose.onAllNodesWithTag("contact").fetchSemanticsNodes().isNotEmpty() }
            compose.onAllNodesWithTag("contact").onFirst().performClick()
            compose.waitUntil(15_000) { compose.onAllNodesWithText("Position").fetchSemanticsNodes().isNotEmpty() }
            Thread.sleep(1500)
            compose.waitForIdle()
            capture("android-inspector")
            compose.onNodeWithContentDescription("Close track details").performClick()
            compose.onNodeWithContentDescription("Overview").assertExists()
        }
    }
}
