/// Static content for the Care Pack features, digitised from the
/// "Allies Family Baby Care Tracking & Reporting Pack".
///
/// Pure data: no Flutter imports so it stays unit-testable.
library;

class CarePackStage {
  /// Stable id stored in weekly_reports.age_stage / monthly_reviews.age_stage.
  final String id;
  final String label;
  final String subtitle;
  final int minMonths; // inclusive
  final int maxMonths; // inclusive

  /// Weekly report checklist ("First time / Better / Not yet").
  final List<CareCheckItem> weeklyMilestones;

  /// Stage-specific focus questions on the weekly report.
  final String focusTitle;
  final String focusIntro;
  final List<CareCheckItem> focusQuestions;

  /// Monthly review checklist ("Yes / Sometimes / Not yet"), by section.
  final List<CareChecklistSection> monthlyChecklist;

  const CarePackStage({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.minMonths,
    required this.maxMonths,
    required this.weeklyMilestones,
    required this.focusTitle,
    required this.focusIntro,
    required this.focusQuestions,
    required this.monthlyChecklist,
  });
}

class CareCheckItem {
  /// Stable key stored in jsonb maps - never change once shipped.
  final String key;
  final String label;
  const CareCheckItem(this.key, this.label);
}

class CareChecklistSection {
  final String title;
  final List<CareCheckItem> items;
  const CareChecklistSection(this.title, this.items);
}

class CareScalePoint {
  final int value;
  final String label;
  final bool alert;
  const CareScalePoint(this.value, this.label, {this.alert = false});
}

abstract final class CarePackData {
  /// Weekly milestone-check states.
  static const String checkFirstTime = 'first_time';
  static const String checkBetter = 'better';
  static const String checkNotYet = 'not_yet';

  /// Monthly checklist states.
  static const String monthlyYes = 'yes';
  static const String monthlySometimes = 'sometimes';
  static const String monthlyNotYet = 'not_yet';

