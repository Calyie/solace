package app.personal.solace

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import java.lang.ref.WeakReference
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: first chosen for a system unlock prompt, which Solace no longer uses (owner, 2026-11-15: the
// app lock is Solace's own six-digit passcode only); kept, as it runs the app as FlutterActivity does and changing
// the base class would need a device build to confirm.
//
// Screenshots, screen recording and copying are allowed (owner, 2026-11-19: "remove this option you have that prevents
// screenshotting on solace or right-clicking and copying text from solace as that is tiring and frustrating"): no
// FLAG_SECURE anywhere. "Hide in the app switcher" now hides only the recent-apps preview, on Android 13 and later
// (setRecentsScreenshotEnabled, which leaves screenshots alone), and the app's own cover (ui/app_lock.dart).
class MainActivity : FlutterFragmentActivity() {
    // OWASP review OW-M8-2: touches are ignored while another app draws over Solace (tapjacking; dispatchTouchEvent
    // below), and no outside link or intent can open a screen inside it.
    //
    // Round 4 review (A-06): this is the launcher's screen, so any app can start it, and Flutter reads extras from the
    // intent that started it (a cached engine, engine arguments, Dart flags): a made-up cached engine id stopped the
    // whole app, a session in progress included. Every extra is removed before Flutter sees the intent, and the engine
    // settings never come from it. A second copy of this screen (another app starting it into its own task) would run
    // a second copy of Solace in this process, writing the same store: it closes at once and the first one stays.
    companion object {
        private var live: WeakReference<MainActivity>? = null
    }

    // Round 8 (OW-M8-2): the link (data) goes too, so nothing in Flutter or a plugin can ever read an outside link
    private fun withoutExtras(i: Intent?): Intent? = i?.let {
        Intent(it).apply {
            replaceExtras(null as Bundle?)
            data = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        intent = withoutExtras(intent)
        // the recent-apps preview is hidden from the first frame (the Dart side shows it only if the person chose to
        // show Solace in the app switcher); screenshots are never blocked (owner, 2026-11-19)
        hideRecentsPreview(true)
        val first = live?.get()
        if (first != null && first !== this && !first.isFinishing && !first.isDestroyed) {
            super.onCreate(savedInstanceState)
            finish()
            return
        }
        live = WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    // Round 8 (OW-M8-2): a touch that lands where another app draws over Solace (FLAG_WINDOW_IS_OBSCURED: tapjacking)
    // is refused for its whole gesture. This replaces filterTouchesWhenObscured on the window's view, which dropped
    // single events: a gesture that became obscured half-way (a second finger under an overlay) left Flutter with a
    // finger it thought was still down. Such a gesture is now cancelled, then refused to its end. Solace's own windows
    // never count (Android 12 and later ignore windows of the same app), nor do the keyboard, the status bar and the
    // system's own overlays. A window elsewhere on the screen (FLAG_WINDOW_IS_PARTIALLY_OBSCURED: a video in
    // picture-in-picture, a chat bubble, a toast) does not refuse touches: Solace, its crisis screen included, would
    // stop answering for as long as one is on screen.
    private var refusing = false

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val obscured = (ev.flags and MotionEvent.FLAG_WINDOW_IS_OBSCURED) != 0
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            refusing = obscured
        } else if (obscured && !refusing) {
            val cancel = MotionEvent.obtain(ev)
            cancel.action = MotionEvent.ACTION_CANCEL
            super.dispatchTouchEvent(cancel)
            cancel.recycle()
            refusing = true
        }
        return if (refusing) true else super.dispatchTouchEvent(ev)
    }

    // "Hide in the app switcher": Android 13 and later show a blank preview in recent apps; screenshots and screen
    // recording are unaffected. Older Android has no such switch without FLAG_SECURE, which also blocks screenshots,
    // so there the preview shows Solace (docs/SECURITY.md section 7).
    private fun hideRecentsPreview(hidden: Boolean) {
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(!hidden)
    }

    override fun onNewIntent(intent: Intent) {
        val clean = withoutExtras(intent)!!
        setIntent(clean)
        super.onNewIntent(clean)
    }

    override fun onDestroy() {
        if (live?.get() === this) live = null
        super.onDestroy()
    }

    override fun getCachedEngineId(): String? = null
    override fun getCachedEngineGroupId(): String? = null
    override fun getDartEntrypointArgs(): List<String>? = null

    override fun getInitialRoute(): String = "/"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // round 5 review, C-08: the key that wraps the data key, usable only while the phone is unlocked (UnlockKey.kt)
        UnlockKey.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "solace/privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "setRecentsHidden" -> {
                    hideRecentsPreview(call.arguments == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // the device's storage, so Solace's own room is a small share of it (core/storage.dart, 2026-11-14)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "solace/storage").setMethodCallHandler { call, result ->
            if (call.method == "space") {
                val stat = android.os.StatFs(filesDir.absolutePath)
                result.success(mapOf("total" to stat.totalBytes, "free" to stat.availableBytes))
            } else {
                result.notImplemented()
            }
        }
        // the screen stays on while the quiet timer or the sleep wind-down runs (core/screen_awake.dart, 2026-11-14)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "solace/screen").setMethodCallHandler { call, result ->
            if (call.method == "setKeepAwake") {
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
