class MilestoneTemplate {
  final String category;
  final String title;
  final String? description;
  final int expectedAgeMonths;

  const MilestoneTemplate({
    required this.category,
    required this.title,
    this.description,
    required this.expectedAgeMonths,
  });
}

const List<MilestoneTemplate> defaultMilestones = [
  // Motor - 0-2 months
  MilestoneTemplate(category: 'Motor', title: 'Lifts head briefly while on tummy', expectedAgeMonths: 1),
  MilestoneTemplate(category: 'Motor', title: 'Moves arms and legs actively', expectedAgeMonths: 1),
  MilestoneTemplate(category: 'Motor', title: 'Brings hands to mouth', expectedAgeMonths: 2),

  // Social - 0-2 months
  MilestoneTemplate(category: 'Social', title: 'First social smile', expectedAgeMonths: 2),
  MilestoneTemplate(category: 'Social', title: 'Looks at faces', expectedAgeMonths: 1),
  MilestoneTemplate(category: 'Social', title: 'Calms when picked up', expectedAgeMonths: 1),

  // Language - 0-2 months
  MilestoneTemplate(category: 'Language', title: 'Makes cooing sounds', expectedAgeMonths: 2),
  MilestoneTemplate(category: 'Language', title: 'Turns toward sounds', expectedAgeMonths: 2),

  // Cognitive - 0-2 months
  MilestoneTemplate(category: 'Cognitive', title: 'Watches things as they move', expectedAgeMonths: 2),
  MilestoneTemplate(category: 'Cognitive', title: 'Stares at faces', expectedAgeMonths: 1),

  // Motor - 3-4 months
  MilestoneTemplate(category: 'Motor', title: 'Holds head steady unsupported', expectedAgeMonths: 3),
  MilestoneTemplate(category: 'Motor', title: 'Pushes up on arms during tummy time', expectedAgeMonths: 3),
  MilestoneTemplate(category: 'Motor', title: 'Grasps a toy', expectedAgeMonths: 4),
  MilestoneTemplate(category: 'Motor', title: 'Brings hands together', expectedAgeMonths: 4),

  // Social - 3-4 months
  MilestoneTemplate(category: 'Social', title: 'Smiles spontaneously', expectedAgeMonths: 3),
  MilestoneTemplate(category: 'Social', title: 'Enjoys playing with people', expectedAgeMonths: 4),
  MilestoneTemplate(category: 'Social', title: 'Copies some facial expressions', expectedAgeMonths: 4),

  // Language - 3-4 months
  MilestoneTemplate(category: 'Language', title: 'Babbles with expression', expectedAgeMonths: 4),
  MilestoneTemplate(category: 'Language', title: 'Cries differently for different needs', expectedAgeMonths: 3),
  MilestoneTemplate(category: 'Language', title: 'Laughs out loud', expectedAgeMonths: 4),

  // Cognitive - 3-4 months
  MilestoneTemplate(category: 'Cognitive', title: 'Follows moving things with eyes', expectedAgeMonths: 3),
  MilestoneTemplate(category: 'Cognitive', title: 'Recognizes familiar people at a distance', expectedAgeMonths: 4),

  // Motor - 5-6 months
  MilestoneTemplate(category: 'Motor', title: 'Rolls from tummy to back', expectedAgeMonths: 5),
  MilestoneTemplate(category: 'Motor', title: 'Rolls from back to tummy', expectedAgeMonths: 6),
  MilestoneTemplate(category: 'Motor', title: 'Sits with support', expectedAgeMonths: 5),
  MilestoneTemplate(category: 'Motor', title: 'Reaches for and grabs objects', expectedAgeMonths: 5),

  // Social - 5-6 months
  MilestoneTemplate(category: 'Social', title: 'Knows familiar faces', expectedAgeMonths: 5),
  MilestoneTemplate(category: 'Social', title: 'Likes to look at self in mirror', expectedAgeMonths: 6),
  MilestoneTemplate(category: 'Social', title: 'Responds to others\' emotions', expectedAgeMonths: 6),

  // Language - 5-6 months
  MilestoneTemplate(category: 'Language', title: 'Responds to own name', expectedAgeMonths: 6),
  MilestoneTemplate(category: 'Language', title: 'Strings vowels together (ah, eh, oh)', expectedAgeMonths: 6),
  MilestoneTemplate(category: 'Language', title: 'Makes sounds to show joy and displeasure', expectedAgeMonths: 5),

  // Cognitive - 5-6 months
  MilestoneTemplate(category: 'Cognitive', title: 'Brings things to mouth', expectedAgeMonths: 5),
  MilestoneTemplate(category: 'Cognitive', title: 'Shows curiosity about things', expectedAgeMonths: 6),
  MilestoneTemplate(category: 'Cognitive', title: 'Tries to get things that are out of reach', expectedAgeMonths: 6),

  // Motor - 7-9 months
  MilestoneTemplate(category: 'Motor', title: 'Sits without support', expectedAgeMonths: 7),
  MilestoneTemplate(category: 'Motor', title: 'Stands holding on', expectedAgeMonths: 8),
  MilestoneTemplate(category: 'Motor', title: 'Crawling', expectedAgeMonths: 9),
  MilestoneTemplate(category: 'Motor', title: 'Picks up small objects with thumb and finger', expectedAgeMonths: 9),

  // Social - 7-9 months
  MilestoneTemplate(category: 'Social', title: 'May be afraid of strangers', expectedAgeMonths: 8),
  MilestoneTemplate(category: 'Social', title: 'Plays peek-a-boo', expectedAgeMonths: 9),
  MilestoneTemplate(category: 'Social', title: 'Has favorite toys', expectedAgeMonths: 8),

  // Language - 7-9 months
  MilestoneTemplate(category: 'Language', title: 'Understands "no"', expectedAgeMonths: 9),
  MilestoneTemplate(category: 'Language', title: 'Makes lots of different sounds (mamamama, bababababa)', expectedAgeMonths: 8),
  MilestoneTemplate(category: 'Language', title: 'Points at things', expectedAgeMonths: 9),

  // Cognitive - 7-9 months
  MilestoneTemplate(category: 'Cognitive', title: 'Looks for things you hide', expectedAgeMonths: 8),
  MilestoneTemplate(category: 'Cognitive', title: 'Watches the path of something as it falls', expectedAgeMonths: 7),
  MilestoneTemplate(category: 'Cognitive', title: 'Transfers things from one hand to other', expectedAgeMonths: 7),

  // Motor - 10-12 months
  MilestoneTemplate(category: 'Motor', title: 'Pulls up to stand', expectedAgeMonths: 10),
  MilestoneTemplate(category: 'Motor', title: 'Walks holding on to furniture (cruising)', expectedAgeMonths: 11),
  MilestoneTemplate(category: 'Motor', title: 'First steps without holding on', expectedAgeMonths: 12),
  MilestoneTemplate(category: 'Motor', title: 'Drinks from a cup without a lid', expectedAgeMonths: 12),

  // Social - 10-12 months
  MilestoneTemplate(category: 'Social', title: 'Waves bye-bye', expectedAgeMonths: 10),
  MilestoneTemplate(category: 'Social', title: 'Cries when parents leave', expectedAgeMonths: 10),
  MilestoneTemplate(category: 'Social', title: 'Plays simple back-and-forth games', expectedAgeMonths: 11),

  // Language - 10-12 months
  MilestoneTemplate(category: 'Language', title: 'Says "mama" or "dada" with meaning', expectedAgeMonths: 10),
  MilestoneTemplate(category: 'Language', title: 'First words (beyond mama/dada)', expectedAgeMonths: 11),
  MilestoneTemplate(category: 'Language', title: 'Tries to say words you say', expectedAgeMonths: 12),
  MilestoneTemplate(category: 'Language', title: 'Uses simple gestures like shaking head "no"', expectedAgeMonths: 12),

  // Cognitive - 10-12 months
  MilestoneTemplate(category: 'Cognitive', title: 'Puts things in a container', expectedAgeMonths: 10),
  MilestoneTemplate(category: 'Cognitive', title: 'Follows simple directions', expectedAgeMonths: 12),
  MilestoneTemplate(category: 'Cognitive', title: 'Explores things by banging and throwing', expectedAgeMonths: 11),
  MilestoneTemplate(category: 'Cognitive', title: 'Finds hidden things easily', expectedAgeMonths: 12),
];
