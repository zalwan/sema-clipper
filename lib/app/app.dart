import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/clipper/clipper_page.dart';

class SemaClipperApp extends StatelessWidget {
  const SemaClipperApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SEMA Clipper',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const ClipperPage(),
  );
}
