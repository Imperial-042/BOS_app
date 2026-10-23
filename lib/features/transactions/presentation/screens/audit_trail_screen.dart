// lib/features/audit/presentation/screens/audit_trail_screen.dart
//
// Audit Trail viewer: filters (date range, user, module, action type,
// affected record) + event details with before/after changes.
// Read-only by design: there is no edit or delete affordance anywhere.
//
// Design notes
//  - Events are grouped by day so the list reads as a timeline.
//  - Every action type owns one colour + icon; the same pair is used in the
//    list, the tags and the detail sheet, so a red tile always means
//    "something was removed".
//  - Before/after changes render as a field-by-field diff (red -> green)
//    instead of a spreadsheet, and creates/deletes show a plain value list.

import 'dart:async';
import 'dart:convert';

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_repository.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────
// Formatting helpers
// ─────────────────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _time(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _dayLabel(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  if (_sameDay(l, now)) return 'Today';
  if (_sameDay(l, DateTime(now.year, now.month, now.day - 1))) {
    return 'Yesterday';
  }
  final base = '${_weekdays[l.weekday - 1]}, ${l.day} ${_months[l.month - 1]}';
  return l.year == now.year ? base : '$base ${l.year}';
}

String _fullStamp(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}, ${_time(l)}';
}

/// 'finance.supplier_purchase_recorded' -> 'Supplier purchase recorded'.
String _humanAction(String action) {
  final verb = action.contains('.')
      ? action.substring(action.indexOf('.') + 1)
      : action;
  final spaced = verb.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return action;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// 'startingBalance' / 'starting_balance' -> 'Starting balance'.
String _humanField(String key) {
  final spaced = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

final _moneyKey = RegExp(
  r'(amount|total|price|balance|cash|variance|gross|cost|outstandingBefore)$',
  caseSensitive: false,
);

bool _isMoneyKey(String? key) => key != null && _moneyKey.hasMatch(key);

/// Writers store money as integer cents; show it as pesos.
String _fmtMoney(num cents) {
  final negative = cents < 0;
  final total = cents.abs().round();
  final whole = (total ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final frac = (total % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}₱$whole.$frac';
}

String _fmtValue(Object? v, {String? key}) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is num) {
    if (!v.isFinite) return '$v';
    if (_isMoneyKey(key)) return _fmtMoney(v);
    if (v is int) return '$v';
    // Hides floating-point noise such as 0.30000000000000004.
    final r = double.parse(v.toStringAsFixed(4));
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }
  if (v is String) {
    if (v.isEmpty) return '—';
    if (v.length >= 19 && v.contains('T')) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return _fullStamp(parsed);
    }
    return v;
  }
  if (v is Map || v is List) return jsonEncode(v);
  return '$v';
}

