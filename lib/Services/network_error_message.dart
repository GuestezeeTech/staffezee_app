/// User-facing messages for network / load failures (no raw debug text in UI).
class NetworkErrorMessage {
  NetworkErrorMessage._();

  static const String connectionLost =
      'Connection lost. Please check your internet and try again.';

  static const String tasksLoadFailed =
      'Unable to load tasks. Please try again.';

  static const String taskDetailsLoadFailed =
      'Unable to load task details. Please try again.';

  static bool isConnectionError(Object error) {
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('NetworkException') ||
        text.contains('Failed host lookup') ||
        text.contains('No address associated');
  }

  static String forTaskLoad(Object error) {
    if (isConnectionError(error)) return connectionLost;
    return tasksLoadFailed;
  }

  static String forTaskDetails(Object error) {
    if (isConnectionError(error)) return connectionLost;
    return taskDetailsLoadFailed;
  }
}
