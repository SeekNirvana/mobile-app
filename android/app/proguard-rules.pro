# Keep SDK classes
-keep class com.lm.sdk.** { *; }
-keep class com.zhy.http.okhttp.** { *; }
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-keep class rx.** { *; }

# Keep RingPlugin
-keep class com.seeknirvana.app.RingPlugin { *; }

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep GreenDAO
-keep class org.greenrobot.greendao.** { *; }
-keep class net.sqlcipher.** { *; }

# Don't warn about missing classes from SDK
-dontwarn com.zhy.http.okhttp.**
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-dontwarn rx.**
-dontwarn com.lm.sdk.library.http.**
-dontwarn com.google.android.play.core.**
-dontwarn net.sqlcipher.**
