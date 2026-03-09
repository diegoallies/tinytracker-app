import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../config/env.dart';
import 'supabase_service.dart';

class AiService {
  static Future<String?> _callGroq(String prompt, {int? maxTokens}) async {
    final models = [AppConstants.primaryModel, AppConstants.fallbackModel];

    for (final model in models) {
      try {
        final response = await http.post(
          Uri.parse(AppConstants.groqApiUrl),
          headers: {
            'Authorization': 'Bearer ${Env.groqApiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': maxTokens ?? AppConstants.maxAiTokens,
            'temperature': 0.7,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['choices'][0]['message']['content'] as String?;
        }
        if (response.statusCode == 429) continue; // rate limited, try fallback
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  // Check cache first, then call AI
  static Future<String?> _getCachedOrGenerate({
    required String babyId,
    required String cacheKey,
    required String Function() promptBuilder,
    int? maxTokens,
  }) async {
    final client = SupabaseService.client;
    final now = DateTime.now();
    final period = now.hour < 18 ? 'am' : 'pm';
    final cachedDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-$period';
    final fullCacheKey = '$cacheKey-$cachedDate';

    // Check cache
    try {
      final cached = await client
          .from('ai_cache')
          .select('response')
          .eq('baby_id', babyId)
          .eq('cache_key', fullCacheKey)
          .maybeSingle();

      if (cached != null && cached['response'] != null) {
        final response = cached['response'];
        if (response is String) return response;
        return jsonEncode(response);
      }
    } catch (_) {}

    // Generate
    final result = await _callGroq(promptBuilder(), maxTokens: maxTokens);
    if (result == null) return null;

    // Store in cache
    try {
      await client.from('ai_cache').upsert({
        'baby_id': babyId,
        'cache_key': fullCacheKey,
        'ai_type': cacheKey,
        'response': result,
        'cached_date': cachedDate,
        'created_at': now.toIso8601String(),
      });
    } catch (_) {}

    return result;
  }

  static Future<List<String>> getInsights({
    required String babyId,
    required String babyName,
    required String gender,
    required Map<String, dynamic> weekData,
  }) async {
    final result = await _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'insights',
      promptBuilder: () =>
          'Here is a baby named $babyName\'s (gender: $gender) complete tracking data for the past week: ${jsonEncode(weekData)}. Generate 3 interesting, actionable insights about $babyName\'s patterns. Examples: sleep trends, feeding preferences, growth observations. Keep each insight to 1 sentence. Be warm and helpful. IMPORTANT: Use simple, mom-friendly language. For times use formats like "1:00 AM" or "around 3 PM". NEVER use ISO timestamps, timezone offsets, or computer date formats. Do not use dashes longer than a hyphen. Return ONLY a JSON array of 3 strings, no other text.',
    );

    if (result == null) return [];

    try {
      final parsed = jsonDecode(result);
      if (parsed is List) return parsed.map((e) => e.toString()).take(3).toList();
    } catch (_) {}

    // Fallback: split by newlines
    return result
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim())
        .where((l) => l.length > 10)
        .take(3)
        .toList();
  }

  static Future<String?> getDailySummary({
    required String babyId,
    required String babyName,
    required String gender,
    required Map<String, dynamic> todayData,
    required Map<String, dynamic> yesterdayData,
  }) async {
    return _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'daily-summary',
      promptBuilder: () =>
          'Here is a baby boy named $babyName\'s (gender: $gender) complete data for today: ${jsonEncode(todayData)}. Yesterday\'s data: ${jsonEncode(yesterdayData)}. Generate a friendly, conversational daily summary. Include: total feeds, diapers, sleep hours, comparisons to yesterday, and any notable patterns. Keep it warm and encouraging for new parents. Keep it to 3-4 sentences. IMPORTANT: Use simple, mom-friendly language. For times use formats like "1:00 AM" or "around 3 PM". NEVER use ISO timestamps, timezone offsets, or computer date formats. Always refer to the baby by name instead of saying "the baby". The baby\'s gender is provided in the request - use correct pronouns (he/him for boys, she/her for girls). Do not use dashes longer than a hyphen.',
    );
  }

  static Future<String?> getSleepPrediction({
    required String babyId,
    required String babyName,
    required String gender,
    required List<Map<String, dynamic>> sleepData,
    required String startTime,
  }) async {
    return _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'sleep-predict',
      maxTokens: 200,
      promptBuilder: () =>
          'Here is a baby named $babyName\'s (gender: $gender) sleep data for the past 14 days: ${jsonEncode(sleepData)}. The baby is currently sleeping and started at $startTime. Predict when the baby will likely wake up. Give a short, friendly prediction in 1-2 sentences. IMPORTANT: Use simple, mom-friendly time formats like "1:00 AM" or "around 3 PM" or "in about 2 hours". NEVER use ISO timestamps, timezone offsets, or computer date formats. Always refer to the baby by name instead of saying "the baby". The baby\'s gender is provided in the request - use correct pronouns (he/him for boys, she/her for girls). Do not use dashes longer than a hyphen.',
    );
  }

