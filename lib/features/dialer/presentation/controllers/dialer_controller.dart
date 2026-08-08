import 'package:flutter/foundation.dart';

/// Holds the number currently typed into the dialer.
///
/// A plain [ChangeNotifier] (not a Riverpod provider) because its lifetime
/// is scoped to one `DeviceDetailPage` instance, not the whole app — it's
/// created and disposed there and handed down to [DialerPage] and, when a
/// favorite is tapped, written to directly from `FavoritesPage`'s callback.
class DialerController extends ChangeNotifier {
  String _number = '';

  String get number => _number;

  void setNumber(String number) {
    _number = number;
    notifyListeners();
  }

  /// Appends one key press (a digit, `*` or `#`) to the current number.
  void append(String value) => setNumber('$_number$value');

  /// Removes the last character, e.g. from the backspace button. No-op on an
  /// empty number.
  void deleteLast() {
    if (_number.isEmpty) return;
    setNumber(_number.substring(0, _number.length - 1));
  }
}
