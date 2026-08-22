import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> init() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted push notification permission');
      
      try {
        final token = await _fcm.getToken();
        if (token != null) {
          debugPrint('FCM Token: $token');
          await _saveTokenToDatabase(token);
        }

        _fcm.onTokenRefresh.listen(_saveTokenToDatabase);
      } catch (e) {
        debugPrint('Failed to get FCM token: $e');
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        if (message.notification != null) {
          debugPrint('Message also contained a notification: ${message.notification?.title}');
        }
      });
    } else {
      debugPrint('User declined push notification permission');
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final wantsPush = prefs.getBool('instructor_push_notifications') ?? true;
    
    if (!wantsPush) {
       debugPrint('Push notifications disabled locally, not saving token.');
       return;
    }

    try {
      await _supabase.from('user_info').update({'fcm_token': token}).eq('id', user.id);
      debugPrint('FCM Token successfully saved to Supabase for user ${user.id}');
    } catch (e) {
      debugPrint('Failed to save FCM token to Supabase: $e');
    }
  }
}
