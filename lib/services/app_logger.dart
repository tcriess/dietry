import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:dietry/app_config.dart';

/// Global logger instance configured with log level from AppConfig.
/// Use this instead of print() for all logging throughout the app.
late final Logger appLogger;

/// Initialize the app logger with the configured log level.
/// Must be called early in main() before other services are initialized.
void initializeAppLogger() {
  final logLevelStr = AppConfig.logLevel.toUpperCase();
  final logLevel = _parseLogLevel(logLevelStr);

  appLogger = Logger(
    level: logLevel,
    filter: ProductionFilter(),
    printer: SimplePrinter(
      colors: kDebugMode,
    ),
  );
}

/// Convert log level string to Logger.LogLevel enum.
Level _parseLogLevel(String level) {
  return switch (level) {
    'TRACE' => Level.trace,
    'DEBUG' => Level.debug,
    'INFO' => Level.info,
    'WARNING' => Level.warning,
    'ERROR' => Level.error,
    'FATAL' => Level.fatal,
    _ => Level.info,
  };
}

/// Filter that only logs in debug mode, except for critical logs (errors, fatals).
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // Always log errors and fatal in all modes
    if (event.level == Level.error || event.level == Level.fatal) {
      return true;
    }
    // Only log other levels in debug mode
    return kDebugMode;
  }
}

/// Simplified printer that is more readable for this project.
class SimplePrinter extends LogPrinter {
  final bool colors;

  SimplePrinter({required this.colors});

  @override
  List<String> log(LogEvent event) {
    final color = _getLevelColor(event.level);
    final levelStr = event.level.name.toUpperCase().padRight(5);
    final prefix = colors ? '$color[$levelStr]\u001b[0m' : '[$levelStr]';

    final lines = <String>[
      '$prefix ${event.message}',
    ];

    if (event.error != null) {
      lines.add('Error: ${event.error}');
    }

    if (event.stackTrace != null && kDebugMode) {
      lines.add(event.stackTrace.toString());
    }

    return lines;
  }

  String _getLevelColor(Level level) {
    // ignore: deprecated_member_use
    return switch (level) {
      Level.all => '\u001b[37m', // White
      Level.trace => '\u001b[35m', // Magenta
      // ignore: deprecated_member_use
      Level.verbose => '\u001b[34m', // Blue
      Level.debug => '\u001b[36m', // Cyan
      Level.info => '\u001b[32m', // Green
      Level.warning => '\u001b[33m', // Yellow
      Level.error => '\u001b[31m', // Red
      Level.fatal => '\u001b[41m', // Red background
      // ignore: deprecated_member_use
      Level.wtf => '\u001b[41m', // Red background
      Level.off => '\u001b[37m', // White
      // ignore: deprecated_member_use
      Level.nothing => '\u001b[37m', // White
    };
  }
}
