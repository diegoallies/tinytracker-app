import 'care_pack_data.dart';

/// Citations for medical information shown outside the Care Guide
/// (Apple guideline 1.4.1: all medical info must cite its source).
///
/// Every URL here was verified live before shipping. Screens show these as
/// tappable source lines next to the medical content they back.
class MedicalSources {
  /// Fever bands used on the Health screen and in the PDF reports.
  /// NHS: 38°C or more is a high temperature; 39°C+ warrants medical
  /// advice for young babies.
  static const CareSource fever = CareSource(
    publisher: 'NHS',
    title: 'High temperature (fever) in children',
    url: 'https://www.nhs.uk/symptoms/fever-in-children/',
  );

  /// Backs the as-needed dose cap and minimum-gap warnings
  /// (both pages: max 4 doses in 24 hours, minimum 4 hours between doses).
  static const CareSource paracetamol = CareSource(
    publisher: 'NHS',
    title: 'Paracetamol for children',
    url: 'https://www.nhs.uk/medicines/paracetamol-for-children/',
  );

  static const CareSource ibuprofen = CareSource(
    publisher: 'NHS',
    title: 'Ibuprofen for children',
    url: 'https://www.nhs.uk/medicines/ibuprofen-for-children/',
  );

  /// Stool scale shown in the diaper logger (shared with the Care Guide).
  static const CareSource stools = CareSource(
    publisher: 'NHS',
    title: 'Diarrhoea and vomiting',
    url: 'https://www.nhs.uk/conditions/diarrhoea-and-vomiting/',
  );

  /// Expected-age groupings on the Milestones screen.
  static const CareSource milestones = CareSource(
    publisher: 'CDC',
    title: "Learn the Signs. Act Early. - developmental milestones",
    url: 'https://www.cdc.gov/act-early/milestones/index.html',
  );

  /// The vaccine schedule tracked on the Immunisations screen.
  static const CareSource saEpi = CareSource(
    publisher: 'South African National Department of Health',
    title: 'Expanded Programme on Immunisation (EPI) schedule',
    url: 'https://www.health.gov.za/',
  );

  /// Shown under AI-generated summaries and insights.
  static const String aiDisclaimer =
      'AI-generated from your own logged data. Not medical advice - '
      'speak to your doctor or clinic about any health concerns.';
}