  static const List<CarePackStage> stages = [
    CarePackStage(
      id: '2-3m',
      label: '2-3 Months',
      subtitle: 'Newborn stage: head control, social smiles, eye tracking',
      minMonths: 0,
      maxMonths: 3,
      weeklyMilestones: [
        CareCheckItem('lifted_head_tummy', 'Lifted head briefly during tummy time'),
        CareCheckItem('head_steady_upright', 'Held head steadier when held upright'),
        CareCheckItem('tracked_face', 'Tracked your face moving side to side'),
        CareCheckItem('followed_toy_eyes', 'Followed a toy with his eyes'),
        CareCheckItem('eye_contact_longer', 'Made eye contact for longer'),
        CareCheckItem('social_smile', 'Smiled in response to your face (social smile)'),
        CareCheckItem('cooed_vowels', 'Cooed, gurgled, or made vowel sounds ("ooh", "ahh")'),
        CareCheckItem('turned_to_sound', 'Turned head toward a sound'),
        CareCheckItem('hands_to_mouth', 'Brought hands to his mouth'),
        CareCheckItem('open_close_hands', 'Opened & closed his hands'),
        CareCheckItem('calmed_when_held', 'Calmed when picked up or spoken to'),
      ],
      focusTitle: 'Newborn focus: tummy time and alertness',
      focusIntro:
          'At this stage we are mainly watching head control, eye contact, and alertness windows between feeds and sleep.',
      focusQuestions: [
        CareCheckItem('tummy_time_total', 'Total tummy time this week (minutes)'),
        CareCheckItem('tummy_time_best', 'How long he tolerated tummy time at best'),
        CareCheckItem('longest_alert_window', 'Length of his longest "awake and alert" window'),
        CareCheckItem('am_pm_alertness', 'Any difference between morning and evening alertness?'),
      ],
      monthlyChecklist: [
        CareChecklistSection('Physical & motor', [
          CareCheckItem('holds_head_tummy', 'Holds head up briefly when on tummy'),
          CareCheckItem('pushes_up_arms', 'Pushes up on arms during tummy time'),
          CareCheckItem('moves_smoothly', 'Moves arms and legs smoothly'),
          CareCheckItem('opens_closes_hands', 'Opens and closes hands'),
          CareCheckItem('hands_to_mouth', 'Brings hands to mouth'),
        ]),
        CareChecklistSection('Communication & senses', [
          CareCheckItem('follows_with_eyes', 'Follows objects or people with eyes'),
          CareCheckItem('turns_to_sounds', 'Turns head toward sounds'),
          CareCheckItem('coos', "Coos and makes 'ooh' or 'ahh' sounds"),
          CareCheckItem('watches_faces', 'Watches faces intently'),
        ]),
        CareChecklistSection('Social & emotional', [
          CareCheckItem('social_smile', 'Smiles at people (social smile)'),
          CareCheckItem('calms_when_held', 'Calms when picked up or spoken to'),
          CareCheckItem('looks_at_carer', 'Tries to look at the parent or nanny'),
        ]),
      ],
    ),
    CarePackStage(
      id: '4m',
      label: '4 Months',
      subtitle: 'Grabbing, rolling, babbling stage',
      minMonths: 4,
      maxMonths: 4,
      weeklyMilestones: [
        CareCheckItem('head_steady_no_support', 'Held head steady without support'),
        CareCheckItem('pushed_up_forearms', 'Pushed up on forearms during tummy time'),
        CareCheckItem('rolled', 'Rolled tummy to back (or back to tummy?)'),
        CareCheckItem('hands_together', 'Brought hands together / clasped them'),
        CareCheckItem('reached_for_toy', 'Reached for a toy'),
        CareCheckItem('grabbed_held_toy', 'Grabbed a toy and held it'),
        CareCheckItem('toys_to_mouth', 'Brought toys to his mouth'),
        CareCheckItem('babbled_consonants', 'Babbled with new sounds (consonants like "b", "m")'),
        CareCheckItem('laughed', 'Laughed out loud'),
        CareCheckItem('recognised_across_room', 'Recognised you from across the room'),
        CareCheckItem('pushed_down_legs', 'Pushed down on legs when feet on a surface'),
        CareCheckItem('copied_expression', 'Copied a facial expression'),
      ],
      focusTitle: '4 month focus: rolling, reaching, and play',
      focusIntro:
          'This stage is about hands and rolling. He should be reaching, grabbing, and might start to roll. Lots of play time on his back and tummy.',
      focusQuestions: [
        CareCheckItem('tummy_time_total', 'Tummy time total this week (minutes)'),
        CareCheckItem('did_he_roll', 'Did he roll? (tummy to back, back to tummy, both, neither)'),
        CareCheckItem('favourite_toy', 'Favourite toy this week'),
        CareCheckItem('self_entertain', 'How long he can entertain himself with a toy'),
        CareCheckItem('wants_to_sit', 'Any signs he is starting to want to sit up?'),
      ],
      monthlyChecklist: [
        CareChecklistSection('Physical & motor', [
          CareCheckItem('head_steady', 'Holds head steady without support'),
          CareCheckItem('pushes_down_legs', 'Pushes down on legs when feet are on a surface'),
          CareCheckItem('hands_together', 'Brings hands together'),
          CareCheckItem('reaches_one_hand', 'Reaches for toys with one hand'),
          CareCheckItem('may_roll', 'May roll from tummy to back'),
        ]),
        CareChecklistSection('Communication & senses', [
          CareCheckItem('babbles_expression', 'Babbles with expression and copies sounds'),
          CareCheckItem('cries_differently', 'Cries differently for different needs'),
          CareCheckItem('responds_affection', 'Responds to affection'),
          CareCheckItem('recognises_distance', 'Recognises familiar people from a distance'),
        ]),
        CareChecklistSection('Social & emotional', [
          CareCheckItem('smiles_spontaneously', 'Smiles spontaneously, especially at people'),
          CareCheckItem('likes_play', 'Likes to play with people, may cry when play stops'),
          CareCheckItem('copies_movements', 'Copies some movements and facial expressions'),
        ]),
      ],
    ),
    CarePackStage(
      id: '5-6m',
      label: '5-6 Months',
      subtitle: 'Sitting, solids, and "who\'s that?" stage',
      minMonths: 5,
      maxMonths: 6,
      weeklyMilestones: [
        CareCheckItem('rolled_both', 'Rolled both directions (tummy to back, back to tummy)'),
        CareCheckItem('sat_supported', 'Sat with support (propped on hands or pillows)'),
        CareCheckItem('sat_unsupported_secs', 'Sat unsupported for a few seconds'),
        CareCheckItem('rocked_hands_knees', 'Rocked on hands and knees'),
        CareCheckItem('passed_toy_hands', 'Passed a toy from one hand to the other'),
        CareCheckItem('responded_name', 'Responded to his name'),
        CareCheckItem('strung_sounds', 'Strung sounds together ("bababa", "mamama")'),
        CareCheckItem('consonants_intent', 'Made consonant sounds with intent'),
        CareCheckItem('watched_things_fall', 'Watched things fall when he dropped them'),
        CareCheckItem('interest_in_food', 'Showed interest in food we were eating'),
        CareCheckItem('mirror_interest', 'Looked at himself in the mirror with interest'),
        CareCheckItem('stranger_vs_family', 'Reacted to a stranger differently than to family'),
      ],
      focusTitle: '5 to 6 month focus: sitting and starting solids',
      focusIntro:
          'Big stage. Sitting is the main motor milestone. If solids have started, we need feeding details as well as bottle feeds.',
      focusQuestions: [
        CareCheckItem('longest_sit', 'Longest time he sat unsupported (seconds)'),
        CareCheckItem('tripoding', 'Is he tripoding (leaning on hands)?'),
        CareCheckItem('solids_started', 'Has he started solids? If yes, when did we start?'),
        CareCheckItem('foods_tried', 'Foods tried this week'),
        CareCheckItem('food_reactions', 'Any reaction to a food (rash, vomiting, fussiness)?'),
        CareCheckItem('spoon_progress', 'How is he with the spoon?'),
      ],
      monthlyChecklist: [
        CareChecklistSection('Physical & motor', [
          CareCheckItem('rolls_both', 'Rolls in both directions (front to back, back to front)'),
          CareCheckItem('begins_sit', 'Begins to sit without support'),
          CareCheckItem('rocks_crawls_back', 'Rocks back and forth, sometimes crawls backward'),
          CareCheckItem('weight_on_legs', 'Supports weight on legs when held standing'),
          CareCheckItem('passes_hands', 'Passes things from one hand to the other'),
        ]),
        CareChecklistSection('Communication & senses', [
          CareCheckItem('responds_name', 'Responds to own name'),
          CareCheckItem('strings_vowels', 'Strings vowels together when babbling'),
          CareCheckItem('responds_sounds', 'Responds to sounds by making sounds'),
          CareCheckItem('consonant_sounds', "Begins to say consonant sounds (jabbering with 'm', 'b')"),
        ]),
        CareChecklistSection('Social & emotional', [
          CareCheckItem('knows_faces', 'Knows familiar faces, starts to know strangers'),
          CareCheckItem('likes_play_others', 'Likes to play with others, especially parents'),
          CareCheckItem('responds_emotions', "Responds to other people's emotions, often seems happy"),
          CareCheckItem('mirror_self', 'Likes to look at self in mirror'),
        ]),
      ],
    ),
    CarePackStage(
      id: '7-9m',
      label: '7-9 Months',
      subtitle: 'Crawling, pulling up, and stranger anxiety stage',
      minMonths: 7,
      maxMonths: 9,
      weeklyMilestones: [
        CareCheckItem('sat_no_support', 'Sat without any support'),
        CareCheckItem('got_to_sitting', 'Got into sitting from lying down by himself'),
        CareCheckItem('crawled', 'Crawled (forward, backward, scoot, army-crawl?)'),
        CareCheckItem('pulled_to_stand', 'Pulled himself up to stand'),
        CareCheckItem('cruised', 'Cruised along furniture'),
        CareCheckItem('pincer', 'Picked things up with thumb + finger (pincer)'),
        CareCheckItem('banged_things', 'Banged two things together'),
        CareCheckItem('mama_dada', 'Said "mama" or "dada" (any meaning yet?)'),
        CareCheckItem('babbled_strings', 'Babbled long strings of sounds'),
        CareCheckItem('responded_no', 'Responded to "no"'),
        CareCheckItem('peekaboo', 'Played peek-a-boo'),
        CareCheckItem('stranger_wary', 'Was wary of strangers / clung to familiar people'),
        CareCheckItem('pointed', 'Pointed at something'),
        CareCheckItem('looked_for_toy', 'Looked for a dropped toy'),
      ],
      focusTitle: '7 to 9 month focus: movement and safety',
      focusIntro:
          "He's mobile now. Track how far he can move and what he gets into. Safety is the new priority: plug points, stairs, sharp corners.",
      focusQuestions: [
        CareCheckItem('mobility_level', 'What can he do? (sit / crawl / pull up / cruise)'),
        CareCheckItem('move_distance', 'How far does he move on his own?'),
        CareCheckItem('babyproofing', 'New places we had to baby-proof this week'),
        CareCheckItem('stood_alone', 'Did he stand alone (even for a second)?'),
        CareCheckItem('separation_anxiety', 'Any signs of stranger anxiety / separation anxiety?'),
        CareCheckItem('sleep_regression', 'Sleep regression. Is it happening?'),
      ],
      monthlyChecklist: [
        CareChecklistSection('Physical & motor', [
          CareCheckItem('sits_no_support', 'Sits without support'),
          CareCheckItem('crawls', 'Crawls'),
          CareCheckItem('pulls_to_stand', 'Pulls to stand'),
          CareCheckItem('pincer_grasp', 'Picks things up with thumb and finger (pincer grasp)'),
          CareCheckItem('bangs_together', 'Bangs two things together'),
        ]),
        CareChecklistSection('Communication & senses', [
          CareCheckItem('understands_no', 'Understands "no"'),
          CareCheckItem('many_sounds', "Makes lots of different sounds like 'mamamama' and 'bababa'"),
          CareCheckItem('copies_sounds', 'Copies sounds and gestures of others'),
          CareCheckItem('points', 'Points to things'),
        ]),
        CareChecklistSection('Social & emotional', [
          CareCheckItem('afraid_strangers', 'May be afraid of strangers'),
          CareCheckItem('clingy_familiar', 'May be clingy with familiar adults'),
          CareCheckItem('favourite_toys', 'Has favourite toys'),
        ]),
      ],
    ),
    CarePackStage(
      id: '10-12m',
      label: '10-12 Months',
      subtitle: 'First words, first steps, big personality',
      minMonths: 10,
      maxMonths: 240,
      weeklyMilestones: [
        CareCheckItem('pulled_stand_confident', 'Pulled to stand confidently'),
        CareCheckItem('cruised_confident', 'Cruised along furniture confidently'),
        CareCheckItem('stood_alone', 'Stood alone (any duration)'),
        CareCheckItem('first_steps', 'Took first steps (alone, no holding)'),
        CareCheckItem('pincer_easy', 'Used pincer grasp easily'),
        CareCheckItem('mama_dada_meaning', 'Said "mama" or "dada" with clear meaning'),
        CareCheckItem('other_word', 'Used another word (which one?)'),
        CareCheckItem('waved_bye', 'Waved "bye-bye"'),
        CareCheckItem('shook_head_no', 'Shook head for "no"'),
        CareCheckItem('followed_instruction', 'Followed a simple instruction ("give me", "come here")'),
        CareCheckItem('drank_from_cup', 'Drank from a cup'),
        CareCheckItem('helped_dressing', 'Helped with dressing (held out an arm/leg)'),
        CareCheckItem('showed_affection', 'Showed affection (hugs, leaning in)'),
        CareCheckItem('patacake', 'Played pat-a-cake / peek-a-boo back'),
        CareCheckItem('imitated_adult', 'Imitated what an adult does'),
      ],
      focusTitle: '10 to 12 month focus: communication and first steps',
      focusIntro:
          'First words and first steps. Even small gestures (pointing, waving, shaking head) are communication wins worth noting.',
      focusQuestions: [
        CareCheckItem('meaningful_words', 'Words / word-like sounds he uses with meaning'),
        CareCheckItem('stand_seconds', 'How many seconds can he stand alone?'),
        CareCheckItem('unsupported_steps', 'Has he taken any unsupported steps?'),
        CareCheckItem('gestures', 'Gestures he uses (pointing, waving, shaking head, etc.)'),
        CareCheckItem('understands_instructions', 'Does he understand simple instructions?'),
        CareCheckItem('frustration', 'How does he handle frustration or being told no?'),
      ],
      monthlyChecklist: [
        CareChecklistSection('Physical & motor', [
          CareCheckItem('sits_without_help', 'Gets to a sitting position without help'),
          CareCheckItem('cruises', 'Pulls up to stand, walks holding furniture (cruising)'),
          CareCheckItem('few_steps', 'May take a few steps without holding on'),
          CareCheckItem('stands_alone', 'May stand alone'),
          CareCheckItem('drinks_cup', 'Drinks from a cup'),
          CareCheckItem('pincer_confident', 'Uses pincer grasp confidently'),
        ]),
        CareChecklistSection('Communication & senses', [
          CareCheckItem('responds_requests', 'Responds to simple spoken requests'),
          CareCheckItem('simple_gestures', "Uses simple gestures (shaking head 'no', waving 'bye-bye')"),
          CareCheckItem('mama_dada_meaning', "Says 'mama' and 'dada' meaningfully"),
          CareCheckItem('tries_words', 'Tries to say words you say'),
        ]),
        CareChecklistSection('Social & emotional', [
          CareCheckItem('shy_strangers', 'Is shy or nervous with strangers'),
          CareCheckItem('cries_at_leaving', 'Cries when mom or dad leaves'),
          CareCheckItem('favourites', 'Has favourite things and people'),
          CareCheckItem('repeats_for_attention', 'Repeats sounds or actions to get attention'),
          CareCheckItem('plays_games', 'Plays games like peek-a-boo and pat-a-cake'),
        ]),
      ],
    ),
  ];

