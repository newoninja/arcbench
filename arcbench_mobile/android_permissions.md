# Android Permissions Setup

After running `flutter create .` in the arcbench_mobile directory, add these to `android/app/src/main/AndroidManifest.xml`:

Inside the `<manifest>` tag (before `<application>`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

Set minimum SDK to 21 in `android/app/build.gradle`:
```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```
