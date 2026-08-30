import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Android suppresses the system-tray notification while the app is in the
/// foreground and hands the message to the app instead. Nothing draws it unless
/// we do — so every alert that arrived while a dean or instructor had iEvaluate
/// open was silently dropped. `onMessage` used to only debugPrint. This channel
/// is what we now draw into.
///
/// The same id is declared in AndroidManifest.xml as
/// `com.google.firebase.messaging.default_notification_channel_id` so the
/// notifications Android renders on its own (app backgrounded or closed) land
/// on this channel too. Two channels would let a user mute one and still be
/// pinged by the other.
const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
  'ievaluate_alerts',
  'iEvaluate alerts',
  description:
      'Low evaluation scores, critical student feedback and result updates.',
  importance: Importance.high,
);

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // init() is called from MainScaffold.initState and DataGathererScreen, and
  // initState runs again every time the scaffold is rebuilt. Without these
  // guards each rebuild attached another onMessage listener, so the user would
  // get one duplicate banner per rebuild.
  static bool _localReady = false;
  static bool _listenersBound = false;

  /// Android requires a 32-bit int id. A counter keeps successive alerts
  /// stacked in the tray instead of each one replacing the previous.
  static int _nextId = 0;

  /// Registers the notification channel and initialises the local-notification
  /// plugin. Idempotent.
  ///
  /// Called from `main()` and not only from [init]: a notification addressed to
  /// a channel that does not exist yet is silently discarded by Android 8+, so
  /// the channel has to be registered at cold start — before any push can
  /// arrive — rather than after a successful login.
  static Future<void> setupLocalNotifications() async {
    if (_localReady) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      // Permission is requested by firebase_messaging in init() instead, and on
      // iOS we never draw these ourselves (see the iOS branch in init()), so
      // asking again here would show the user a second, redundant prompt.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(alertChannel);

    _localReady = true;
  }

  /// The app is already open when a foreground notification is tapped, so there
  /// is nothing to launch. Routing the user to the instructor or department the
  /// alert is about is NOT implemented — the six FCM senders in the n8n
  /// workflow post only a `notification` block with no `data`, so there is no
  /// target id to navigate to. Adding one requires changing the senders first.
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped. payload=${response.payload}');
  }

  Future<void> init() async {
    // Cheap and idempotent; covers the gatherer path if it ever starts up
    // without main()'s call having run.
    await setupLocalNotifications();

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('User declined push notification permission');
      return;
    }

    debugPrint('User granted push notification permission');

    // iOS does display foreground pushes itself, but only once asked to. Doing
    // it this way rather than drawing a local notification avoids the duplicate
    // banner that showing both would produce.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        await _saveTokenToDatabase(token);
      }

      if (!_listenersBound) {
        _fcm.onTokenRefresh.listen(_saveTokenToDatabase);
      }
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }

    if (!_listenersBound) {
      FirebaseMessaging.onMessage.listen(_showForeground);
      _listenersBound = true;
    }
  }

  /// Draws an incoming push while the app is in the foreground.
  ///
  /// Android only: iOS is handled by
  /// `setForegroundNotificationPresentationOptions` above, and drawing here as
  /// well would show the alert twice.
  static Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      // Data-only message. None of the current senders produce these, but if
      // one is added later it has no title or body to render.
      debugPrint('Foreground data-only message: ${message.data}');
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;

    await setupLocalNotifications();

    await _local.show(
      id: _nextId++,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          alertChannel.id,
          alertChannel.name,
          channelDescription: alertChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          // The alert bodies are one sentence today but the sentiment ones are
          // the most likely to grow; BigText stops them being truncated.
          styleInformation: BigTextStyleInformation(notification.body ?? ''),
        ),
      ),
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
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
      await _supabase
          .from('user_info')
          .update({'fcm_token': token})
          .eq('id', user.id);
      debugPrint('FCM Token successfully saved to Supabase for user ${user.id}');
    } catch (e) {
      debugPrint('Failed to save FCM token to Supabase: $e');
    }
  }
}
