import 'package:flutter/material.dart';

/// Terracotta: a warm, home-like brick/clay tone. The whole color scheme
/// (light and dark) is derived from this one seed.
const Color _seed = Color(0xFFC1623F);

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      // Taller than the default 80 so thumbs have room.
      height: 80,
    ),
    // 48dp is the Material minimum touch target; enforce it on buttons.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
  );
}

/// Light and dark share one builder; MaterialApp picks via ThemeMode.system.
final ThemeData lightTheme = _buildTheme(Brightness.light);
final ThemeData darkTheme = _buildTheme(Brightness.dark);
