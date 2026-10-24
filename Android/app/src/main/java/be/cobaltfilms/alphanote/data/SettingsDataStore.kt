package be.cobaltfilms.alphanote.data

import android.content.Context
import androidx.datastore.preferences.preferencesDataStore

val Context.alphaNoteSettingsDataStore by preferencesDataStore(name = "alphanote_settings")
