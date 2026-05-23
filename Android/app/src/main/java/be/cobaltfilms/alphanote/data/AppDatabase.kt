package be.cobaltfilms.alphanote.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import be.cobaltfilms.alphanote.model.Note

/**
 * Base de données Room pour AlphaNote.
 * Schema identique à la version macOS (GRDB.swift → Room).
 */
@Database(
    entities = [Note::class],
    version = 1,
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun noteDao(): NoteDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        /**
         * Retourne l'instance singleton de la base de données.
         * En test, utiliser Room.inMemoryDatabaseBuilder().
         */
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: buildDatabase(context).also { INSTANCE = it }
            }
        }

        private fun buildDatabase(context: Context): AppDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                AppDatabase::class.java,
                "alphanote.db"
            )
                .fallbackToDestructiveMigration()
                .build()
        }

        /** Pour les tests unitaires : base en mémoire */
        fun createInMemory(context: Context): AppDatabase {
            return Room.inMemoryDatabaseBuilder(
                context.applicationContext,
                AppDatabase::class.java
            ).build()
        }
    }
}
