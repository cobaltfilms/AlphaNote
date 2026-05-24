# AlphaNote Android ProGuard rules
# Keep Kotlin metadata useful for reflection-safe libraries.
-keep class kotlin.Metadata { *; }

# Keep Room generated implementations.
-keep class * extends androidx.room.RoomDatabase
-keep class * implements androidx.room.RoomDatabase$Callback
-keep class **_Impl { *; }

# Keep JSON parser classes used by org.json based parsing.
-keep class org.json.** { *; }

# Keep app model used across Room and parsing flows.
-keep class be.cobaltfilms.alphanote.model.Note { *; }
