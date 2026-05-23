package be.cobaltfilms.alphanote

import android.app.Application
import be.cobaltfilms.alphanote.data.AppDatabase

/**
 * Classe Application — initialise les singletons au démarrage.
 * Équivalent Android de AlphaNoteApp.swift (macOS).
 */
class AlphaNoteApp : Application() {

    /** Référence à la base de données (initialisée paresseusement) */
    val database: AppDatabase by lazy {
        AppDatabase.getInstance(this)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: AlphaNoteApp
            private set
    }
}