Map<String, Object?> _decodeMap(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final v = jsonDecode(json);
    return v is Map ? Map<String, Object?>.from(v) : {'value': v};
  } on FormatException {
    return {'value': json};
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

// ─────────────────────────────────────────────────────────────
// Visual language: one colour + icon per action type / module
// ─────────────────────────────────────────────────────────────

class _TypeStyle {
  const _TypeStyle(this.icon, this.color);
  final IconData icon;
  final Color color;
}

_TypeStyle _styleFor(AuditActionType? t) => switch (t) {
  AuditActionType.create => const _TypeStyle(
    Icons.add_circle_outline_rounded,
    Color(0xFF2E9E6B),
  ),
  AuditActionType.update => const _TypeStyle(
    Icons.edit_outlined,
    Color(0xFF3B82F6),
  ),
  AuditActionType.delete => const _TypeStyle(
    Icons.delete_outline_rounded,
    Color(0xFFE5484D),
  ),
  AuditActionType.voided => const _TypeStyle(
    Icons.block_rounded,
    Color(0xFFF59E0B),
  ),
  AuditActionType.refund => const _TypeStyle(
    Icons.assignment_return_outlined,
    Color(0xFF8B5CF6),
  ),
  AuditActionType.adjustment => const _TypeStyle(
    Icons.tune_rounded,
    Color(0xFFC77700),
  ),
  AuditActionType.permission => const _TypeStyle(
    Icons.verified_user_outlined,
    Color(0xFF0EA5A4),
  ),
  AuditActionType.export => const _TypeStyle(
    Icons.file_download_outlined,
    Color(0xFF6366F1),
  ),
  AuditActionType.security => const _TypeStyle(
    Icons.shield_outlined,
    Color(0xFFEF6C3E),
  ),
  null => const _TypeStyle(Icons.history_rounded, Color(0xFF8A8F98)),
};

IconData _moduleIcon(AuditModule? m) => switch (m) {
  AuditModule.finance => Icons.account_balance_wallet_outlined,
  AuditModule.inventory => Icons.inventory_2_outlined,
  AuditModule.sales => Icons.point_of_sale_outlined,
  AuditModule.people => Icons.people_outline_rounded,
  AuditModule.administration => Icons.settings_outlined,
  AuditModule.security => Icons.shield_outlined,
  null => Icons.folder_outlined,
};

const _avatarPalette = [
  Color(0xFF3B82F6),
  Color(0xFF2E9E6B),
  Color(0xFF8B5CF6),
  Color(0xFFE5484D),
  Color(0xFF0EA5A4),
  Color(0xFFC77700),
];

Color _avatarColor(String seed) =>
    _avatarPalette[seed.hashCode.abs() % _avatarPalette.length];

// ─────────────────────────────────────────────────────────────
// Date presets
// ─────────────────────────────────────────────────────────────

enum _DatePreset {
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days'),
  custom('Pick a range…');

  const _DatePreset(this.label);
  final String label;
}

(DateTime, DateTime) _presetRange(_DatePreset p) {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return switch (p) {
    _DatePreset.today => (DateTime(now.year, now.month, now.day), tomorrow),
    _DatePreset.week => (DateTime(now.year, now.month, now.day - 6), tomorrow),
    _DatePreset.month => (
      DateTime(now.year, now.month, now.day - 29),
      tomorrow,
    ),
    _DatePreset.custom => (DateTime(now.year, now.month, now.day), tomorrow),
  };
}

/// Wraps a picked value so "Any" (null) can be told apart from "dismissed".
class _Choice<T> {
  const _Choice(this.value);
  final T? value;
}

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────

class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  AuditFilter _filter = const AuditFilter();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  int get _activeFilters =>
      (_filter.from != null ? 1 : 0) +
      (_filter.userId != null ? 1 : 0) +
      (_filter.module != null ? 1 : 0) +
      (_filter.actionType != null ? 1 : 0) +
      (_filter.query.trim().isNotEmpty ? 1 : 0);

  void _clearAll() {
    _debounce?.cancel();
    setState(() {
      _search.clear();
      _filter = const AuditFilter();
    });
  }

  // ── pickers ────────────────────────────────────────────────

  Future<_Choice<T>?> _pick<T extends Object>({
    required String title,
    required String anyLabel,
    required Map<T, String> items,
    required T? selected,
    IconData? Function(T value)? iconFor,
  }) {
    return showModalBottomSheet<_Choice<T>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.layers_clear_outlined),
                        title: Text(anyLabel),
                        trailing: selected == null
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(ctx, _Choice<T>(null)),
                      ),
                      for (final e in items.entries)
                        ListTile(
                          leading: iconFor?.call(e.key) == null
                              ? null
                              : Icon(iconFor!(e.key)),
                          title: Text(e.value),
                          trailing: e.key == selected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, _Choice<T>(e.key)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final choice = await _pick<_DatePreset>(
      title: 'Date',
      anyLabel: 'Any date',
      selected: _currentPreset(),
      items: {for (final p in _DatePreset.values) p: p.label},
    );
    if (choice == null || !mounted) return;

    final preset = choice.value;
    if (preset == null) {
      setState(() {
        _filter = _filter.copyWith(from: () => null, toExclusive: () => null);
      });
      return;
    }
    if (preset == _DatePreset.custom) {
      await _pickCustomRange();
      return;
    }
    final (from, to) = _presetRange(preset);
    setState(() {
      _filter = _filter.copyWith(from: () => from, toExclusive: () => to);
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _filter.from == null || _filter.toExclusive == null
          ? null
          : DateTimeRange(
              start: _filter.from!,
              end: _filter.toExclusive!.subtract(const Duration(days: 1)),
            ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filter = _filter.copyWith(
        from: () => _startOfDay(picked.start),
        toExclusive: () =>
            DateTime(picked.end.year, picked.end.month, picked.end.day + 1),
      );
    });
  }

  _DatePreset? _currentPreset() {
    final from = _filter.from;
    final to = _filter.toExclusive;
    if (from == null || to == null) return null;
    for (final p in const [
      _DatePreset.today,
      _DatePreset.week,
      _DatePreset.month,
    ]) {
      final (f, t) = _presetRange(p);
      if (f == from && t == to) return p;
    }
    return _DatePreset.custom;
  }

  String get _dateLabel {
    final from = _filter.from;
    final to = _filter.toExclusive;
    if (from == null || to == null) return 'Any date';
    final preset = _currentPreset();
    if (preset != null && preset != _DatePreset.custom) return preset.label;
    final last = to.subtract(const Duration(days: 1));
    return _sameDay(from, last)
        ? _shortDate(from)
        : '${_shortDate(from)} – ${_shortDate(last)}';
  }

  Future<void> _pickUser(List<AuditActor> actors) async {
    final choice = await _pick<String>(
      title: 'Who made the change',
      anyLabel: 'Anyone',
      selected: _filter.userId,
      items: {for (final a in actors) a.userId: a.name},
    );
    if (choice == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(userId: () => choice.value));
  }

  Future<void> _pickModule() async {
    final choice = await _pick<AuditModule>(
      title: 'Module',
      anyLabel: 'All modules',
      selected: _filter.module,
      items: {for (final m in AuditModule.values) m: m.label},
      iconFor: _moduleIcon,
    );
    if (choice == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(module: () => choice.value));
  }

  Future<void> _pickAction() async {
    final choice = await _pick<AuditActionType>(
      title: 'Type of action',
      anyLabel: 'All actions',
      selected: _filter.actionType,
      items: {for (final a in AuditActionType.values) a: a.label},
      iconFor: (a) => _styleFor(a).icon,
    );
    if (choice == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(actionType: () => choice.value));
  }

  // ── build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authorizationServiceProvider);
    if (!auth.can(AuditRepository.viewPermission)) {
      return const _CenteredMessage(
        icon: Icons.lock_outline_rounded,
        title: 'Audit trail is restricted',
        message:
            'Your role can\'t view the audit trail. Ask the business '
            'owner if you need access.',
      );
    }

    final events = ref.watch(auditEventsProvider(_filter));
    final actors = ref.watch(auditActorsProvider).value ?? const [];
    final actorName = actors
        .where((a) => a.userId == _filter.userId)
        .map((a) => a.name)
        .firstOrNull;

    return Column(
      children: [
        _FilterBar(
          search: _search,
          onSearchChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) {
                setState(() => _filter = _filter.copyWith(query: v));
              }
            });
          },
          onSearchCleared: () {
            _debounce?.cancel();
            setState(() {
              _search.clear();
              _filter = _filter.copyWith(query: '');
            });
          },
          pills: [
            _Pill(
              icon: Icons.calendar_today_outlined,
              label: _dateLabel,
              active: _filter.from != null,
              onTap: _pickDate,
            ),
            _Pill(
              icon: Icons.person_outline_rounded,
              label: actorName ?? 'Anyone',
              active: _filter.userId != null,
              onTap: () => _pickUser(actors),
            ),
            _Pill(
              icon: _moduleIcon(_filter.module),
              label: _filter.module?.label ?? 'All modules',
              active: _filter.module != null,
              onTap: _pickModule,
            ),
            _Pill(
              icon: _styleFor(_filter.actionType).icon,
              label: _filter.actionType?.label ?? 'All actions',
              active: _filter.actionType != null,
              color: _filter.actionType == null
                  ? null
                  : _styleFor(_filter.actionType).color,
              onTap: _pickAction,
            ),
          ],
          activeCount: _activeFilters,
          onClear: _clearAll,
        ),
        Expanded(
          child: events.when(
            loading: () => const _SkeletonList(),
            error: (e, _) => _CenteredMessage(
              icon: Icons.error_outline_rounded,
              title: 'Couldn\'t load the audit trail',
              message: '$e',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(auditEventsProvider(_filter)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return _CenteredMessage(
                  icon: _activeFilters == 0
                      ? Icons.history_toggle_off_rounded
                      : Icons.search_off_rounded,
                  title: _activeFilters == 0
                      ? 'No activity recorded yet'
                      : 'No events match these filters',
                  message: _activeFilters == 0
                      ? 'Changes to money, stock, people and security '
                            'settings will show up here as they happen.'
                      : 'Try a wider date range or remove a filter.',
                  actionLabel: _activeFilters == 0 ? null : 'Clear filters',
                  onAction: _activeFilters == 0 ? null : _clearAll,
                );
              }
              return _EventList(
                rows: rows,
                limit: _filter.limit,
                onRefresh: () async {
                  ref.invalidate(auditEventsProvider(_filter));
                  ref.invalidate(auditActorsProvider);
                },
                onOpen: (r) => _showDetails(context, r),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context, AuditLog r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (context, controller) =>
            _AuditDetails(row: r, controller: controller),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.pills,
    required this.activeCount,
    required this.onClear,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final List<Widget> pills;
  final int activeCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: search,
            builder: (context, value, _) => TextField(
              controller: search,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by record name, type or id',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: onSearchCleared,
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.primary, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in pills)
                  Padding(padding: const EdgeInsets.only(right: 8), child: p),
                if (activeCount > 0)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: Text('Clear ($activeCount)'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Material(
      color: active
          ? accent.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? accent.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? accent : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? accent : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: active ? accent : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Event list (summary + day-grouped timeline)
// ─────────────────────────────────────────────────────────────

class _Summary {
  const _Summary(this.total, this.today, this.removals, this.security);

  factory _Summary.from(List<AuditLog> rows) {
    final now = DateTime.now();
    var today = 0, removals = 0, security = 0;
    for (final r in rows) {
      if (_sameDay(r.createdAt.toLocal(), now)) today++;
      final t = AuditActionType.fromId(r.actionType);
      if (t == AuditActionType.delete ||
          t == AuditActionType.voided ||
          t == AuditActionType.refund) {
        removals++;
      }
      if (t == AuditActionType.security ||
          t == AuditActionType.permission ||
          AuditModule.fromId(r.module) == AuditModule.security) {
        security++;
      }
    }
    return _Summary(rows.length, today, removals, security);
  }

  final int total;
  final int today;
  final int removals;
  final int security;
}

class _DayHeader {
  const _DayHeader(this.label, this.count);
  final String label;
  final int count;
}

class _EventList extends StatelessWidget {
  const _EventList({
    required this.rows,
    required this.limit,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<AuditLog> rows;
  final int limit;
  final Future<void> Function() onRefresh;
  final ValueChanged<AuditLog> onOpen;

  List<Object> _items() {
    final counts = <String, int>{};
    String keyOf(DateTime d) {
      final l = d.toLocal();
      return '${l.year}-${l.month}-${l.day}';
    }

    for (final r in rows) {
      counts.update(keyOf(r.createdAt), (n) => n + 1, ifAbsent: () => 1);
    }

    final items = <Object>[_Summary.from(rows)];
    String? last;
    for (final r in rows) {
      final k = keyOf(r.createdAt);
      if (k != last) {
        items.add(_DayHeader(_dayLabel(r.createdAt), counts[k] ?? 0));
        last = k;
      }
      items.add(r);
    }
    if (rows.length >= limit) items.add(limit);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          if (item is _Summary) return _SummaryCard(summary: item);
          if (item is _DayHeader) return _DayHeaderTile(header: item);
          if (item is AuditLog) {
            return _EventCard(row: item, onTap: () => onOpen(item));
          }
          return _LimitNote(limit: item as int);
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.heroGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Audit trail',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'A read-only record of who changed what.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(value: summary.total, label: 'Events'),
                _Stat(value: summary.today, label: 'Today'),
                _Stat(value: summary.removals, label: 'Removals'),
                _Stat(value: summary.security, label: 'Security'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeaderTile extends StatelessWidget {
  const _DayHeaderTile({required this.header});
  final _DayHeader header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Text(
            header.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${header.count} ${header.count == 1 ? 'event' : 'events'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitNote extends StatelessWidget {
  const _LimitNote({required this.limit});
  final int limit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Showing the latest $limit events. Use the filters above to '
                'reach older ones.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Event card
// ─────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({required this.row, required this.onTap});

  final AuditLog row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = AuditActionType.fromId(row.actionType);
    final module = AuditModule.fromId(row.module);
    final style = _styleFor(type);
    final who = row.actorName ?? row.userId;
    final hasReason = (row.reason ?? '').trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeTile(style: style, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.entityLabel ??
                            '${row.entityType} ${row.entityId ?? ''}'.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _humanAction(row.action),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Tag(
                            label: type?.label ?? 'Event',
                            color: style.color,
                          ),
                          _Tag(
                            label: module?.label ?? 'Other',
                            icon: _moduleIcon(module),
                            color: scheme.onSurfaceVariant,
                          ),
                          if (hasReason)
                            _Tag(
                              label: 'Reason given',
                              icon: Icons.chat_bubble_outline_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _Avatar(name: who, size: 20),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              row.actorRole == null
                                  ? who
                                  : '$who (${row.actorRole})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _time(row.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.outline,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.style, required this.size});
  final _TypeStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(style.icon, color: style.color, size: size * 0.5),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Loading / empty / error states
// ─────────────────────────────────────────────────────────────

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      itemCount: 6,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(150, 14),
                  const SizedBox(height: 8),
                  bar(110, 11),
                  const SizedBox(height: 12),
                  bar(180, 11),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Detail sheet
// ─────────────────────────────────────────────────────────────

class _AuditDetails extends StatelessWidget {
  const _AuditDetails({required this.row, required this.controller});

  final AuditLog row;
  final ScrollController controller;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = AuditActionType.fromId(row.actionType);
    final module = AuditModule.fromId(row.module);
    final style = _styleFor(type);
    final who = row.actorName ?? row.userId;

    final before = _decodeMap(row.beforeJson);
    final after = _decodeMap(row.afterJson);
    final keys = {...before.keys, ...after.keys}.toList()..sort();
    final details = _decodeMap(row.details);
    final reason = (row.reason ?? '').trim();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    Widget section(String title, {String? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    Widget infoRow(String label, String? value, {bool copyable = false}) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (copyable)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _copy(context, value),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget card(List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 32 + bottomInset),
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TypeTile(style: style, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _humanAction(row.action),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.entityLabel ?? row.entityType,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag(label: type?.label ?? 'Event', color: style.color),
                      _Tag(
                        label: module?.label ?? row.module ?? 'Other',
                        icon: _moduleIcon(module),
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Who + when
        const SizedBox(height: 20),
        card([
          Row(
            children: [
              _Avatar(name: who, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      who,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (row.actorRole != null)
                      Text(
                        row.actorRole!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          infoRow('When', _fullStamp(row.createdAt)),
          infoRow('Device', row.deviceId, copyable: true),
        ]),

        // Reason
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: Color(0xFFC77700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason given',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC77700),
                        ),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(reason),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Changes
        if (keys.isNotEmpty) ...[
          if (before.isEmpty)
            section('Recorded values', trailing: '${keys.length} fields')
          else if (after.isEmpty)
            section('Values at removal', trailing: '${keys.length} fields')
          else
            section(
              'What changed',
              trailing:
                  '${keys.length} ${keys.length == 1 ? 'field' : 'fields'}',
            ),
          if (before.isEmpty || after.isEmpty)
            card([
              for (final k in keys)
                infoRow(
                  _humanField(k),
                  _fmtValue(before.isEmpty ? after[k] : before[k], key: k),
                ),
            ])
          else
            for (final k in keys)
              _DiffTile(
                field: _humanField(k),
                fieldKey: k,
                hasBefore: before.containsKey(k),
                before: before[k],
                hasAfter: after.containsKey(k),
                after: after[k],
              ),
        ],

        // Record
        section('Affected record'),
        card([
          infoRow('Name', row.entityLabel),
          infoRow('Type', row.entityType),
          infoRow('Record id', row.entityId, copyable: true),
        ]),

        // Extra details
        if (details.isNotEmpty) ...[
          section('More details'),
          card([
            for (final e in details.entries)
              infoRow(_humanField(e.key), _fmtValue(e.value, key: e.key)),
          ]),
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 2),
              title: const Text(
                'Raw JSON',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(details),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Footer
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: scheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Audit events can\'t be edited or deleted.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _copy(context, row.id),
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Copy event id'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiffTile extends StatelessWidget {
  const _DiffTile({
    required this.field,
    required this.fieldKey,
    required this.hasBefore,
    required this.before,
    required this.hasAfter,
    required this.after,
  });

  final String field;
  final String fieldKey;
  final bool hasBefore;
  final Object? before;
  final bool hasAfter;
  final Object? after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const red = Color(0xFFE5484D);
    const green = Color(0xFF2E9E6B);

    Widget box({
      required bool present,
      required String text,
      required String emptyText,
      required Color color,
      required bool strike,
    }) {
      final muted = !present;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (muted ? scheme.outline : color).withValues(
            alpha: muted ? 0.08 : 0.12,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          muted ? emptyText : text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            color: muted ? scheme.onSurfaceVariant : color,
            decoration: strike && !muted ? TextDecoration.lineThrough : null,
            decorationColor: color,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              field,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: box(
                    present: hasBefore,
                    text: _fmtValue(before, key: fieldKey),
                    emptyText: 'Not set',
                    color: red,
                    strike: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: scheme.outline,
                  ),
                ),
                Expanded(
                  child: box(
                    present: hasAfter,
                    text: _fmtValue(after, key: fieldKey),
                    emptyText: 'Removed',
                    color: green,
                    strike: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
