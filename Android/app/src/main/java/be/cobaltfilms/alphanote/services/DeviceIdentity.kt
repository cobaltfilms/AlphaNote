package be.cobaltfilms.alphanote.services

import android.content.Context
import java.util.UUID

object DeviceIdentity {
    private const val PREFS_NAME = "alphanote_device_identity"
    private const val DEVICE_ID_KEY = "device_id"

    fun currentDeviceId(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(DEVICE_ID_KEY, null)
        if (!existing.isNullOrBlank()) return existing

        val generated = "android-${UUID.randomUUID().toString().lowercase()}"
        prefs.edit().putString(DEVICE_ID_KEY, generated).apply()
        return generated
    }
}
