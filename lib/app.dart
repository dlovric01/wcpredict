import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class WcPredictApp extends StatelessWidget {
  const WcPredictApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WC2026 Predict',
      theme: wcpredictTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
