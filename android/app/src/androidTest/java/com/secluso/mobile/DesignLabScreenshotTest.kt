package com.secluso.mobile

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DesignLabScreenshotTest {
    // The shell script and this instrumentation test both only need two knobs:
    // which design target to show and which theme to force before we capture it
    data class TargetSpec(
        val target: String,
        val theme: String,
    )

    companion object {
        private const val packageName = "com.secluso.mobile"
        private const val commandFileName = "design_command.txt"
        private const val screenshotRoot = "/sdcard/test-screenshots"
        private const val launchTimeoutMs = 45_000L
        private const val settleDelayMs = 2_500L
    }

    private lateinit var device: UiDevice
    private lateinit var commandFile: File
    private lateinit var screenshotDir: File
    private lateinit var targetSpecs: List<TargetSpec>

    @Before
    fun setUp() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val targetContext = instrumentation.targetContext
        val testContext = instrumentation.context

        device = UiDevice.getInstance(instrumentation)
        // The app already knows how to poll a command file and hot-swap design
        // targets. We lean on that instead of inventing a second debug-only
        // navigation API for tests.
        commandFile = File(targetContext.filesDir, commandFileName)
        screenshotDir = File(screenshotRoot).apply {
            mkdirs()
            listFiles()?.forEach { child ->
                if (child.extension.lowercase() == "png") {
                    child.delete()
                }
            }
        }
        targetSpecs = loadTargetSpecs(testContext)

        launchApp()
    }

    @Test
    fun captureAllDesignTargets() {
        assertTrue("Expected at least one design target to capture.", targetSpecs.isNotEmpty())

        targetSpecs.forEach { spec ->
            // We write the next desired target/theme into the command file, then give the Flutter side a short settle window to rebuild the
            // page and finish any entrance/layout work before the screenshot.
            writeCommand(spec)
            device.waitForIdle()
            Thread.sleep(settleDelayMs)

            val outFile = File(screenshotDir, "${spec.target}.png")
            assertTrue("Failed to take screenshot for ${spec.target}.", device.takeScreenshot(outFile))
        }
    }

    private fun launchApp() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(packageName)?.apply {
                // Start from a clean task so every Device Farm device begins
                // from the same visual baseline.
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        assertNotNull("Unable to resolve launch intent for $packageName.", launchIntent)
        context.startActivity(launchIntent)
        device.wait(Until.hasObject(By.pkg(packageName).depth(0)), launchTimeoutMs)
        // Flutter takes a second to boot and prime the design controller
        Thread.sleep(5_000L)
    }

    private fun writeCommand(spec: TargetSpec) {
        commandFile.parentFile?.mkdirs()
        commandFile.writeText(
            buildString {
                appendLine(spec.target)
                appendLine("theme=${spec.theme}")
                // The nonce is just a cheap change marker
                appendLine("nonce=${System.nanoTime()}")
            }
        )
    }

    private fun loadTargetSpecs(context: android.content.Context): List<TargetSpec> {
        context.assets.open("design_targets_android.txt").bufferedReader().useLines { lines ->
            return lines
                .map { it.trim() }
                // The manifest is meant to stay hand-editable
                .filter { it.isNotEmpty() && !it.startsWith("#") }
                .map { row ->
                    val parts = row.split('|')
                    TargetSpec(
                        target = parts[0].trim(),
                        theme =
                            parts.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }
                                ?: "dark",
                    )
                }
                .toList()
        }
    }
}
