import java.util.Properties

// AlphaNote Android — Configuration du module application
// Stack : Kotlin 1.9+ / Jetpack Compose / Material 3 / Room / Coroutines

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "be.cobaltfilms.alphanote"
    compileSdk = 34

    defaultConfig {
        applicationId = "be.cobaltfilms.alphanote"
        minSdk = 26
        targetSdk = 34
        // versionCode = major*10000 + minor*100 + patch (lisible, monotone).
        versionCode = 300
        versionName = "0.3.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    // Signature de release : ~/.alphanote/keystore.properties (hors dépôt), ou la
    // variable ALPHANOTE_KEYSTORE_PROPS. Sans fichier, la release est signée en
    // debug (installable, mais les mises à jour in-app exigent une clé stable).
    val keystorePropsFile = file(System.getenv("ALPHANOTE_KEYSTORE_PROPS") ?: "${System.getProperty("user.home")}/.alphanote/keystore.properties")
    val keystoreProps = Properties().apply { if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) } }
    val hasReleaseKey = keystoreProps.getProperty("storeFile") != null

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.5"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = false
        }
    }
}

dependencies {
    // Compose BOM — Material 3
    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.navigation:navigation-compose:2.7.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")

    // Coroutines + Flow
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")

    // Room (SQLite)
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")

    // OkHttp (pour API devises + WebDAV)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Kotlin JSON serialization (pour le parsing des réponses LLM)
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")

    // Core
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.datastore:datastore-preferences:1.0.0")

    // Tests unitaires
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013") // org.json réel dans les tests JVM (sinon « not mocked »)
    testImplementation("org.jetbrains.kotlin:kotlin-test:1.9.20")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")

    // Tests UI Compose
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
