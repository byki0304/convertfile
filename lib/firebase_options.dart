import 'package:firebase_core/firebase_core.dart';

/// Public Firebase web configuration only. Server keys never belong here.
class DefaultFirebaseOptions {
  static const projectId = 'convertfile-9b293';
  static const region = 'asia-northeast3';
  static const databaseId = 'convertfile';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCGSFCEaSS9PHo0sGn6zYDbEuWDflOk_VA',
    authDomain: 'convertfile-9b293.firebaseapp.com',
    projectId: projectId,
    storageBucket: 'convertfile-9b293.firebasestorage.app',
    messagingSenderId: '557200943471',
    appId: '1:557200943471:web:9620a75bf9aa893e31a09a',
  );

  static FirebaseOptions get currentPlatform => web;
}
