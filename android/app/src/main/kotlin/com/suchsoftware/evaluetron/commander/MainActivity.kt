package com.suchsoftware.evaluetron.commander

import android.net.VpnService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native boundary for Commander's optional managed-network engine.
 *
 * No tunnel engine is embedded yet. Every mutating method therefore fails
 * closed and the Flutter UI reports that state explicitly.
 *
 * Extends [FlutterFragmentActivity] rather than `FlutterActivity` because
 * AndroidX `BiometricPrompt`, used by the local user-presence gate in front of
 * privileged operator actions, requires a `FragmentActivity` host.
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL =
            "com.suchsoftware.evaluetron.commander/managed_network"
        private const val ENGINE_EMBEDDED = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> result.success(
                    mapOf(
                        "availability" to if (ENGINE_EMBEDDED) {
                            "available"
                        } else {
                            "engineNotInstalled"
                        },
                        "platform" to "android",
                        "vpnServiceDeclared" to true,
                        "engineVersion" to null,
                        "consentRequired" to (VpnService.prepare(this) != null),
                    ),
                )
                "status" -> result.success(unavailableStatus())
                "requestConsent", "connect", "disconnect" -> result.error(
                    "engine_unavailable",
                    "The audited Nebula engine is not embedded in this build.",
                    null,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun unavailableStatus(): Map<String, String> = mapOf(
        "lifecycle" to "unavailable",
        "message" to "Managed network engine is not installed.",
    )
}
