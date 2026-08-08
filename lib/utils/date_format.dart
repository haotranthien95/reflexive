const List<String> _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a timestamp as `Aug 7, 2:45 PM` — the shape the UI contract asks
/// for on history rows and the session-detail title.
///
/// Hand-written rather than pulling in `intl`: the app needs exactly one
/// format and no localisation in this milestone.
String formatSessionTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = _kMonths[local.month - 1];
  final hour24 = local.hour;
  final meridiem = hour24 < 12 ? 'AM' : 'PM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, $hour12:$minute $meridiem';
}