  static Future<String?> getFeedingAlert({
    required String babyId,
    required String babyName,
    required String gender,
    required List<Map<String, dynamic>> feedingData,
    required String lastFeedTime,
  }) async {
    return _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'feeding-alert',
      maxTokens: 200,
      promptBuilder: () =>
          'Here is a baby named $babyName\'s (gender: $gender) feeding history for 7 days: ${jsonEncode(feedingData)}. Last feed was at $lastFeedTime. Analyze the feeding pattern and tell me: when is the next feed likely? Is the baby overdue? Give a short, friendly alert in 1-2 sentences. IMPORTANT: Use simple, mom-friendly time formats like "1:00 AM" or "around 3 PM" or "in about 2 hours". NEVER use ISO timestamps, timezone offsets, or computer date formats. Always refer to the baby by name instead of saying "the baby". The baby\'s gender is provided in the request - use correct pronouns (he/him for boys, she/her for girls). Do not use dashes longer than a hyphen.',
    );
  }

  static Future<String?> getPoopAnalysis({
    required String babyId,
    required String babyName,
    required String gender,
    required String color,
    required int ageDays,
    String feedingType = 'breastfed',
  }) async {
    return _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'poop-$color',
      maxTokens: 300,
      promptBuilder: () =>
          'A $gender baby named $babyName\'s diaper was $color. The baby is $ageDays days old and is $feedingType. Is this color normal? Should the parent be concerned? Give a short, reassuring medical explanation in 2-3 sentences. Always refer to the baby by name instead of saying "the baby". The baby\'s gender is provided in the request - use correct pronouns (he/him for boys, she/her for girls). Do not use dashes longer than a hyphen.',
    );
  }

  static Future<String?> getGrowthAnalysis({
    required String babyId,
    required String babyName,
    required String gender,
    required int ageDays,
    double? weightKg,
    double? heightCm,
    double? headCm,
    Map<String, double>? percentiles,
    Map<String, dynamic>? previousMeasurement,
  }) async {
    return _getCachedOrGenerate(
      babyId: babyId,
      cacheKey: 'growth-$weightKg-$heightCm-$headCm',
      maxTokens: 300,
      promptBuilder: () =>
          'A $ageDays-day-old $gender named $babyName weighs ${weightKg ?? "unknown"}kg, is ${heightCm ?? "unknown"}cm long, head circumference ${headCm ?? "unknown"}cm. WHO percentiles: weight ${percentiles?['weight'] ?? "unknown"}th, height ${percentiles?['height'] ?? "unknown"}th, head ${percentiles?['head'] ?? "unknown"}th. Previous measurement was ${previousMeasurement != null ? jsonEncode(previousMeasurement) : "not available"}. Analyze this growth data. Is the baby growing well? Any concerns? Keep response short and friendly, 2-3 sentences. Always refer to the baby by name instead of saying "the baby". Do not use dashes longer than a hyphen.',
    );
  }
}
