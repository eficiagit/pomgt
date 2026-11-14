/// An expected action restriction with a message safe to show to the user.
class ActionException implements Exception {
  const ActionException(this.message);

  final String message;

  @override
  String toString() => message;
}
