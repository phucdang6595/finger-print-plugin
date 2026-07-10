package com.example.fingerprint

import android.content.Context
import android.media.MediaDrm
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

/** FingerprintPlugin */
class FingerprintPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private var appContext: Context? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    appContext = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "fingerprint")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" ->
        result.success("Android ${Build.VERSION.RELEASE}")
      "getPersistentDeviceId" ->
        result.success(persistentDeviceId())
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    appContext = null
  }

  /**
   * 1) Widevine DRM device unique id
   * 2) ANDROID_ID (bỏ ID bug cũ)
   * 3) UUID lưu SharedPreferences (per-install)
   */
  private fun persistentDeviceId(): String {
    widevineId()?.let { return it }
    androidId()?.let { return it }
    return localPersistedUuid()
  }

  private fun widevineId(): String? {
    return try {
      val widevineUuid = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)
      val mediaDrm = MediaDrm(widevineUuid)
      try {
        val bytes = mediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
        if (bytes == null || bytes.isEmpty()) null
        else UUID.nameUUIDFromBytes(bytes).toString()
      } finally {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
          mediaDrm.close()
        } else {
          @Suppress("DEPRECATION")
          mediaDrm.release()
        }
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun androidId(): String? {
    val context = appContext ?: return null
    val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
    if (id.isNullOrBlank()) return null
    // Bug ID trên một số máy Android cũ
    if (id == "9774d56d682e549c") return null
    return UUID.nameUUIDFromBytes(id.toByteArray(Charsets.UTF_8)).toString()
  }

  private fun localPersistedUuid(): String {
    val context = appContext
      ?: return UUID.randomUUID().toString()
    val prefs = context.getSharedPreferences("fingerprint_device_id", Context.MODE_PRIVATE)
    val existing = prefs.getString("device_id", null)
    if (!existing.isNullOrBlank()) return existing
    val created = UUID.randomUUID().toString()
    prefs.edit().putString("device_id", created).apply()
    return created
  }
}
