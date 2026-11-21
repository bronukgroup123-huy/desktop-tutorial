import 'json.dart';
import 'me.dart';

/// Вибір готового аватара (`GET v1-me?avatars=1`, ADR-021 §21.7): що відкрито, а що ні і чому —
/// вирішує сервер; картинки — у застосунку (`assets/avatars/<id>.webp`).
class AvatarChoice {
  const AvatarChoice({required this.id, required this.title, required this.role, required this.open});

  factory AvatarChoice.fromJson(Map<String, dynamic> j) => AvatarChoice(
        id: req<String>(j, 'id'),
        title: opt<String>(j, 'title') ?? '',
        role: opt<String>(j, 'role') ?? '',
        open: opt<bool>(j, 'open') ?? false,
      );

  final String id;
  final String title;
  final String role;
  final bool open;
}

class AvatarGroup {
  const AvatarGroup({required this.level, required this.label, required this.open, this.lockLabel, this.avatars = const []});

  factory AvatarGroup.fromJson(Map<String, dynamic> j) => AvatarGroup(
        level: req<String>(j, 'level'),
        label: opt<String>(j, 'label') ?? '',
        open: opt<bool>(j, 'open') ?? false,
        lockLabel: opt<String>(j, 'lock_label'),
        avatars: [for (final a in opt<List<dynamic>>(j, 'avatars') ?? const []) AvatarChoice.fromJson(a as Map<String, dynamic>)],
      );

  final String level;
  final String label;
  final bool open;
  final String? lockLabel;
  final List<AvatarChoice> avatars;
}

class AvatarChoices {
  const AvatarChoices({required this.current, required this.canChange, this.reasonLabel, this.groups = const []});

  factory AvatarChoices.fromJson(Map<String, dynamic> j) => AvatarChoices(
        current: opt<Map<String, dynamic>>(j, 'current') == null ? const Avatar() : Avatar.fromJson(opt<Map<String, dynamic>>(j, 'current')!),
        canChange: opt<bool>(j, 'can_change') ?? false,
        reasonLabel: opt<String>(j, 'reason_label'),
        groups: [for (final g in opt<List<dynamic>>(j, 'groups') ?? const []) AvatarGroup.fromJson(g as Map<String, dynamic>)],
      );

  final Avatar current;
  final bool canChange;
  final String? reasonLabel;
  final List<AvatarGroup> groups;
}
