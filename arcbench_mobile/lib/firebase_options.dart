import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this project.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: '1:742378201773:android:d0d6359574685ed7489c24',
    messagingSenderId: '742378201773',
    projectId: 'arcbench-app',
    storageBucket: 'arcbench-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: '1:742378201773:ios:7ab7db168c66367f489c24',
    messagingSenderId: '742378201773',
    projectId: 'arcbench-app',
    storageBucket: 'arcbench-app.firebasestorage.app',
    iosBundleId: 'com.arcbench.arcbenchMobile',
  );
}
