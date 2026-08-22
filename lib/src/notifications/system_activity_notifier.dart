import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';

/// System notifications via flutter_local_notifications.
class SystemActivityNotifier implements ActivityNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> notify({required String title, required String body}) async {
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'tmux_activity',
          'tmux activity',
          channelDescription:
              'Pane/window activity in the connected tmux session',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}
