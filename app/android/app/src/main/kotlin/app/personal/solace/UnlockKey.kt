package app.personal.solace

import android.annotation.TargetApi
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// Round 5 review, C-08: the data key is kept in flutter_secure_storage only wrapped with this key, an AES-256-GCM key in
// the Android Keystore that works only while the phone is unlocked (setUnlockedDeviceRequired, Android 9 and later).
// It needs no user authentication (Solace never asks for the device's own unlock: owner, 2026-11-15), the Keystore
// picks every IV (setRandomizedEncryptionRequired), and it lives in StrongBox when the phone has one. A running Solace
// keeps working while the phone is locked, as it holds the data key in memory from the moment it opened
// (lib/core/unlock_key.dart, lib/core/store.dart).
//
// Channel app.personal.solace/unlock_key:
//   wrap(bytes)   -> IV (12 bytes) + ciphertext and GCM tag; errors: unavailable, locked, failed, bad_input
//   unwrap(bytes) -> the bytes wrapped;                     errors: locked, gone, failed, bad_input
//   forget()      -> deletes the key (Delete everything, after every wrapped value is gone)
// "unavailable": Android 8.1 or below, no secure screen lock, or the Keystore would not make the key; the Dart side
// then keeps the value as before. "gone": the key is no longer in the Keystore, or the value is not one it wrapped,
// so it can never be opened here. Every call runs off the main thread, one at a time (so two first wraps can never
// make two keys), and its answer comes back on the main thread.
//
// Round 10 review A, R10A-04: every call is answered, whatever is thrown (a java.lang.Error from Keystore code
// included: some builds throw NoSuchFieldError there, and one left uncaught was never answered and ended the app); the
// Dart side also stops waiting after a time limit (lib/core/unlock_key.dart). When the Keystore refuses the key, the
// answer follows the phone's real state (KeyguardManager), not the exception alone (review observation O-1): "locked"
// only while the phone really is locked; "gone" when it is unlocked and the refusal is one the Keystore never takes
// back, or the phone has no screen lock left (the key works only on a phone with one: on Android 14, removing the
// screen lock deletes it), so a removed screen lock leads to Start fresh, never to an endless "Unlock your phone";
// anything else is a failure to try again. A refusal "as locked" on a phone that says it is unlocked is tried once
// more after a moment first (the Keystore may not have heard of the unlock yet).
object UnlockKey {
    private const val CHANNEL = "app.personal.solace/unlock_key"
    private const val ALIAS = "solace_unlock_wrap_v1"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val TAG_BYTES = TAG_BITS / 8
    private const val MAX_VALUE = 4096 // bounded input: a data key is 44 bytes
    private const val SETTLE_MS = 500L // the wait before a refusal "as locked" on an unlocked phone is tried again

    private class Refusal(val code: String) : Exception(code)

    /** No key under ALIAS: the Keystore no longer has it. */
    private class KeyMissing : Exception("no key")

    /** The phone as KeyguardManager reports it. */
    private enum class Phone { LOCKED, UNLOCKED, NO_SCREEN_LOCK, UNKNOWN }

