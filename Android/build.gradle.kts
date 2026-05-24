// AlphaNote Android — Gradle racine
// Portage depuis macOS Swift/SwiftUI vers Kotlin/Jetpack Compose

plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
    // Room (KSP pour la compilation des annotations)
    id("com.google.devtools.ksp") version "1.9.20-1.0.14" apply false
}
