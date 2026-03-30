// Plattform-Utilities für Web und Native
import 'package:flutter/foundation.dart' show kIsWeb;

// Für Native Plattformen
import 'dart:io' if (dart.library.html) 'platform_web.dart';

bool isLinux() => !kIsWeb && Platform.isLinux;
bool isWindows() => !kIsWeb && Platform.isWindows;
bool isAndroid() => !kIsWeb && Platform.isAndroid;
bool isIOS() => !kIsWeb && Platform.isIOS;
bool isMacOS() => !kIsWeb && Platform.isMacOS;

bool isDesktop() => isLinux() || isWindows() || isMacOS();
bool isMobile() => isAndroid() || isIOS();

