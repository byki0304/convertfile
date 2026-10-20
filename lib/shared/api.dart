import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../firebase_options.dart';
import 'file_rules.dart';
import 'web/bridge.dart';

class ApiException implements Exception {
  const ApiException(this.code);

  final String code;

  @override
  String toString() => 'ApiException($code)';
}

class Api {
  Api._();

  static FirebaseFirestore get db => FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: DefaultFirebaseOptions.databaseId);

  static FirebaseFunctions get functions => FirebaseFunctions.instanceFor(region: DefaultFirebaseOptions.region);

  static FirebaseStorage get storage => FirebaseStorage.instance;

  /// Calls a Cloud Function and maps server errors to app error codes.
  static Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> data = const {}]) async {
    try {
      final r = await functions.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 180))).call(data);
      final v = r.data;
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final code = d is Map && d['code'] is String ? d['code'] as String : (e.message ?? 'engine-failed');
      throw ApiException(code);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw const ApiException('network');
    }
  }

  /// Resumable upload of the browser File (not read into memory). Emits progress 0~100 and completes with the path.
  static UploadTask upload(String uid, PickedFile file) {
    final safe = file.name.replaceAll(RegExp(r'[/\\#?\[\]*]'), '_');
    final path = 'uploads/$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    final type = uploadContentTypes[file.ext] ?? 'application/octet-stream';
    return storage.ref(path).putBlob(file.blob, SettableMetadata(contentType: type));
  }

  static CollectionReference<Map<String, dynamic>> conversions(String uid) => db.collection('users/$uid/conversions');

  static CollectionReference<Map<String, dynamic>> turns(String uid) => db.collection('users/$uid/turns');

  static DocumentReference<Map<String, dynamic>> usage(String uid, String day) => db.doc('users/$uid/usage/$day');
}

/// yyyyMMdd in Asia/Seoul (UTC+9, no DST).
String seoulDay(DateTime now) {
  final k = now.toUtc().add(const Duration(hours: 9));
  return '${k.year}${k.month.toString().padLeft(2, '0')}${k.day.toString().padLeft(2, '0')}';
}

/// Firestore timestamps, or epoch milliseconds as returned by readBackup.
DateTime? _ts(Object? v) => switch (v) {
  Timestamp t => t.toDate(),
  num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
  _ => null,
};

class Conversion {
  Conversion(this.id, Map<String, dynamic> d)
    : sourceName = d['sourceName'] as String? ?? '',
      sourceExt = d['sourceExt'] as String? ?? '',
      sourceSize = (d['sourceSize'] as num?)?.toInt() ?? 0,
      target = TargetFormat.fromExt(d['targetFormat'] as String?) ?? TargetFormat.pdf,
      mode = d['mode'] as String? ?? 'content',
      status = d['status'] as String? ?? 'queued',
      errorCode = d['errorCode'] as String?,
      outputName = d['outputName'] as String?,
      outputSize = (d['outputSize'] as num?)?.toInt(),
      pageCount = (d['pageCount'] as num?)?.toInt(),
      summaryLines = (d['summaryLines'] as List?)?.cast<String>() ?? const [],
      fontSubstituted = d['fontSubstituted'] == true,
      createdAt = _ts(d['createdAt']),
      expireAt = _ts(d['expireAt']);

  final String id;
  final String sourceName;
  final String sourceExt;
  final int sourceSize;
  final TargetFormat target;
  final String mode;
  final String status;
  final String? errorCode;
  final String? outputName;
  final int? outputSize;
  final int? pageCount;
  final List<String> summaryLines;
  final bool fontSubstituted;
  final DateTime? createdAt;
  final DateTime? expireAt;

  bool get isDone => status == 'done' && (outputSize ?? 0) > 0;
  bool get isRunning => status == 'running';
  bool expiredAt(DateTime now) => expireAt != null && !expireAt!.isAfter(now);
  int hoursLeft(DateTime now) => expireAt == null ? 0 : (expireAt!.difference(now).inMinutes / 60).ceil().clamp(0, Limits.retentionHours);
}

class Turn {
  Turn(this.id, Map<String, dynamic> d)
    : userText = d['userText'] as String? ?? '',
      aiText = d['aiText'] as String? ?? '',
      isVoice = d['isVoice'] == true,
      fileName = d['fileName'] as String?,
      filePath = d['filePath'] as String?,
      targetMenu = d['targetMenu'] as String? ?? 'general',
      routeCard = d['routeCard'] is Map ? Map<String, dynamic>.from(d['routeCard'] as Map) : null,
      summaryLines = (d['summaryLines'] as List?)?.cast<String>() ?? const [],
      sources = [
        for (final s in (d['sources'] as List? ?? const []))
          if (s is Map && s['uri'] is String) (title: (s['title'] as String?) ?? s['uri'] as String, uri: s['uri'] as String),
      ],
      searchQueries = (d['searchQueries'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt = _ts(d['createdAt']),
      expireAt = _ts(d['expireAt']),
      userHidden = d['userHidden'] == true,
      aiHidden = d['aiHidden'] == true;

  final String id;
  final String userText;
  final String aiText;
  final bool isVoice;
  final String? fileName;
  final String? filePath;
  final String targetMenu;
  final Map<String, dynamic>? routeCard;
  final List<String> summaryLines;
  final List<({String title, String uri})> sources;
  final List<String> searchQueries;
  final DateTime? createdAt;
  final DateTime? expireAt;
  final bool userHidden;
  final bool aiHidden;

  bool expiredAt(DateTime now) => expireAt != null && !expireAt!.isAfter(now);
}
