import 'package:flutter_test/flutter_test.dart';
import 'package:tinytrack_app/services/report_math.dart';

// All fixtures use plain local ISO strings (no zone suffix) so the expected
// numbers are deterministic on any machine.
void main() {
  group('parseTimestamp', () {
    test('parses ISO strings and passes through DateTime', () {
      expect(parseTimestamp('2026-06-01T10:30:00'),
          DateTime(2026, 6, 1, 10, 30));
      expect(parseTimestamp(DateTime(2026, 6, 1, 8)),
          DateTime(2026, 6, 1, 8));
    });

    test('returns null for null and garbage', () {
      expect(parseTimestamp(null), isNull);
      expect(parseTimestamp('not a date'), isNull);
    });
  });

  group('dayKey', () {
    test('uses local calendar components, zero-padded', () {
      expect(dayKey(DateTime(2026, 6, 1, 23, 59)), '2026-06-01');
      expect(dayKey(DateTime(2026, 12, 9, 0, 0)), '2026-12-09');
    });
  });

  group('daysBetween', () {
    test('counts calendar days, ignoring time of day', () {
      expect(daysBetween(DateTime(2026, 6, 1, 23), DateTime(2026, 6, 2, 1)),
          1);
      expect(daysBetween(DateTime(2026, 6, 1), DateTime(2026, 6, 1, 18)), 0);
      expect(daysBetween(DateTime(2026, 6, 1), DateTime(2026, 6, 8)), 7);
    });

    test('is negative when the second date is earlier', () {
      expect(daysBetween(DateTime(2026, 6, 8), DateTime(2026, 6, 1)), -7);
    });

    test('crosses month and year boundaries', () {
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 2)), 2);
      expect(
          daysBetween(DateTime(2025, 12, 29), DateTime(2026, 1, 5)), 7);
    });
  });

  group('periodLengthDays', () {
    test('half-open period lengths', () {
      // Week: Mon 1 June .. Mon 8 June (exclusive) = 7 days.
      expect(periodLengthDays(DateTime(2026, 6, 1), DateTime(2026, 6, 8)), 7);
      // Calendar months.
      expect(periodLengthDays(DateTime(2026, 6, 1), DateTime(2026, 7, 1)), 30);
      expect(periodLengthDays(DateTime(2026, 2, 1), DateTime(2026, 3, 1)), 28);
    });

    test('never below 1', () {
      expect(periodLengthDays(DateTime(2026, 6, 1), DateTime(2026, 6, 1)), 1);
    });
  });

  group('divisorDays', () {
    final weekStart = DateTime(2026, 6, 1); // Monday
    final weekEnd = DateTime(2026, 6, 8);

    test('period entirely in the past uses the full length', () {
      expect(
        divisorDays(
          periodStart: weekStart,
          periodEnd: weekEnd,
          now: DateTime(2026, 6, 20),
        ),
        7,
      );
    });

    test('period including today uses elapsed days only', () {
      // "Now" is Wednesday of that week: Mon, Tue, Wed = 3 elapsed days.
      expect(
        divisorDays(
          periodStart: weekStart,
          periodEnd: weekEnd,
          now: DateTime(2026, 6, 3, 14, 30),
        ),
        3,
      );
    });

    test('first day of a live period counts as 1, never 0', () {
      expect(
        divisorDays(
          periodStart: weekStart,
          periodEnd: weekEnd,
          now: DateTime(2026, 6, 1, 0, 5),
        ),
        1,
      );
    });

    test('the moment the period ends it is a full past period', () {
      expect(
        divisorDays(
          periodStart: weekStart,
          periodEnd: weekEnd,
          now: DateTime(2026, 6, 8),
        ),
        7,
      );
    });

    test('past month uses its true length', () {
      expect(
        divisorDays(
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 3, 1),
          now: DateTime(2026, 6, 10),
        ),
        28,
      );
    });
  });

  group('perDay', () {
    test('divides and guards against bad divisors', () {
      expect(perDay(14, 7), 2.0);
      expect(perDay(5, 0), 5.0);
      expect(perDay(0, 7), 0.0);
    });
  });

  group('deltaLabel', () {
    test('zero previous and zero current is "no change"', () {
      expect(deltaLabel(0, 0), 'no change');
    });

    test('zero previous with activity now is "new"', () {
      expect(deltaLabel(2.5, 0), 'new');
    });

    test('signed percentages against the previous rate', () {
      expect(deltaLabel(11, 10), '+10%');
      expect(deltaLabel(9, 10), '-10%');
      expect(deltaLabel(20, 10), '+100%');
      expect(deltaLabel(0, 10), '-100%');
    });

    test('sub-half-percent moves round to "no change"', () {
      expect(deltaLabel(10.04, 10), 'no change');
    });
  });

  group('sessionMinutes', () {
    test('trusts a positive stored duration', () {
      expect(sessionMinutes({'duration_minutes': 95}), 95);
    });

    test('derives from end - start when duration missing or zero', () {
      expect(
        sessionMinutes({
          'duration_minutes': 0,
          'start_time': '2026-06-01T13:00:00',
          'end_time': '2026-06-01T14:30:00',
        }),
        90,
      );
    });

    test('returns 0 for an ongoing session', () {
      expect(sessionMinutes({'start_time': '2026-06-01T13:00:00'}), 0);
    });
  });

  group('bucketing', () {
    final weekStart = DateTime(2026, 6, 1); // Monday
    final monthStart = DateTime(2026, 6, 1);
    final monthEnd = DateTime(2026, 7, 1);

    test('weekly periods always have 7 day buckets', () {
      expect(
        bucketCountFor(
          periodStart: weekStart,
          periodEnd: DateTime(2026, 6, 8),
          isMonthly: false,
        ),
        7,
      );
    });

    test('monthly bucket count covers partial trailing weeks', () {
      // 30 days -> W1..W5; 28 days -> W1..W4.
      expect(
        bucketCountFor(
            periodStart: monthStart, periodEnd: monthEnd, isMonthly: true),
        5,
      );
      expect(
        bucketCountFor(
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 3, 1),
          isMonthly: true,
        ),
        4,
      );
    });

    test('weekly index is the day offset, clamped into 0..6', () {
      expect(
        bucketIndexOf(DateTime(2026, 6, 1, 9),
            periodStart: weekStart, isMonthly: false, bucketCount: 7),
        0,
      );
      expect(
        bucketIndexOf(DateTime(2026, 6, 7, 23, 59),
            periodStart: weekStart, isMonthly: false, bucketCount: 7),
        6,
      );
      // A stray row outside the period cannot escape the chart.
      expect(
        bucketIndexOf(DateTime(2026, 6, 9),
            periodStart: weekStart, isMonthly: false, bucketCount: 7),
        6,
      );
    });

    test('monthly index groups days into weeks of the month', () {
      expect(
        bucketIndexOf(DateTime(2026, 6, 7),
            periodStart: monthStart, isMonthly: true, bucketCount: 5),
        0,
      );
      expect(
        bucketIndexOf(DateTime(2026, 6, 8),
            periodStart: monthStart, isMonthly: true, bucketCount: 5),
        1,
      );
      expect(
        bucketIndexOf(DateTime(2026, 6, 30),
            periodStart: monthStart, isMonthly: true, bucketCount: 5),
        4,
      );
    });

    test('bucketTotals counts rows and applies weights', () {
      final rows = [
        {'logged_at': '2026-06-01T08:00:00', 'amount_ml': 60},
        {'logged_at': '2026-06-01T20:00:00', 'amount_ml': 90},
        {'logged_at': '2026-06-03T08:00:00', 'amount_ml': 120},
        {'logged_at': null}, // unparseable rows are skipped
      ];
      final counts = bucketTotals(
        rows,
        timeField: 'logged_at',
        periodStart: weekStart,
        isMonthly: false,
        bucketCount: 7,
      );
      expect(counts, [2, 0, 1, 0, 0, 0, 0]);

      final ml = bucketTotals(
        rows,
        timeField: 'logged_at',
        periodStart: weekStart,
        isMonthly: false,
        bucketCount: 7,
        weight: (r) => (r['amount_ml'] as num).toDouble(),
      );
      expect(ml, [150, 0, 120, 0, 0, 0, 0]);
    });
  });

  group('FeedingStats', () {
    test('empty period yields zeros and nulls', () {
      final stats = FeedingStats.fromRows(const []);
      expect(stats.total, 0);
      expect(stats.avgMl, isNull);
      expect(stats.avgQuality, isNull);
      expect(stats.spitUpRate, isNull);
      expect(stats.busiestDay, isNull);
      expect(stats.busiestDayCount, 0);
      expect(stats.refusedCount, 0);
    });

    test('avg ml only averages rows that carry an amount', () {
      final stats = FeedingStats.fromRows([
        {'logged_at': '2026-06-01T08:00:00', 'amount_ml': 60},
        {'logged_at': '2026-06-01T11:00:00', 'amount_ml': 120},
        {'logged_at': '2026-06-01T14:00:00'}, // breastfeed, no amount
      ]);
      expect(stats.total, 3);
      expect(stats.avgMl, 90.0); // (60 + 120) / 2, NOT / 3
    });

    test('avg quality only averages rows with quality; counts refusals', () {
      final stats = FeedingStats.fromRows([
        {'logged_at': '2026-06-01T08:00:00', 'quality': 5},
        {'logged_at': '2026-06-01T11:00:00', 'quality': 1},
        {'logged_at': '2026-06-01T14:00:00', 'quality': 3},
        {'logged_at': '2026-06-01T17:00:00'}, // no quality recorded
      ]);
      expect(stats.avgQuality, 3.0); // (5 + 1 + 3) / 3
      expect(stats.qualityKnown, 3);
      expect(stats.refusedCount, 1);
    });

    test('spit-up rate uses only rows where the flag was recorded', () {
      final stats = FeedingStats.fromRows([
        {'logged_at': '2026-06-01T08:00:00', 'had_spitup': true},
        {'logged_at': '2026-06-01T11:00:00', 'had_spitup': false},
        {'logged_at': '2026-06-01T14:00:00', 'had_spitup': false},
        {'logged_at': '2026-06-01T17:00:00'}, // not recorded
      ]);
      expect(stats.spitUpKnown, 3);
      expect(stats.spitUpYes, 1);
      expect(stats.spitUpRate, closeTo(1 / 3, 1e-9));
    });

    test('per-day buckets, busiest day and dayparts', () {
      final stats = FeedingStats.fromRows([
        {'logged_at': '2026-06-01T07:00:00'}, // morning
        {'logged_at': '2026-06-01T13:00:00'}, // afternoon
        {'logged_at': '2026-06-02T02:00:00'}, // night
        {'logged_at': '2026-06-02T19:30:00'}, // evening
        {'logged_at': '2026-06-02T21:00:00'}, // evening
      ]);
      expect(stats.perDayCounts, {'2026-06-01': 2, '2026-06-02': 3});
      expect(stats.busiestDay, '2026-06-02');
      expect(stats.busiestDayCount, 3);
      expect(stats.daypartCounts, {
        'morning': 1,
        'afternoon': 1,
        'night': 1,
        'evening': 2,
      });
    });

    test('busiest day tie goes to the earliest day', () {
      final stats = FeedingStats.fromRows([
        {'logged_at': '2026-06-02T08:00:00'},
        {'logged_at': '2026-06-01T08:00:00'},
      ]);
      expect(stats.busiestDay, '2026-06-01');
    });
  });

  group('SleepStats', () {
    test('empty period yields all zeros', () {
      final stats = SleepStats.fromRows(const []);
      expect(stats.totalMinutes, 0);
      expect(stats.longestMinutes, 0);
      expect(stats.stretchCount, 0);
      expect(stats.nightPct, 0);
      expect(stats.dayPct, 0);
    });

    test('totals, longest stretch and stretch count over completed naps', () {
      final stats = SleepStats.fromRows([
        {
          'start_time': '2026-06-01T09:00:00',
          'end_time': '2026-06-01T10:00:00',
          'duration_minutes': 60,
        },
        {
          'start_time': '2026-06-01T13:00:00',
          'end_time': '2026-06-01T15:30:00',
          'duration_minutes': 150,
        },
        {'start_time': '2026-06-01T20:00:00'}, // ongoing -> excluded
      ]);
      expect(stats.totalMinutes, 210);
      expect(stats.longestMinutes, 150);
      expect(stats.stretchCount, 2);
    });

    test('derives duration from end - start when not stored', () {
      final stats = SleepStats.fromRows([
        {
          'start_time': '2026-06-01T09:00:00',
          'end_time': '2026-06-01T10:15:00',
        },
      ]);
      expect(stats.totalMinutes, 75);
    });

    test('night vs day is classified by START time (19:00-07:00 night)', () {
      final stats = SleepStats.fromRows([
        // Starts 18:30, ends 20:30: crosses the boundary but counts as DAY
        // in full, because classification is by start time.
        {
          'start_time': '2026-06-01T18:30:00',
          'end_time': '2026-06-01T20:30:00',
          'duration_minutes': 120,
        },
        // Starts exactly 19:00 -> night.
        {
          'start_time': '2026-06-01T19:00:00',
          'end_time': '2026-06-02T01:00:00',
          'duration_minutes': 360,
        },
        // Starts 06:59 -> still night.
        {
          'start_time': '2026-06-02T06:59:00',
          'end_time': '2026-06-02T07:59:00',
          'duration_minutes': 60,
        },
        // Starts exactly 07:00 -> day.
        {
          'start_time': '2026-06-02T07:00:00',
          'end_time': '2026-06-02T08:00:00',
          'duration_minutes': 60,
        },
      ]);
      expect(stats.nightMinutes, 420); // 360 + 60
      expect(stats.dayMinutes, 180); // 120 + 60
      expect(stats.nightPct, 70); // 420 / 600
      expect(stats.dayPct, 30);
    });
  });

  group('NappyStats', () {
    test('"both" counts in wet AND dirty', () {
      final stats = NappyStats.fromRows([
        {'type': 'wet'},
        {'type': 'wet'},
        {'type': 'dirty'},
        {'type': 'both'},
      ]);
      expect(stats.total, 4);
      expect(stats.wetCount, 3); // 2 wet + 1 both
      expect(stats.dirtyCount, 2); // 1 dirty + 1 both
    });

    test('stool type distribution skips rows without the column', () {
      final stats = NappyStats.fromRows([
        {'type': 'dirty', 'stool_type': 4},
        {'type': 'dirty', 'stool_type': 4},
        {'type': 'both', 'stool_type': 6},
        {'type': 'wet'},
      ]);
      expect(stats.stoolTypeCounts, {4: 2, 6: 1});
    });

    test('empty period', () {
      final stats = NappyStats.fromRows(const []);
      expect(stats.total, 0);
      expect(stats.wetCount, 0);
      expect(stats.dirtyCount, 0);
      expect(stats.stoolTypeCounts, isEmpty);
    });
  });

  group('uncomfortableDayCount', () {
    test('counts distinct days with cramps or gas rated 2+', () {
      expect(
        uncomfortableDayCount([
          {'journal_date': '2026-06-01', 'cramps': 2, 'gas': 0},
          {'journal_date': '2026-06-02', 'cramps': 0, 'gas': 3},
          {'journal_date': '2026-06-03', 'cramps': 1, 'gas': 1},
          {'journal_date': '2026-06-04'},
        ]),
        2,
      );
    });
  });

  group('RefluxStats', () {
    final rows = [
      {
        'logged_at': '2026-06-01T08:00:00',
        'severity': 2,
        'painful_crying': true,
        'trigger_noticed': ' After Feed ',
      },
      {
        'logged_at': '2026-06-01T12:00:00',
        'severity': 3,
        'trigger_noticed': 'after feed',
      },
      {
        'logged_at': '2026-06-02T09:00:00',
        'severity': 2,
        'painful_crying': true,
        'trigger_noticed': 'lying flat',
      },
      {'logged_at': '2026-06-03T09:00:00'},
    ];

    test('severity distribution, painful count and per-day buckets', () {
      final stats = RefluxStats.fromRows(rows);
      expect(stats.total, 4);
      expect(stats.severityCounts, {2: 2, 3: 1});
      expect(stats.painfulCount, 2);
      expect(stats.perDayCounts,
          {'2026-06-01': 2, '2026-06-02': 1, '2026-06-03': 1});
      expect(stats.worstDay, '2026-06-01');
      expect(stats.worstDayCount, 2);
    });

    test('triggers group case- and whitespace-insensitively', () {
      final stats = RefluxStats.fromRows(rows);
      expect(stats.triggerCounts, {'after feed': 2, 'lying flat': 1});
      expect(stats.topTriggers.first.key, 'after feed');
      expect(stats.topTriggers.first.value, 2);
    });

    test('empty period', () {
      final stats = RefluxStats.fromRows(const []);
      expect(stats.total, 0);
      expect(stats.worstDay, isNull);
      expect(stats.topTriggers, isEmpty);
    });
  });

  group('MedicationAdherence', () {
    final catalog = [
      {'name': 'Gaviscon', 'frequency_per_day': 3},
      {'name': 'Vitamin D', 'frequency_per_day': 1},
      {'name': 'Paracetamol', 'as_needed': true},
    ];

    List<Map<String, dynamic>> doses(Map<String, int> byName) => [
          for (final e in byName.entries)
            for (var i = 0; i < e.value; i++) {'medication': e.key},
        ];

    test('expected = frequency x days for a fully past period', () {
      // Past 7-day week, fully elapsed: divisor is the full 7 days.
      final days = divisorDays(
        periodStart: DateTime(2026, 5, 25),
        periodEnd: DateTime(2026, 6, 1),
        now: DateTime(2026, 6, 10),
      );
      expect(days, 7);
      final adherence = MedicationAdherence.compute(
        catalog: catalog,
        healthLogs: doses({'gaviscon': 18, 'vitamin d': 7}),
        days: days,
      );
      final gaviscon = adherence.scheduled[0];
      expect(gaviscon.name, 'Gaviscon');
      expect(gaviscon.expected, 21); // 3 x 7
      expect(gaviscon.given, 18);
      expect(gaviscon.adherence, closeTo(18 / 21, 1e-9));
      final vitD = adherence.scheduled[1];
      expect(vitD.expected, 7); // 1 x 7
      expect(vitD.adherence, 1.0);
    });

    test('expected uses elapsed days when the period includes today', () {
      // Week of Mon 8 June, "today" is Wed 10 June: 3 elapsed days.
      final days = divisorDays(
        periodStart: DateTime(2026, 6, 8),
        periodEnd: DateTime(2026, 6, 15),
        now: DateTime(2026, 6, 10, 16),
      );
      expect(days, 3);
      final adherence = MedicationAdherence.compute(
        catalog: catalog,
        healthLogs: doses({'gaviscon': 9}),
        days: days,
      );
      expect(adherence.scheduled[0].expected, 9); // 3 x 3, not 3 x 7
      expect(adherence.scheduled[0].adherence, 1.0);
    });

    test('dose matching is case-insensitive on the medication name', () {
      final adherence = MedicationAdherence.compute(
        catalog: catalog,
        healthLogs: [
          {'medication': 'GAVISCON'},
          {'medication': 'Gaviscon '},
        ],
        days: 1,
      );
      expect(adherence.scheduled[0].given, 2);
    });

    test('as-needed meds and uncatalogued doses land in asNeeded', () {
      final adherence = MedicationAdherence.compute(
        catalog: catalog,
        healthLogs: doses({'paracetamol': 2, 'teething gel': 1}),
        days: 7,
      );
      expect(adherence.asNeeded, hasLength(2));
      final paracetamol =
          adherence.asNeeded.firstWhere((a) => a.name == 'Paracetamol');
      expect(paracetamol.given, 2);
      expect(paracetamol.inCatalog, isTrue);
      final gel =
          adherence.asNeeded.firstWhere((a) => a.name == 'teething gel');
      expect(gel.given, 1);
      expect(gel.inCatalog, isFalse);
    });

    test('zero or missing frequency is treated as as-needed', () {
      final adherence = MedicationAdherence.compute(
        catalog: [
          {'name': 'Mystery drops', 'frequency_per_day': 0},
        ],
        healthLogs: const [],
        days: 7,
      );
      expect(adherence.scheduled, isEmpty);
      expect(adherence.asNeeded.single.name, 'Mystery drops');
    });

    test('health logs without a medication are not doses', () {
      expect(
        medicationDoseCount([
          {'medication': 'Gaviscon'},
          {'medication': '  '},
          {'temperature_c': 37.0},
        ]),
        1,
      );
    });
  });

  group('temperatureStatus', () {
    test('clinical bands', () {
      expect(temperatureStatus(35.9), 'Low');
      expect(temperatureStatus(36.8), 'Normal');
      expect(temperatureStatus(37.5), 'Normal');
      expect(temperatureStatus(38.0), 'Fever');
      expect(temperatureStatus(38.6), 'High fever');
    });
  });

  group('moodCounts', () {
    test('counts known moods only', () {
      expect(
        moodCounts([
          {'mood': 'happy'},
          {'mood': 'happy'},
          {'mood': 'very_fussy'},
          {'mood': 'ecstatic'}, // unknown -> skipped
          {},
        ]),
        {'happy': 2, 'very_fussy': 1},
      );
    });
  });

  group('GlanceAggregates', () {
    test('aggregates every headline number from raw rows', () {
      final agg = GlanceAggregates.of(
        feedings: [
          {'logged_at': '2026-06-01T08:00:00', 'amount_ml': 100},
          {'logged_at': '2026-06-01T12:00:00', 'amount_ml': 140},
          {'logged_at': '2026-06-01T16:00:00'},
        ],
        sleeps: [
          {
            'start_time': '2026-06-01T20:00:00',
            'end_time': '2026-06-02T02:00:00',
            'duration_minutes': 360,
          },
          {
            'start_time': '2026-06-02T13:00:00',
            'end_time': '2026-06-02T14:00:00',
            'duration_minutes': 60,
          },
        ],
        diapers: [
          {'type': 'wet'},
          {'type': 'both'},
        ],
        tummyTimes: [
          {'duration_minutes': 10},
          {'duration_minutes': 5},
        ],
        reflux: [
          {'logged_at': '2026-06-01T09:00:00'},
        ],
        healthLogs: [
          {'medication': 'Gaviscon'},
          {'temperature_c': 37.2},
        ],
      );
      expect(agg.feeds, 3);
      expect(agg.avgMl, 120.0);
      expect(agg.sleepMinutes, 420);
      expect(agg.longestSleepMin, 360);
      expect(agg.nappies, 2);
      expect(agg.tummyMinutes, 15);
      expect(agg.refluxEvents, 1);
      expect(agg.medicineDoses, 1);
    });

    test('deltas vs an empty previous period read as "new"', () {
      const days = 7;
      const prevDays = 7;
      final cur = GlanceAggregates.of(
        feedings: [
          {'logged_at': '2026-06-01T08:00:00'},
        ],
        sleeps: const [],
        diapers: const [],
        tummyTimes: const [],
        reflux: const [],
        healthLogs: const [],
      );
      final prev = GlanceAggregates.of(
        feedings: const [],
        sleeps: const [],
        diapers: const [],
        tummyTimes: const [],
        reflux: const [],
        healthLogs: const [],
      );
      expect(
        deltaLabel(perDay(cur.feeds, days), perDay(prev.feeds, prevDays)),
        'new',
      );
      expect(
        deltaLabel(perDay(cur.nappies, days), perDay(prev.nappies, prevDays)),
        'no change',
      );
    });
  });

  group('dailyLedger', () {
    List<DayLedger> build() => dailyLedger(
          start: DateTime(2026, 6, 8),
          days: 3,
          feedings: [
            {'logged_at': '2026-06-08T06:00:00', 'amount_ml': 120},
            {'logged_at': '2026-06-08T09:30:00', 'amount_ml': 90},
            {'logged_at': '2026-06-09T07:00:00'}, // breast, no ml
          ],
          sleeps: [
            // Starts on the 8th late evening, ends on the 9th: counts on the 8th.
            {
              'start_time': '2026-06-08T22:00:00',
              'end_time': '2026-06-09T05:00:00',
            },
            {'start_time': '2026-06-09T13:00:00', 'duration_minutes': 90},
            // Open session (no end, no duration) is ignored.
            {'start_time': '2026-06-10T20:00:00'},
          ],
          diapers: [
            {'logged_at': '2026-06-08T08:00:00', 'type': 'wet'},
            {'logged_at': '2026-06-10T10:00:00', 'type': 'dirty'},
          ],
          reflux: [
            {'logged_at': '2026-06-09T11:00:00'},
          ],
          healthLogs: [
            {'logged_at': '2026-06-08T07:00:00', 'medication': 'Nexiam'},
            // Temperature-only rows are not medicine doses.
            {'logged_at': '2026-06-08T12:00:00', 'temperature_c': 37.0},
          ],
          tummyTimes: [
            {'start_time': '2026-06-09T15:00:00', 'duration_minutes': 12},
            {'start_time': '2026-06-09T17:00:00', 'duration_minutes': 8},
          ],
          journals: [
            {'journal_date': '2026-06-08', 'mood': 'happy'},
            {'journal_date': '2026-06-10', 'mood': 'fussy'},
          ],
        );

    test('produces one row per day, in order', () {
      final ledger = build();
      expect(ledger.length, 3);
      expect(ledger[0].day, DateTime(2026, 6, 8));
      expect(ledger[2].day, DateTime(2026, 6, 10));
    });

    test('buckets every domain on the right local day', () {
      final l = build();
      // 8 June: 2 feeds 210ml, the overnight sleep, 1 nappy, 1 dose, happy.
      expect(l[0].feeds, 2);
      expect(l[0].milkMl, 210);
      expect(l[0].sleepSessions, 1);
      expect(l[0].sleepMinutes, 7 * 60);
      expect(l[0].nappies, 1);
      expect(l[0].medicineDoses, 1);
      expect(l[0].mood, 'happy');
      expect(l[0].refluxEvents, 0);
      // 9 June: 1 feed no ml, 90min nap, reflux event, 20min tummy.
      expect(l[1].feeds, 1);
      expect(l[1].milkMl, 0);
      expect(l[1].sleepMinutes, 90);
      expect(l[1].refluxEvents, 1);
      expect(l[1].tummyMinutes, 20);
      expect(l[1].mood, isNull);
      // 10 June: nappy + fussy mood; the open sleep session is ignored.
      expect(l[2].nappies, 1);
      expect(l[2].sleepSessions, 0);
      expect(l[2].mood, 'fussy');
      expect(l[2].isEmpty, isFalse);
    });

    test('a day with nothing logged is empty', () {
      final ledger = dailyLedger(
        start: DateTime(2026, 6, 1),
        days: 2,
        feedings: const [],
        sleeps: const [],
        diapers: const [],
        reflux: const [],
        healthLogs: const [],
        tummyTimes: const [],
        journals: const [],
      );
      expect(ledger.every((l) => l.isEmpty), isTrue);
    });
  });
}