    /** How the Keystore refused the key: for good, as if the phone were locked, or some other way. */
    private enum class Refused { FOR_GOOD, AS_LOCKED, OTHER }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val input = call.arguments as? ByteArray
            when (call.method) {
                "wrap", "unwrap", "forget" -> {
                    val run = Runnable {
                        val outcome: Pair<Any?, String?> = try {
                            Pair(answer(call.method, app, input), null)
                        } catch (e: Refusal) {
                            Pair(null, e.code)
                        } catch (e: Throwable) {
                            // R10A-04: any other failure, an Error included, is answered too
                            Pair(null, if (phone(app) == Phone.LOCKED) "locked" else "failed")
                        }
                        main.post {
                            val error = outcome.second
                            if (error == null) result.success(outcome.first) else result.error(error, null, null)
                        }
                    }
                    try {
                        worker.execute(run)
                    } catch (e: Throwable) {
                        result.error("failed", null, null) // the worker would not take the call: answered here
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun answer(method: String, context: Context, input: ByteArray?): Any? = when (method) {
        "wrap" -> wrap(context, input)
        "unwrap" -> unwrap(context, input)
        else -> {
            forget()
            null
        }
    }

    /** The phone's state; UNKNOWN when it cannot be read (never thrown). */
    private fun phone(context: Context): Phone {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return Phone.UNKNOWN
        try {
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager ?: return Phone.UNKNOWN
            if (keyguard.isDeviceLocked) return Phone.LOCKED
            if (!keyguard.isDeviceSecure) return Phone.NO_SCREEN_LOCK
            return Phone.UNLOCKED
        } catch (e: Throwable) {
            return Phone.UNKNOWN
        }
    }

    /** What a refusal of the key means for an unwrap, from the phone's real state (O-1). */
    private fun refusal(context: Context, why: Refused): Refusal {
        val state = phone(context)
        return Refusal(when {
            state == Phone.LOCKED -> "locked" // nothing is given up while the phone is locked
            why == Refused.FOR_GOOD -> "gone" // the key is missing or invalidated: it can never work again
            // no screen lock left to unlock it with: a key that needs an unlocked device can never work again
            why == Refused.AS_LOCKED && state == Phone.NO_SCREEN_LOCK -> "gone"
            // round 10 review A (R10A-08): refused as locked on a phone the system calls unlocked. Smart Lock or a
            // weaker face unlock (Android 12 to 14) unlocks the phone but not these keys, which wait for the PIN,
            // pattern or password; that is "locked", never "gone", so nothing is set aside
            why == Refused.AS_LOCKED -> "locked"
            else -> "failed" // anything else may pass: Try again, never Start fresh
        })
    }

    private fun kind(e: Throwable): Refused = when (e) {
        is KeyMissing, is KeyPermanentlyInvalidatedException, is AEADBadTagException -> Refused.FOR_GOOD
        is UserNotAuthenticatedException -> Refused.AS_LOCKED
        else -> Refused.OTHER
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun wrap(context: Context, clear: ByteArray?): ByteArray {
        if (clear == null || clear.isEmpty() || clear.size > MAX_VALUE) throw Refusal("bad_input")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) throw Refusal("unavailable")
        when (phone(context)) {
            Phone.LOCKED -> throw Refusal("locked")
            Phone.UNLOCKED -> Unit
            // with no secure screen lock there is no locked state to protect, and some Android versions cannot make or
            // keep such a key then (nor can a phone that cannot say): the value is kept as before
            else -> throw Refusal("unavailable")
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            cipher.init(Cipher.ENCRYPT_MODE, existingKey() ?: makeKey(context)) // the Keystore picks the IV
        } catch (e: UserNotAuthenticatedException) {
            // "locked" only when the phone says so too (O-1); on an unlocked phone, once more after a moment, and then
            // a failure to try again: a write never gives a key up
            if (phone(context) != Phone.UNLOCKED) throw Refusal(if (phone(context) == Phone.LOCKED) "locked" else "failed")
            Thread.sleep(SETTLE_MS)
            try {
                cipher.init(Cipher.ENCRYPT_MODE, existingKey() ?: makeKey(context))
            } catch (again: UserNotAuthenticatedException) {
                throw Refusal(if (phone(context) == Phone.LOCKED) "locked" else "failed")
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // a key the Keystore will never use again opens nothing it wrapped either (those reads say "gone", and
            // Start fresh moves them aside): a new key is made, so Solace can keep its data key again
            keyStore().deleteEntry(ALIAS)
            cipher.init(Cipher.ENCRYPT_MODE, makeKey(context))
        }
        val iv = cipher.iv
        if (iv == null || iv.size != IV_BYTES) throw Refusal("failed")
        val sealed = cipher.doFinal(clear)
        if (sealed.size != clear.size + TAG_BYTES) throw Refusal("failed")
        return iv + sealed
    }

    private fun unwrap(context: Context, wrapped: ByteArray?): ByteArray {
        if (wrapped == null || wrapped.size <= IV_BYTES + TAG_BYTES || wrapped.size > MAX_VALUE + IV_BYTES + TAG_BYTES) {
            throw Refusal("bad_input")
        }
        // never wrapped below Android 9: a failure to look into, never a key to give up on
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) throw Refusal("failed")
        return try {
            open(wrapped)
        } catch (e: UserNotAuthenticatedException) {
            // the Keystore refused as if the phone were locked: believed only if the phone says so (O-1); an unlocked
            // phone's Keystore may not have heard of the unlock yet, so the key is tried once more after a moment
            if (phone(context) != Phone.UNLOCKED) throw refusal(context, Refused.AS_LOCKED)
            Thread.sleep(SETTLE_MS)
            try {
                open(wrapped)
            } catch (again: Exception) {
                throw refusal(context, kind(again))
            }
        } catch (e: Exception) {
            throw refusal(context, kind(e))
        }
    }

    /** The bytes inside [wrapped]; throws KeyMissing when the Keystore no longer has the key. */
    private fun open(wrapped: ByteArray): ByteArray {
        val key = existingKey() ?: throw KeyMissing()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, wrapped, 0, IV_BYTES))
        return cipher.doFinal(wrapped, IV_BYTES, wrapped.size - IV_BYTES)
    }

    private fun forget() {
        val ks = keyStore()
        if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS)
    }

    private fun existingKey(): SecretKey? {
        val ks = keyStore()
        if (!ks.containsAlias(ALIAS)) return null
        return ks.getKey(ALIAS, null) as? SecretKey ?: throw Refusal("failed")
    }

    // Only ever called when the Keystore has no key under ALIAS, and only on the single worker thread.
    @TargetApi(Build.VERSION_CODES.P)
    private fun makeKey(context: Context): SecretKey {
        val strongBox = context.packageManager.hasSystemFeature("android.hardware.strongbox_keystore")
        if (strongBox) {
            try {
                return generate(true)
            } catch (e: Exception) {
                // StrongBox unavailable just now, or refusing one of the settings: the ordinary Keystore below
            }
        }
        return try {
            generate(false)
        } catch (e: Exception) {
            throw Refusal(if (phone(context) == Phone.LOCKED) "locked" else "unavailable")
        }
    }

    @TargetApi(Build.VERSION_CODES.P)
    private fun generate(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(strongBox)
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(spec)
        return generator.generateKey()
    }
}
