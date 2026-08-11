import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';

void main() {
  group('DialerController', () {
    test('starts empty', () {
      final controller = DialerController();

      expect(controller.number, isEmpty);
    });

    test('append adds to the end of the number', () {
      final controller = DialerController();

      controller.append('1');
      controller.append('2');
      controller.append('3');

      expect(controller.number, '123');
    });

    test('deleteLast removes the last character', () {
      final controller = DialerController()..append('12');

      controller.deleteLast();

      expect(controller.number, '1');
    });

    test('deleteLast on an empty number is a no-op', () {
      final controller = DialerController();

      controller.deleteLast();

      expect(controller.number, isEmpty);
    });

    test('setNumber replaces the whole number', () {
      final controller = DialerController()..append('123');

      controller.setNumber('456');

      expect(controller.number, '456');
    });

    test('every mutation notifies listeners', () {
      final controller = DialerController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.append('1');
      controller.deleteLast();
      controller.setNumber('9');

      expect(notifications, 3);
    });
  });
}
