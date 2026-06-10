/// UI display names for the sharing roles. The DATABASE values stay
/// owner/parent/logger/viewer - this is presentation only (Diego, 2026-06-10).
///
/// Capabilities follow the DB role, not the label:
///   owner  -> Parent  (full control)
///   parent -> Family  (log entries + give medicine)
///   logger -> Nanny   (log entries, no medicine)
///   viewer -> Viewer  (read-only)
library;

String roleDisplayName(String role) => switch (role.toLowerCase()) {
      'owner' => 'Parent',
      'parent' => 'Family',
      'logger' => 'Nanny',
      'viewer' => 'Viewer',
      _ => role,
    };
