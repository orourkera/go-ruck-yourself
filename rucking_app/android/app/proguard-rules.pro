# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Gal package - for saving to camera roll
-keep class com.natsune.gal.** { *; }
-dontwarn com.natsune.gal.**

# Keep all Flutter plugins
-dontwarn io.flutter.embedding.**
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.embedding.** { *; }

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firebase - Critical for preventing channel-error
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-keep class io.flutter.plugins.firebase.crashlytics.** { *; }
-keep class io.flutter.plugins.firebase.analytics.** { *; }
-keep class com.google.firebase.provider.FirebaseInitProvider { *; }
-keep class com.google.firebase.components.** { *; }
-dontwarn com.google.firebase.**

# Supabase and related
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Keep crash reporting data
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*

# General Android rules
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keepclassmembers class fqcn.of.javascript.interface.for.webview {
    public *;
}

# Preserve all native method names and the names of their classes.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep setters in Views so that animations can still work.
-keepclassmembers public class * extends android.view.View {
    void set*(***);
    *** get*();
}

# Keep all classes with Flutter or plugin references
-keep class **.flutter.** { *; }
-keep class **.FlutterPlugin { *; }
-keep class **.MethodChannel { *; }
-keep class **.MethodChannel$MethodCallHandler { *; }
-keep class **.MethodChannel$Result { *; }

# RevenueCat / Purchases
-keep class com.revenuecat.purchases.** { *; }

# Health package
-keep class com.google.android.gms.fitness.** { *; }
-keep class com.google.android.gms.auth.** { *; }

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.signin.** { *; }

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Pedometer and sensor handling
-keep class com.ruck.app.PedometerStreamHandler { *; }
-keep class com.ruck.app.PedometerStreamHandler$* { *; }

# Location tracking service
-keep class com.ruck.app.LocationTrackingService { *; }
-keep class com.ruck.app.LocationTrackingService$* { *; }

# File sharing receivers
-keep class com.ruck.app.FileShareReceiver { *; }
-keep class com.ruck.app.BootReceiver { *; }
-keep class com.ruck.app.SessionHeartbeatReceiver { *; }

# Keep all app-specific classes
-keep class com.ruck.app.** { *; }

# Sensors Plus plugin
-keep class dev.fluttercommunity.plus.sensors.** { *; }

# FFmpeg Kit Flutter - CRITICAL for preventing splash screen freeze
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.mobileffmpeg.** { *; }
-keep class com.arthenica.smartexception.** { *; }

# FFmpeg native libraries and JNI - CRITICAL
-keep class ffmpegkit.** { *; }
-keep class mobileffmpeg.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Prevent stripping of FFmpeg JNI methods
-keepclasseswithmembers class * {
    @com.arthenica.ffmpegkit.* <methods>;
}

# Keep FFmpeg plugin initialization
-keep class io.flutter.plugins.ffmpegkitflutter.** { *; }
-keep class com.arthenica.ffmpegkit.flutter.** { *; }

# Image compression
-keep class com.fluttercandies.flutter_image_compress.** { *; }

# Additional networking libraries
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class retrofit2.** { *; }
-keep interface retrofit2.** { *; }

# Glide (used by some image loading libraries)
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
 <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}

# Prevent stripping of annotations
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator CREATOR;
}

# Keep Serializable implementations
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Geolocator plugin
-keep class com.baseflow.geolocator.** { *; }

# Location plugin
-keep class com.lyokone.location.** { *; }

# Health Connect / Google Fit
-keep class androidx.health.** { *; }
-keep class com.google.android.gms.fitness.** { *; }
-keep class com.google.android.gms.auth.** { *; }

# Keep custom exceptions
-keep public class * extends java.lang.Exception

# Prevent obfuscation of model classes (adjust package name as needed)
-keep class com.ruck.app.models.** { *; }
-keep class com.ruck.app.data.** { *; }