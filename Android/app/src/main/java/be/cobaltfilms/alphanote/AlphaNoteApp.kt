package be.cobaltfilms.alphanote

import android.app.Application
import be.cobaltfilms.alphanote.data.AppDatabase
import be.cobaltfilms.alphanote.domain.CurrencyRateService
import be.cobaltfilms.alphanote.timer.TimerRegistry

/** Classe Application — initialise les singletons (équivalent d'AlphaNoteApp.swift). */
class AlphaNoteApp : Application() {

    val database: AppDatabase by lazy { AppDatabase.getInstance(this) }

    override fun onCreate() {
        super.onCreate()
        instance = this
        CurrencyRateService.shared.attach(this)
        TimerRegistry.shared.attach(this)
    }

    companion object {
        lateinit var instance: AlphaNoteApp
            private set
    }
}
