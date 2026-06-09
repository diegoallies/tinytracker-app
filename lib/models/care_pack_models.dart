/// Models for the Care Pack features (reflux, daily journal, weekly report,
/// monthly review, emergency contacts). Kept in one file — they ship and
/// evolve together with supabase/2026-06-10_care_pack.sql.
library;

class RefluxEvent {
  final String id;
  final String babyId;
  final String userId;
  final int severity; // 1–5
  final bool painfulCrying;
  final bool archingBack;
  final String? triggerNoticed;
  final String? notes;
  final DateTime loggedAt;
  final DateTime createdAt;

  const RefluxEvent({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.severity,
    required this.painfulCrying,
    required this.archingBack,
    this.triggerNoticed,
    this.notes,
    required this.loggedAt,
    required this.createdAt,
  });

  bool get isAlert => severity >= 5;

  factory RefluxEvent.fromJson(Map<String, dynamic> json) {
    return RefluxEvent(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      severity: json['severity'] as int,
      painfulCrying: (json['painful_crying'] as bool?) ?? false,
      archingBack: (json['arching_back'] as bool?) ?? false,
      triggerNoticed: json['trigger_noticed'] as String?,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

class DailyJournal {
  final String id;
  final String babyId;
  final String userId;
  final DateTime journalDate;
  final String? mood; // happy | okay | fussy | very_fussy
  final int? cramps; // 0–3
  final int? gas; // 0–3
  final String? fussyTimes;
  final String? activities;
  final String? newThings;
  final String? upsets;
  final String? notes;

  const DailyJournal({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.journalDate,
    this.mood,
    this.cramps,
    this.gas,
    this.fussyTimes,
    this.activities,
    this.newThings,
    this.upsets,
    this.notes,
  });

  factory DailyJournal.fromJson(Map<String, dynamic> json) {
    return DailyJournal(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      journalDate: DateTime.parse(json['journal_date'] as String),
      mood: json['mood'] as String?,
      cramps: json['cramps'] as int?,
      gas: json['gas'] as int?,
      fussyTimes: json['fussy_times'] as String?,
      activities: json['activities'] as String?,
      newThings: json['new_things'] as String?,
      upsets: json['upsets'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class WeeklyCareReport {
  final String id;
  final String babyId;
  final String userId;
  final DateTime weekStart;
  final String ageStage;
  final String? summary;
  final String? struggles;
  final String? questions;
  final Map<String, String> milestoneChecks;
  final Map<String, String> focusAnswers;
  final Map<String, dynamic> metrics;
  final DateTime? submittedAt;

  const WeeklyCareReport({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.weekStart,
    required this.ageStage,
    this.summary,
    this.struggles,
    this.questions,
    this.milestoneChecks = const {},
    this.focusAnswers = const {},
    this.metrics = const {},
    this.submittedAt,
  });

  bool get isSubmitted => submittedAt != null;

  factory WeeklyCareReport.fromJson(Map<String, dynamic> json) {
    return WeeklyCareReport(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      weekStart: DateTime.parse(json['week_start'] as String),
      ageStage: json['age_stage'] as String,
      summary: json['summary'] as String?,
      struggles: json['struggles'] as String?,
      questions: json['questions'] as String?,
      milestoneChecks: _stringMap(json['milestone_checks']),
      focusAnswers: _stringMap(json['focus_answers']),
      metrics: (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String).toLocal()
          : null,
    );
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
}

class MonthlyReview {
  final String id;
  final String babyId;
  final String userId;
  final DateTime reviewMonth;
  final String ageStage;
  final Map<String, String> checklist;
  final String? comments;

  const MonthlyReview({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.reviewMonth,
    required this.ageStage,
    this.checklist = const {},
    this.comments,
  });

  factory MonthlyReview.fromJson(Map<String, dynamic> json) {
    return MonthlyReview(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      reviewMonth: DateTime.parse(json['review_month'] as String),
      ageStage: json['age_stage'] as String,
      checklist: WeeklyCareReport._stringMap(json['checklist']),
      comments: json['comments'] as String?,
    );
  }
}

class EmergencyContact {
  final String id;
  final String babyId;
  final String label;
  final String? name;
  final String? phone;
  final String? notes;
  final int sortOrder;

  const EmergencyContact({
    required this.id,
    required this.babyId,
    required this.label,
    this.name,
    this.phone,
    this.notes,
    this.sortOrder = 0,
  });

  bool get isFilled =>
      (name?.isNotEmpty ?? false) ||
      (phone?.isNotEmpty ?? false) ||
      (notes?.isNotEmpty ?? false);

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      label: json['label'] as String,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }
}
