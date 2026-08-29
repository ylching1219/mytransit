import 'dart:async';

import 'package:flutter/material.dart';

const kInk = Color(0xFF193140);
const kMuted = Color(0xFF7E9299);
const kMutedDark = Color(0xFF60767D);
const kBackground = Color(0xFFF4F8F7);
const kBorder = Color(0xFFE0EBE8);
const kTeal = Color(0xFF1D8D83);
const kTealSoft = Color(0xFFE2F4EE);
const kPurple = Color(0xFF6852AE);
const kPurpleSoft = Color(0xFFF0EAFB);
const kPeach = Color(0xFFFFE9E1);
const kYellow = Color(0xFFFFF4CF);

Color appFieldSurface(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF24363A)
      : Colors.white;
}

Color appFieldBorder(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF4A6166)
      : kBorder;
}

Color appCardColor(BuildContext context, Color lightColor) {
  if (Theme.of(context).brightness != Brightness.dark) return lightColor;
  if (lightColor == Colors.white) return const Color(0xFF1E2C30);
  if (lightColor == kBackground) return const Color(0xFF101A1D);
  if (lightColor == kTealSoft) return const Color(0xFF16413E);
  if (lightColor == kPurpleSoft) return const Color(0xFF30264D);
  if (lightColor == kPeach) return const Color(0xFF4A302D);
  if (lightColor == kYellow) return const Color(0xFF493B1C);
  return lightColor;
}

DateTime malaysiaNow() {
  return DateTime.now().toUtc().add(const Duration(hours: 8));
}

String greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 19) return 'Good evening';
  return 'Good night';
}

class AppHeader extends StatefulWidget {
  final String title;
  final String? greetingName;
  final String avatarLabel;

  const AppHeader({
    required this.title,
    this.greetingName,
    this.avatarLabel = 'AK',
    super.key,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = malaysiaNow();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = malaysiaNow());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _dateLabel(DateTime date) {
    const weekdays = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  String _timeLabel(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final headerTitle = widget.greetingName == null
        ? widget.title
        : '${greetingForHour(_now.hour)}, ${widget.greetingName}';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 17, 7, 0),
      child: Row(
        children: [
          AvatarChip(size: 31, label: widget.avatarLabel),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_dateLabel(_now)} · ${_timeLabel(_now)}',
                style: KickerStyle.small.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                headerTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const Spacer(),
          Icon(
            Icons.notifications_none_rounded,
            size: 19,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class AvatarChip extends StatelessWidget {
  final double size;
  final String label;

  const AvatarChip({this.size = 32, this.label = 'AK', super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8D79E),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFECC27E)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C8E988D),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * .27,
          color: kInk,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String avatarInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'G';
  if (words.length == 1) {
    final word = words.first;
    return (word.length > 1 ? word.substring(0, 2) : word).toUpperCase();
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}

class KickerStyle {
  static const small = TextStyle(
    fontSize: 8,
    letterSpacing: 1.2,
    color: kMuted,
    fontWeight: FontWeight.w800,
  );

  static const regular = TextStyle(
    fontSize: 9,
    letterSpacing: 1.15,
    color: kMuted,
    fontWeight: FontWeight.w800,
  );
}

class PageTitle extends StatelessWidget {
  final String kicker;
  final String title;
  final Widget? trailing;

  const PageTitle({
    required this.kicker,
    required this.title,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker,
                style: KickerStyle.regular.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 21,
                  height: 1.05,
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionHeading({
    required this.title,
    this.trailing,
    this.onTrailingTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Text(
              trailing!,
              style: const TextStyle(
                fontSize: 9,
                color: kPurple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  const SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = Colors.white,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.brightness == Brightness.dark
        ? const Color(0xFF35484C)
        : kBorder;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark
                ? const Color(0x40000000)
                : const Color(0x100A373B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const AppBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const items = [
      (Icons.home_outlined, 'Home'),
      (Icons.alt_route_rounded, 'Plan'),
      (Icons.bookmark_outline_rounded, 'Saved'),
      (Icons.person_outline_rounded, 'Profile'),
    ];
    return Container(
      height: 61,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(index),
                child: NavItem(
                  icon: items[index].$1,
                  label: items[index].$2,
                  selected: selectedIndex == index,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 57,
          height: 31,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kPurpleSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? kPurple : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            color: selected ? kPurple : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
