# Keep WebView JavascriptInterface annotations and bridge methods
-keepattributes JavascriptInterface,Annotation,Signature,InnerClasses,EnclosingMethod
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.singwallet.app.MainActivity$AndroidBridge { *; }

# Keep SingWallet native host components, security codecs, SQLite helper, and services
-keep class com.singwallet.app.MainActivity { *; }
-keep class com.singwallet.app.security.** { *; }
-keep class com.singwallet.app.data.** { *; }
-keep class com.singwallet.app.services.** { *; }

# ML Kit Chinese Text Recognition (offline bundled)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
