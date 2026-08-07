import 'package:flutter/foundation.dart';

class DialerController extends ChangeNotifier {
  String _number = '';

  String get number => _number;

  void setNumber(String number) {
    _number = number;
    notifyListeners();
  }

  void append(String value) => setNumber('$_number$value');

  void deleteLast() {
    if (_number.isEmpty) return;
    setNumber(_number.substring(0, _number.length - 1));
  }
}
