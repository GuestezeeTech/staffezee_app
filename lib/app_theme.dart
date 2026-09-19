import 'package:flutter/material.dart';

class AppTheme {
  static final ColorScheme colorScheme = ColorScheme.fromSeed(
      surface: const Color.fromARGB(255, 242, 242, 237),
      onSurface: const Color.fromARGB(255, 21, 21, 21),
      primary: const Color(0xff800020),
      secondary: const Color(0xffCFB67A),
      seedColor: const Color.fromRGBO(37, 11, 67, 1),
      onPrimary: const Color.fromARGB(255, 255, 255, 255),
      onPrimaryFixed: Colors.blue);

  static ThemeData appTheme = ThemeData(
      fontFamily: 'Poppins',
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.light,
      appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 22.0,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.white)),
      // scaffoldBackgroundColor: colorScheme.surface,
      primaryColor: colorScheme.secondary,
      primaryColorDark: colorScheme.primary,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)))));

  static const TextStyle extraLightText = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.white,
    fontWeight: FontWeight.w200,
  );
}
