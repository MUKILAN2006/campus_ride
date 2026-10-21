import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_ride_flutter/main.dart';

void main() {
  testWidgets('CampusRide App loads splash screen test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const CampusRideApp());

    // Verify that CampusRide text is displayed on Splash Screen
    expect(find.text('CampusRide'), findsOneWidget);

    // Pump timer to navigate to login screen
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
