import 'package:dio/dio.dart';
import 'neon_database_service.dart';

enum FeedbackType { bug, feature, general }

extension FeedbackTypeValue on FeedbackType {
  String get value => switch (this) {
        FeedbackType.bug => 'bug',
        FeedbackType.feature => 'feature',
        FeedbackType.general => 'general',
      };
}

class FeedbackService {
  final NeonDatabaseService _db;

  FeedbackService(this._db);

  Future<void> submitFeedback({
    required FeedbackType type,
    required String message,
    int? rating,
    String? appVersion,
    String? userRole,
  }) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token invalid');

    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID available');

    final payload = {
      'user_id': userId,
      'type': type.value,
      'message': message,
      if (rating != null) 'rating': rating,
      if (appVersion != null) 'app_version': appVersion,
      if (userRole != null) 'user_role': userRole,
    };

    final response = await _db.dioClient.post(
      '/feedback',
      data: payload,
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to submit feedback: ${response.statusCode}');
    }
  }
}
