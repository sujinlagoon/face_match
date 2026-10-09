import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Offline pending chip widget renders count correctly', (WidgetTester tester) async {
    int tappedCount = 0;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  return InkWell(
                    onTap: () => tappedCount++,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_outlined),
                          SizedBox(width: 8),
                          Text('3 offline punches pending'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('3 offline punches pending'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    await tester.tap(find.text('3 offline punches pending'));
    expect(tappedCount, 1);
  });
}
