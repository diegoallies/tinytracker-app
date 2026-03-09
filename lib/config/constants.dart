class AppConstants {
  static const String appName = 'TinyTrack';
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String primaryModel = 'llama-3.3-70b-versatile';
  static const String fallbackModel = 'llama-3.1-8b-instant';
  static const int maxAiTokens = 400;
  static const int photosPerPage = 30;
  static const int recentItemsLimit = 5;
  static const int activityFeedLimit = 15;
  static const int tummyTimeDailyGoalMinutes = 30;
  static const Duration cachePeriod = Duration(hours: 12);
  static const Duration inviteExpiry = Duration(days: 7);
}
