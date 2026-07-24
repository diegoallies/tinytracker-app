/// Static South African EPI (Expanded Programme on Immunisation) schedule,
/// grouped by clinic visit age. Pure data: no Flutter imports so it stays
/// unit-testable, mirroring care_pack_data.dart.
///
/// Source: South African National Department of Health EPI schedule
/// (https://www.health.gov.za/) - cited in-app via MedicalSources.saEpi.
///
/// Vaccine keys are stored in immunisations.vaccine_key - never change a key
/// once shipped.
library;

class VaccineItem {
  /// Stable id stored in immunisations.vaccine_key.
  final String key;
  final String name;
  final String description;

  const VaccineItem(this.key, this.name, this.description);
}

class ImmunisationVisit {
  /// Human label for the visit ('Birth', '6 weeks', '6 months', ...).
  final String ageLabel;

  /// Due age in weeks after birth (months converted at ~4.345 weeks/month).
  final int dueWeeks;

  final List<VaccineItem> vaccines;

  const ImmunisationVisit({
    required this.ageLabel,
    required this.dueWeeks,
    required this.vaccines,
  });
}

abstract final class ImmunisationData {
  static const List<ImmunisationVisit> schedule = [
    ImmunisationVisit(
      ageLabel: 'Birth',
      dueWeeks: 0,
      vaccines: [
        VaccineItem('bcg', 'BCG', 'Protects against tuberculosis'),
        VaccineItem('opv0', 'OPV (0)', 'Oral polio vaccine, birth dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '6 weeks',
      dueWeeks: 6,
      vaccines: [
        VaccineItem('opv1', 'OPV (1)', 'Oral polio vaccine, 1st dose'),
        VaccineItem('hexa1', 'Hexavalent (1)',
            'DTaP-IPV-Hib-HepB combined vaccine, 1st dose'),
        VaccineItem('pcv1', 'PCV (1)', 'Pneumococcal vaccine, 1st dose'),
        VaccineItem('rv1', 'Rotavirus (1)', 'Rotavirus vaccine, 1st dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '10 weeks',
      dueWeeks: 10,
      vaccines: [
        VaccineItem('hexa2', 'Hexavalent (2)',
            'DTaP-IPV-Hib-HepB combined vaccine, 2nd dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '14 weeks',
      dueWeeks: 14,
      vaccines: [
        VaccineItem('hexa3', 'Hexavalent (3)',
            'DTaP-IPV-Hib-HepB combined vaccine, 3rd dose'),
        VaccineItem('pcv2', 'PCV (2)', 'Pneumococcal vaccine, 2nd dose'),
        VaccineItem('rv2', 'Rotavirus (2)', 'Rotavirus vaccine, 2nd dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '6 months',
      dueWeeks: 26, // 6 × 4.345 weeks
      vaccines: [
        VaccineItem('measles1', 'Measles (1)', 'Measles vaccine, 1st dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '9 months',
      dueWeeks: 39, // 9 × 4.345 weeks
      vaccines: [
        VaccineItem('pcv3', 'PCV (3)', 'Pneumococcal vaccine, 3rd dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '12 months',
      dueWeeks: 52, // 12 × 4.345 weeks
      vaccines: [
        VaccineItem('measles2', 'Measles (2)', 'Measles vaccine, 2nd dose'),
      ],
    ),
    ImmunisationVisit(
      ageLabel: '18 months',
      dueWeeks: 78, // 18 × 4.345 weeks
      vaccines: [
        VaccineItem('hexa4', 'Hexavalent (4)',
            'DTaP-IPV-Hib-HepB booster dose'),
      ],
    ),
  ];

  /// Total number of vaccines across the whole schedule.
  static int get totalVaccines =>
      schedule.fold(0, (sum, v) => sum + v.vaccines.length);

  /// Due date for [visit] given a date of birth. Day-component arithmetic,
  /// not Duration math - DST-safe (matches weekStartOf in care_pack_provider).
  static DateTime dueDateFor(ImmunisationVisit visit, DateTime dateOfBirth) {
    return DateTime(
      dateOfBirth.year,
      dateOfBirth.month,
      dateOfBirth.day + visit.dueWeeks * 7,
    );
  }
}
