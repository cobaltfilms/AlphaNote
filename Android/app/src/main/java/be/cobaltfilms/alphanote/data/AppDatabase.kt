package be.cobaltfilms.alphanote.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
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
                .addCallback(object : RoomDatabase.Callback() {
                    // Contenu effacé ou remplacé mis à zéro : une note passée au
                    // coffre ne laisse pas son ancien texte en clair.
                    override fun onOpen(db: SupportSQLiteDatabase) {
                        db.query("PRAGMA secure_delete=ON").use { it.moveToFirst() }
                    }
                })
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
