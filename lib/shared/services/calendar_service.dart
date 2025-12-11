import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';

class CalendarService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [CalendarApi.calendarEventsScope],
  );

  CalendarApi? _calendarApi;

  /// Googleアカウントでサインインし、APIクライアントを初期化
  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false; // ユーザーがキャンセル

      // googleapis_authのクライアントを取得
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) {
        throw Exception('認証クライアントの取得に失敗しました');
      }

      _calendarApi = CalendarApi(httpClient);
      return true;
    } catch (e) {
      print('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// サインアウト
  Future<void> signOut() async {
    await _googleSignIn.disconnect();
    _calendarApi = null;
  }

  /// 連携済みかどうか確認
  Future<bool> isAuthenticated() async {
    return _googleSignIn.currentUser !=
        null; // 簡易チェック (実際はToken有効期限なども考慮が必要だが、SDKが隠蔽してくれる)
  }

  /// イベントを作成
  Future<String?> createEvent({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (_calendarApi == null) {
      final success = await signIn();
      if (!success) {
        // キャンセルの場合はnullを返す（エラーではない）
        return null;
      }
    }

    final event = Event(
      summary: title,
      description: '$description\n\nCreated via Homeppu 🌸',
      start: EventDateTime(
        dateTime: startTime,
        timeZone: "Asia/Tokyo", // ユーザーのローカルに合わせるべきだが一旦固定
      ),
      end: EventDateTime(dateTime: endTime, timeZone: "Asia/Tokyo"),
      reminders: EventReminders(useDefault: true), // デフォルト通知を使用
    );

    try {
      final createdEvent = await _calendarApi!.events.insert(event, "primary");
      return createdEvent.id;
    } catch (e) {
      print('Calendar Insert Error: $e');
      rethrow;
    }
  }

  /// イベントを更新
  Future<bool> updateEvent({
    required String eventId,
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (_calendarApi == null) {
      final success = await signIn();
      if (!success) return false;
    }

    final event = Event(
      summary: title,
      description: '$description\n\nUpdated via Homeppu 🌸',
      start: EventDateTime(dateTime: startTime, timeZone: "Asia/Tokyo"),
      end: EventDateTime(dateTime: endTime, timeZone: "Asia/Tokyo"),
    );

    try {
      await _calendarApi!.events.patch(event, "primary", eventId);
      return true;
    } catch (e) {
      print('Calendar Update Error: $e');
      rethrow;
    }
  }

  /// イベントを削除
  Future<bool> deleteEvent(String eventId) async {
    if (_calendarApi == null) {
      final success = await signIn();
      if (!success) return false;
    }

    try {
      await _calendarApi!.events.delete("primary", eventId);
      return true;
    } catch (e) {
      print('Calendar Delete Error: $e');
      rethrow;
    }
  }
}
