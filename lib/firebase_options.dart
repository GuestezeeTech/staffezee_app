import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // if (kIsWeb) {
    //   throw UnsupportedError('Web FirebaseOptions not configured.');
    // }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      // throw UnsupportedError('iOS FirebaseOptions not configured.');
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError('Desktop FirebaseOptions not configured.');
      default:
        throw UnsupportedError('Unknown platform for Firebase initialization');
    }
  }

  // static const FirebaseOptions android = FirebaseOptions(
  //   apiKey: 'AIzaSyDQpxqONFpkcBZTsALez85Jo1n-m5aTrMU',
  //   appId: '1:563382026704:android:fb9952831a272bab14b9d5',
  //   messagingSenderId: '563382026704',
  //   projectId: 'labes-common-app-a2fa5',
  //   storageBucket: 'labes-common-app-a2fa5.appspot.com',
  // );
  // static const FirebaseOptions ios = FirebaseOptions(
  //   apiKey: 'AIzaSyBh8B1AC8Dw9N1qbk-t8FgZG7xYRjibjAw',
  //   appId: '1:563382026704:ios:45b80741eca034a614b9d5',
  //   messagingSenderId: '563382026704',
  //   projectId: 'labes-common-app-a2fa5',
  //   storageBucket: 'labes-common-app-a2fa5.appspot.com',
  // );
  // static const FirebaseOptions web = FirebaseOptions(
  //   apiKey: 'AIzaSyDQpxqONFpkcBZTsALez85Jo1n-m5aTrMU',
  //   appId: '1:563382026704:android:fb9952831a272bab14b9d5',
  //   messagingSenderId: '563382026704',
  //   projectId: 'labes-common-app-a2fa5',
  //   storageBucket: 'labes-common-app-a2fa5.appspot.com',
  //   measurementId: 'G-FVT7XXJZ1K',
  // );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCxpF6fFUrntXtkKwkjIW8hLana-UVvih4',
    appId: '1:945771911357:android:bd81263d8355f20c773fd4',
    messagingSenderId: '945771911357',
    projectId: 'hospitalitynewsapp-f7968',
    storageBucket: 'hospitalitynewsapp-f7968.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD7VTImJvZaNcz72UEw1NN9kGukphNLeCs',
    appId: '1:945771911357:ios:f712455b48e3705d773fd4',
    messagingSenderId: '945771911357',
    projectId: 'hospitalitynewsapp-f7968',
    storageBucket: 'hospitalitynewsapp-f7968.firebasestorage.app',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCxpF6fFUrntXtkKwkjIW8hLana-UVvih4',
    appId: '1:945771911357:android:bd81263d8355f20c773fd4',
    messagingSenderId: '945771911357',
    projectId: 'hospitalitynewsapp-f7968',
    storageBucket: 'hospitalitynewsapp-f7968.firebasestorage.app',
  );
}
