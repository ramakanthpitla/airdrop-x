import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(_Handler());

class _Handler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Android foreground service + Wi-Fi lock + wake lock: keeps sockets alive in background.
class Background {
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.requestNotificationPermission();
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'adx', channelName: 'AirDrop X',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true, allowWifiLock: true),
    );
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
        serviceId: 256, notificationTitle: 'AirDrop X',
        notificationText: 'Ready to receive', callback: startCallback);
  }

  static void notify(String text) {
    if (Platform.isAndroid) FlutterForegroundTask.updateService(notificationText: text);
  }
}
