// Device keys on Android (ADR 0050): an EC P-256 key in the Android Keystore
// (StrongBox when the device has it), usable for one signature after a
// BiometricPrompt with a CryptoObject. `alg: es256`; the public key goes out as
// the 65-byte uncompressed point, the signature as ASN.1 DER (SHA256withECDSA).

package uk.gencto.device_key

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DeviceKeyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: FragmentActivity? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(availability())
            "create" -> {
                val alias = call.argument<String>("alias")
                if (alias == null) {
                    result.error("failed", "alias missing", null)
                    return
                }
                val cred = call.argument<Boolean>("allowDeviceCredential") ?: false
                worker.execute {
                    try {
                        val pub = create(alias, cred)
                        main.post { result.success(mapOf("alg" to "es256", "publicKey" to pub)) }
                    } catch (e: Exception) {
                        main.post { result.error("failed", e.toString(), null) }
                    }
                }
            }
            "sign" -> {
                val alias = call.argument<String>("alias")
                val bytes = call.argument<ByteArray>("bytes")
                if (alias == null || bytes == null) {
                    result.success(mapOf("result" to "failed", "message" to "alias or bytes missing"))
                    return
                }
                val reason = call.argument<String>("reason") ?: "Unlock"
                val cancel = call.argument<String>("cancelLabel") ?: "Cancel"
                sign(alias, bytes, reason, cancel, result)
            }
            "delete" -> {
                val alias = call.argument<String>("alias")
                worker.execute {
                    try {
                        val ks = keyStore()
                        if (alias != null && ks.containsAlias(PREFIX + alias)) {
                            ks.deleteEntry(PREFIX + alias)
                        }
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        main.post { result.error("failed", e.toString(), null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ---- isAvailable ----

    private fun availability(): Map<String, String> {
        val none = mapOf("kind" to "none", "name" to "")
        if (BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG) !=
            BiometricManager.BIOMETRIC_SUCCESS
        ) {
            return none
        }
        val pm = context.packageManager
        val finger = pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        val face = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            pm.hasSystemFeature(PackageManager.FEATURE_FACE)
        val iris = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            pm.hasSystemFeature(PackageManager.FEATURE_IRIS)
        return when {
            finger && !face && !iris -> mapOf("kind" to "fingerprint", "name" to "Fingerprint")
            face && !finger && !iris -> mapOf("kind" to "face", "name" to "Face unlock")
            iris && !finger && !face -> mapOf("kind" to "iris", "name" to "Iris")
            else -> mapOf("kind" to "biometric", "name" to "Biometrics")
        }
    }

    // ---- create ----

    /// The device PIN may stand in only from API 30: before it, a CryptoObject
    /// cannot be used with DEVICE_CREDENTIAL, so the key is biometric-only.
    private fun create(alias: String, deviceCredential: Boolean): ByteArray {
        val cred = deviceCredential && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        val strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        val ks = keyStore()
        if (ks.containsAlias(PREFIX + alias)) {
            ks.deleteEntry(PREFIX + alias)
        }
        val pair = try {
            generate(alias, cred, strongBox)
        } catch (e: Exception) {
            if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                e is StrongBoxUnavailableException
            ) {
                generate(alias, cred, false)
            } else {
                throw e
            }
        }
        val pub = pair.public as ECPublicKey
        return byteArrayOf(4) + fixed32(pub.w.affineX) + fixed32(pub.w.affineY)
    }

    private fun generate(alias: String, cred: Boolean, strongBox: Boolean) =
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).run {
            val spec = KeyGenParameterSpec.Builder(PREFIX + alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(true)
                // Like Apple's `userPresence`, a key the PIN can open outlives
                // an enrollment change; a biometric-only key does not.
                .setInvalidatedByBiometricEnrollment(!cred)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val types = if (cred) {
                    KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
                } else {
                    KeyProperties.AUTH_BIOMETRIC_STRONG
                }
                spec.setUserAuthenticationParameters(0, types)
            } else {
                @Suppress("DEPRECATION")
                spec.setUserAuthenticationValidityDurationSeconds(-1)
            }
            if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                spec.setIsStrongBoxBacked(true)
            }
            initialize(spec.build())
            generateKeyPair()
        }

    // ---- sign ----

    private fun sign(
        alias: String,
        bytes: ByteArray,
        reason: String,
        cancel: String,
        result: MethodChannel.Result,
    ) {
        val done = AtomicBoolean(false)
        fun reply(code: String, extra: Map<String, Any> = emptyMap()) {
            if (done.compareAndSet(false, true)) {
                main.post { result.success(mapOf("result" to code) + extra) }
            }
        }

        val activity = this.activity
        if (activity == null) {
            reply("failed", mapOf("message" to "no FragmentActivity: MainActivity must be a FlutterFragmentActivity"))
            return
        }
        worker.execute {
            val key: PrivateKey
            val signature: Signature
            val cred: Boolean
            try {
                val entry = keyStore().getEntry(PREFIX + alias, null) as? KeyStore.PrivateKeyEntry
                if (entry == null) {
                    reply("invalidated")
                    return@execute
                }
                key = entry.privateKey
                cred = allowsDeviceCredential(key)
                signature = Signature.getInstance("SHA256withECDSA")
                signature.initSign(key)
            } catch (e: KeyPermanentlyInvalidatedException) {
                reply("invalidated", mapOf("message" to e.toString()))
                return@execute
            } catch (e: Exception) {
                reply("failed", mapOf("message" to e.toString()))
                return@execute
            }
            val authenticators = if (cred) BIOMETRIC_STRONG or DEVICE_CREDENTIAL else BIOMETRIC_STRONG
            when (BiometricManager.from(context).canAuthenticate(authenticators)) {
                BiometricManager.BIOMETRIC_SUCCESS -> {}
                else -> {
                    reply("unavailable")
                    return@execute
                }
            }
            main.post {
                try {
                    val prompt = BiometricPrompt(
                        activity,
                        ContextCompat.getMainExecutor(activity),
                        object : BiometricPrompt.AuthenticationCallback() {
                            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                                val s = r.cryptoObject?.signature
                                if (s == null) {
                                    reply("failed", mapOf("message" to "no signature object"))
                                    return
                                }
                                try {
                                    s.update(bytes)
                                    reply("signed", mapOf("signature" to s.sign()))
                                } catch (e: Exception) {
                                    reply("failed", mapOf("message" to e.toString()))
                                }
                            }

                            override fun onAuthenticationError(code: Int, message: CharSequence) {
                                reply(errorCode(code), mapOf("message" to message.toString()))
                            }

                            // One miss: the prompt stays open and says so itself.
                            override fun onAuthenticationFailed() {}
                        },
                    )
                    val info = BiometricPrompt.PromptInfo.Builder()
                        .setTitle(reason)
                        .setAllowedAuthenticators(authenticators)
                        .setConfirmationRequired(false)
                    if (!cred) {
                        info.setNegativeButtonText(cancel)
                    }
                    prompt.authenticate(info.build(), BiometricPrompt.CryptoObject(signature))
                } catch (e: Exception) {
                    reply("failed", mapOf("message" to e.toString()))
                }
            }
        }
    }

    private fun allowsDeviceCredential(key: PrivateKey): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        val info = KeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java)
        return info.userAuthenticationType and KeyProperties.AUTH_DEVICE_CREDENTIAL != 0
    }

    private fun errorCode(code: Int): String = when (code) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_CANCELED,
        BiometricPrompt.ERROR_TIMEOUT -> "cancelled"
        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
        BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> "unavailable"
        else -> "failed"
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    /// An unsigned coordinate as exactly 32 big-endian bytes.
    private fun fixed32(v: BigInteger): ByteArray {
        val raw = v.toByteArray()
        return when {
            raw.size == 32 -> raw
            raw.size > 32 -> raw.copyOfRange(raw.size - 32, raw.size)
            else -> ByteArray(32 - raw.size) + raw
        }
    }

    companion object {
        private const val CHANNEL = "uk.gencto.device_key"
        private const val PREFIX = "uk.gencto.device_key."
        private const val KEYSTORE = "AndroidKeyStore"
    }
}
