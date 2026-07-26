import 'package:flutter_test/flutter_test.dart';
import 'package:tinytrack_app/services/prediction_service.dart';

void main() {
  group('PredictionService.predictNextFromEvents', () {
    test('returns null with too little history', () {
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
      ];
      expect(PredictionService.predictNextFromEvents(events), isNull);
    });

    test('predicts last event + median gap for regular feedings', () {
      // Every 3 hours during the day.
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p, isNotNull);
      expect(p!.typicalGap, const Duration(hours: 3));
      expect(p.expectedAt, DateTime(2026, 6, 9, 23));
      expect(p.confidence, greaterThan(0.5));
    });

    test('ignores double-log gaps shorter than minGap', () {
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 8, 5), // accidental double log
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p!.typicalGap.inMinutes, closeTo(180, 6));
    });

    test('irregular gaps lower confidence vs regular gaps', () {
      final regular = PredictionService.predictNextFromEvents([
        for (var i = 0; i < 6; i++) DateTime(2026, 6, 9, 8 + i * 2),
      ])!;
      final irregular = PredictionService.predictNextFromEvents([
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 8, 40),
        DateTime(2026, 6, 9, 13),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 20),
        DateTime(2026, 6, 9, 21),
      ])!;
      expect(regular.confidence, greaterThan(irregular.confidence));
    });

    test('unsorted input is handled', () {
      final events = [
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 20),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 11),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p!.expectedAt, DateTime(2026, 6, 9, 23));
    });

    test('rolls a long-passed prediction forward to the next future slot', () {
      // Every 3h. Raw prediction would be 23:00, but it's already 01:30 the
      // next morning — two slots have gone by. It should advance, not stick.
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      final p = PredictionService.predictNextFromEvents(
        events,
        now: DateTime(2026, 6, 10, 1, 30),
      );
      // 23:00 -> 02:00 (23:00 and 02:00 are the slots; 23:00 is >1.5h past).
      expect(p!.expectedAt, DateTime(2026, 6, 10, 2));
      expect(p.isOverdue(DateTime(2026, 6, 10, 1, 30)), isFalse);
    });

    test('a just-due prediction stays put (within grace, shows around now)', () {
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      // 10 min past the 23:00 slot — still "around now", don't skip it.
      final p = PredictionService.predictNextFromEvents(
        events,
        now: DateTime(2026, 6, 9, 23, 10),
      );
      expect(p!.expectedAt, DateTime(2026, 6, 9, 23));
      expect(p.isOverdue(DateTime(2026, 6, 9, 23, 10)), isTrue);
    });
  });

  group('PredictionService.predictNextNap', () {
    test('predicts next nap from awake windows', () {
      final sessions = [
        (start: DateTime(2026, 6, 9, 9), end: DateTime(2026, 6, 9, 10)),
        (start: DateTime(2026, 6, 9, 12), end: DateTime(2026, 6, 9, 13)),
        (start: DateTime(2026, 6, 9, 15), end: DateTime(2026, 6, 9, 16, 30)),
      ];
      // Awake windows: 2h and 2h → next nap 2h after last wake (16:30).
      final p = PredictionService.predictNextNap(sessions);
      expect(p, isNotNull);
      expect(p!.expectedAt, DateTime(2026, 6, 9, 18, 30));
    });

    test('returns null with too few sessions', () {
      final sessions = [
        (start: DateTime(2026, 6, 9, 9), end: DateTime(2026, 6, 9, 10)),
        (start: DateTime(2026, 6, 9, 12), end: DateTime(2026, 6, 9, 13)),
      ];
      expect(PredictionService.predictNextNap(sessions), isNull);
    });

    test('overdue detection works', () {
      final p = NextEventPrediction(
        expectedAt: DateTime(2026, 6, 9, 12),
        typicalGap: const Duration(hours: 3),
        sampleSize: 5,
        confidence: 0.8,
      );
      expect(p.isOverdue(DateTime(2026, 6, 9, 13)), isTrue);
      expect(p.isOverdue(DateTime(2026, 6, 9, 11)), isFalse);
      expect(p.timeUntil(DateTime(2026, 6, 9, 11)), const Duration(hours: 1));
    });
  });

  group('PredictionService.predictNextDose', () {
    test('as-needed meds return null (no schedule)', () {
      final p = PredictionService.predictNextDose(
        name: 'Calpol',
        asNeeded: true,
        recentDoses: const [],
        now: DateTime(2026, 6, 9, 12),
      );
      expect(p, isNull);
    });

    test('no schedule info returns null', () {
      final p = PredictionService.predictNextDose(
        name: 'Vitamins',
        recentDoses: const [],
        now: DateTime(2026, 6, 9, 12),
      );
      expect(p, isNull);
    });

    test('never-dosed scheduled med is due now', () {
      final now = DateTime(2026, 6, 9, 12);
      final p = PredictionService.predictNextDose(
        name: 'Amoxicillin',
        minIntervalHours: 8,
        frequencyPerDay: 3,
        recentDoses: const [],
        now: now,
      );
      expect(p, isNotNull);
      expect(p!.dueAt, now);
      expect(p.dosesGivenToday, 0);
      expect(p.isOverdue(now.add(const Duration(minutes: 1))), isTrue);
    });

    test('next dose is last dose + min interval', () {
      final now = DateTime(2026, 6, 9, 14);
      final p = PredictionService.predictNextDose(
        name: 'Amoxicillin',
        minIntervalHours: 8,
        frequencyPerDay: 3,
        recentDoses: [DateTime(2026, 6, 9, 8)],
        now: now,
      );
      expect(p, isNotNull);
      expect(p!.dueAt, DateTime(2026, 6, 9, 16));
      expect(p.dosesGivenToday, 1);
      expect(p.confidence, 0.9);
    });

    test('daily cap reached returns null', () {
      final now = DateTime(2026, 6, 9, 20);
      final p = PredictionService.predictNextDose(
        name: 'Amoxicillin',
        minIntervalHours: 8,
        frequencyPerDay: 3,
        recentDoses: [
          DateTime(2026, 6, 9, 8),
          DateTime(2026, 6, 9, 14),
          DateTime(2026, 6, 9, 20),
        ],
        now: now,
      );
      expect(p, isNull);
    });

    test('frequency-only med spreads across a 12h waking day', () {
      final now = DateTime(2026, 6, 9, 10);
      final p = PredictionService.predictNextDose(
        name: 'Iron drops',
        frequencyPerDay: 2,
        recentDoses: [DateTime(2026, 6, 9, 8)],
        now: now,
      );
      expect(p, isNotNull);
      // 12h / 2 = 6h interval.
      expect(p!.dueAt, DateTime(2026, 6, 9, 14));
      expect(p.confidence, 0.6);
    });
  });
}