  /// Stage for a baby of [ageMonths]. Clamps to the nearest stage so a
  /// 13-month-old still gets the 10-12 month content.
  static CarePackStage stageForAgeMonths(int ageMonths) {
    for (final stage in stages) {
      if (ageMonths >= stage.minMonths && ageMonths <= stage.maxMonths) {
        return stage;
      }
    }
    return stages.last;
  }

  static CarePackStage? stageById(String id) {
    for (final stage in stages) {
      if (stage.id == id) return stage;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Scales
  // ---------------------------------------------------------------

  static const List<CareScalePoint> refluxSeverity = [
    CareScalePoint(1, 'Small spit-up, no distress'),
    CareScalePoint(2, 'Larger spit-up, mild fussing'),
    CareScalePoint(3, 'Projectile or repeated, clear discomfort'),
    CareScalePoint(4, 'Painful crying, refuses to settle'),
    CareScalePoint(5, 'Projectile + pain + refusing feeds. Tell parents the same day.', alert: true),
  ];

  static const List<CareScalePoint> stoolTypes = [
    CareScalePoint(1, 'Hard little pellets (constipation)', alert: true),
    CareScalePoint(2, 'Hard, lumpy, sausage-shaped'),
    CareScalePoint(3, 'Sausage with cracks on the surface'),
    CareScalePoint(4, 'Smooth, soft, sausage or paste (normal for formula babies)'),
    CareScalePoint(5, 'Soft blobs with clear edges'),
    CareScalePoint(6, 'Mushy, fluffy pieces (normal for breastfed babies)'),
    CareScalePoint(7, 'Watery, no solid pieces (diarrhoea)', alert: true),
  ];

  static const List<CareScalePoint> crampsGasScale = [
    CareScalePoint(0, 'None noticed'),
    CareScalePoint(1, 'Mild, brief fussing, settled quickly'),
    CareScalePoint(2, 'Clearly uncomfortable, pulling legs up, needs holding'),
    CareScalePoint(3, 'Severe, crying for over 30 minutes, very hard to settle', alert: true),
  ];

  // ---------------------------------------------------------------
  // Red flags
  // ---------------------------------------------------------------

  static const List<String> redFlags = [
    'Fever (any fever under 3 months; over 38°C in older babies)',
    'Refusing more than 2 feeds in a row',
    'Projectile vomiting (forceful, large amounts, different from spit-up)',
    'Blood or green colour in vomit or stool',
    'Fewer than 4 wet nappies in 24 hours',
    'Very sleepy, floppy, or hard to wake',
    'Breathing fast, noisy, or with effort (ribs pulling in)',
    'Skin colour change: bluish lips, very pale, or yellow',
    "Rash that doesn't fade when pressed",
    "Crying that won't stop for over an hour",
    'Any fall, knock to the head, or accident',
    'Convulsions, fits, or unusual stiffening',
    'Loses a skill he used to have (stops smiling, stops cooing for days)',
  ];

  static const List<String> tummyRedFlags = [
    'No poo for more than 3 days (formula) or more than 7 days (breastfed)',
    'Hard pellets with crying or visible straining',
    'Watery diarrhoea more than 3 times in a day',
    'Blood or mucus in the stool',
    'Stool that is white, grey, or black',
    'Very swollen / hard tummy',
    'Vomiting along with no poo',
    'Refusing to feed with a hard tummy',
  ];

  /// Default emergency contact sheet rows (label only; user fills the rest).
  static const List<String> defaultContactLabels = [
    'Parent 1 name & cell',
    'Parent 2 name & cell',
    "Parent's work number (backup)",
    'Paediatrician name & number',
    'Family GP',
    'Closest hospital + address',
    'Ambulance (ER24 / Netcare 911)',
    'Police (10111)',
    'Poison hotline',
    'Trusted neighbour',
    'Grandparents',
    'Medical aid name & member number',
    "Baby's blood type (if known)",
    'Known allergies / conditions',
    'Reflux medication & dose (if any)',
  ];

  /// Shown with the sources so users know this is general information.
  static const String medicalDisclaimer =
      'This Care Guide is general information digitised from the public health '
      'sources listed below. It is not a substitute for professional medical '
      'advice, diagnosis, or treatment. Always follow your doctor, clinic, or '
      'emergency service, and call them whenever you are unsure.';

  /// Authoritative sources cited for the medical guidance in this screen
  /// (red flags, tummy red flags, and the reflux / stool / cramps scales).
  static const List<CareSource> sources = [
    CareSource(
      publisher: 'NHS',
      title: 'Is my baby or toddler seriously ill? '
          '(fever, breathing, dehydration, red flags)',
      url:
          'https://www.nhs.uk/conditions/baby/health/is-my-baby-or-toddler-seriously-ill/',
    ),
    CareSource(
      publisher: 'NHS',
      title: 'Reflux in babies',
      url: 'https://www.nhs.uk/conditions/reflux-in-babies/',
    ),
    CareSource(
      publisher: 'NICE',
      title: 'Gastro-oesophageal reflux disease in children and young people '
          '(NG1)',
      url: 'https://www.nice.org.uk/guidance/ng1',
    ),
    CareSource(
      publisher: 'NHS',
      title: 'Sepsis - urgent warning signs and the rash that does not fade',
      url: 'https://www.nhs.uk/conditions/sepsis/',
    ),
    CareSource(
      publisher: 'NHS',
      title: 'Diarrhoea and vomiting',
      url: 'https://www.nhs.uk/conditions/diarrhoea-and-vomiting/',
    ),
    CareSource(
      publisher: 'NHS',
      title: 'Colic',
      url: 'https://www.nhs.uk/conditions/colic/',
    ),
    CareSource(
      publisher: 'American Academy of Pediatrics (HealthyChildren.org)',
      title: 'Fever - when to call the pediatrician',
      url:
          'https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/When-to-Call-the-Pediatrician.aspx',
    ),
    CareSource(
      publisher: 'NHS Start for Life',
      title: "Your baby's health and development, including nappies and stools",
      url: 'https://www.nhs.uk/start-for-life/baby/',
    ),
  ];
}

/// A single cited reference for the medical content in the Care Guide.
class CareSource {
  final String title;
  final String publisher;
  final String url;

  const CareSource({
    required this.title,
    required this.publisher,
    required this.url,
  });
}
