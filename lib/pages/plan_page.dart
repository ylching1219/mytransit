import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_page.dart';
import 'route_results_page.dart';
import '../providers/app_state.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';

class PlanPage extends StatefulWidget {
  final ValueChanged<String> onMessage;

  const PlanPage({required this.onMessage, super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final FocusNode _fromFocusNode;
  late final FocusNode _toFocusNode;
  TimeOfDay? _departureTime;
  bool _findingNearby = false;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(text: 'Current location');
    _toController = TextEditingController(text: 'Pasar Seni');
    _fromController.addListener(_onLocationTextChanged);
    _toController.addListener(_onLocationTextChanged);
    _fromFocusNode = FocusNode();
    _toFocusNode = FocusNode();
    _fromFocusNode.addListener(_closeToSuggestionsWhenFromFocuses);
    _toFocusNode.addListener(_closeFromSuggestionsWhenToFocuses);
  }

  @override
  void dispose() {
    _fromController.removeListener(_onLocationTextChanged);
    _toController.removeListener(_onLocationTextChanged);
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.removeListener(_closeToSuggestionsWhenFromFocuses);
    _toFocusNode.removeListener(_closeFromSuggestionsWhenToFocuses);
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }

  void _onLocationTextChanged() {
    if (mounted) setState(() {});
  }

  void _closeToSuggestionsWhenFromFocuses() {
    if (_fromFocusNode.hasFocus) _toFocusNode.unfocus();
  }

  void _closeFromSuggestionsWhenToFocuses() {
    if (_toFocusNode.hasFocus) _fromFocusNode.unfocus();
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Enter a location' : null;
  }

  Future<Iterable<TransitPlaceSuggestion>> _placeSuggestions(
    TextEditingController controller,
    String value,
  ) async {
    final query = value.trim();
    if (query.length < 2) return const [];

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || controller.text.trim() != query) return const [];

    final suggestions = await context.read<AppState>().searchTransitSuggestions(
      query: query,
    );
    if (!mounted || controller.text.trim() != query) return const [];
    return suggestions;
  }

  Future<void> _chooseDepartureTime() async {
    FocusScope.of(context).unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: _departureTime ?? _currentMalaysiaTime(),
      helpText: 'Show departures after',
    );
    if (picked == null || !mounted) return;
    setState(() => _departureTime = picked);
  }

  Future<bool> _chooseNearbyStartingStop() async {
    if (_findingNearby) return false;
    FocusScope.of(context).unfocus();
    setState(() => _findingNearby = true);

    try {
      final state = context.read<AppState>();
      final location = await state.getCurrentLocation();
      if (!mounted) return false;
      if (location?.latitude == null || location?.longitude == null) {
        widget.onMessage(
          'Turn on GPS and allow location access to find nearby stops.',
        );
        return false;
      }

      final nearbyStops = await state.findNearbyTransitStops(
        latitude: location!.latitude!,
        longitude: location.longitude!,
      );
      if (!mounted) return false;
      if (nearbyStops.isEmpty) {
        widget.onMessage('No transit stop was found within 1.5 km.');
        return false;
      }

      final selected = await showModalBottomSheet<NearbyTransitStop>(
        context: context,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        isScrollControlled: true,
        builder: (sheetContext) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .58,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Choose a nearby stop',
                            style: TextStyle(
                              fontSize: 16,
                              color: kInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: kMutedDark,
                        ),
                      ],
                    ),
                    const Text(
                      'Based on your current GPS location',
                      style: TextStyle(fontSize: 10, color: kMutedDark),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: nearbyStops.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 7),
                        itemBuilder: (_, index) {
                          final stop = nearbyStops[index];
                          return SoftCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: InkWell(
                              onTap: () => Navigator.of(sheetContext).pop(stop),
                              borderRadius: BorderRadius.circular(10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: stop.mode.contains('Bus')
                                          ? kTealSoft
                                          : kPurpleSoft,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      stop.mode.contains('Bus')
                                          ? Icons.directions_bus_filled_rounded
                                          : Icons.train_rounded,
                                      size: 16,
                                      color: stop.mode.contains('Bus')
                                          ? kTeal
                                          : kPurple,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stop.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: kInk,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${stop.mode} · ${_formatDistance(stop.distanceMeters)} away',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: kMutedDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: kMuted,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (!mounted || selected == null) return false;
      _fromController.text = selected.name;
      return true;
    } catch (error) {
      if (mounted) {
        widget.onMessage(
          error is TransitDataException
              ? error.message
              : 'Could not read your current location.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _findingNearby = false);
    }
  }

  Future<void> _findRoutes() async {
    if (_fromController.text.trim().toLowerCase() == 'current location') {
      final selected = await _chooseNearbyStartingStop();
      if (!selected || !mounted) return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = context.read<AppState>();
    final departureTime = _departureTime;
    final found = await state.planJourney(
      from: _fromController.text,
      to: _toController.text,
      departureAfterSeconds: departureTime == null
          ? null
          : departureTime.hour * 60 * 60 + departureTime.minute * 60,
      departureBeforeSeconds: departureTime == null
          ? null
          : departureTime.hour * 60 * 60 + departureTime.minute * 60 + 30 * 60,
    );
    if (!mounted) return;
    if (!found) {
      widget.onMessage(
        state.transitError ?? 'No direct route was found for these stops.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteResultsPage(
          from: _fromController.text.trim(),
          to: _toController.text.trim(),
          departureTimeLabel: departureTime == null
              ? null
              : _timeOfDayLabel(departureTime),
        ),
      ),
    );
  }

  void _resetPlan() {
    FocusScope.of(context).unfocus();
    _fromController.text = 'Current location';
    _toController.text = 'Pasar Seni';
    setState(() => _departureTime = null);
    context.read<AppState>().resetJourneySearch();
    _formKey.currentState?.reset();
    widget.onMessage('Journey search reset');
  }

  String _timeOfDayLabel(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  TimeOfDay _currentMalaysiaTime() {
    final now = malaysiaNow();
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }

  Future<void> _saveFavoriteRoute() async {
    final state = context.read<AppState>();
    if (state.isGuest) {
      widget.onMessage('Please sign in to save favourite routes');
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    if (_fromController.text.trim().toLowerCase() == 'current location') {
      final selected = await _chooseNearbyStartingStop();
      if (!selected || !mounted) return;
    }

    if (state.isFavoriteRouteSaved(
      from: _fromController.text,
      to: _toController.text,
    )) {
      widget.onMessage('This route is already saved');
      return;
    }

    final saved = await state.saveFavoriteRoute(
      from: _fromController.text,
      to: _toController.text,
    );
    if (!mounted) return;
    if (saved) {
      widget.onMessage('Favourite route saved');
    } else if (state.isFavoriteRouteSaved(
      from: _fromController.text,
      to: _toController.text,
    )) {
      widget.onMessage('This route is already saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final routeAlreadySaved =
        !state.isGuest &&
        state.isFavoriteRouteSaved(
          from: _fromController.text,
          to: _toController.text,
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              title: 'Plan',
              avatarLabel: avatarInitials(state.profileName),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: PageTitle(
                    kicker: 'PLAN A JOURNEY',
                    title: 'Find your best route',
                    trailing: Text(
                      '1 of 2',
                      style: TextStyle(
                        fontSize: 9,
                        color: kMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            RouteField(
              label: 'STARTING FROM',
              controller: _fromController,
              validator: _required,
              icon: Icons.my_location_rounded,
              iconColor: kTeal,
              iconBackground: kTealSoft,
              subtitle: _findingNearby
                  ? 'Finding the closest transit stops...'
                  : _fromController.text.trim().toLowerCase() ==
                        'current location'
                  ? 'Tap the location icon to find a nearby stop'
                  : 'Selected transit stop · tap the icon to change',
              trailingIcon: Icons.my_location_rounded,
              onTrailingTap: _chooseNearbyStartingStop,
              focusNode: _fromFocusNode,
              suggestionsBuilder: (value) =>
                  _placeSuggestions(_fromController, value),
            ),
            const SizedBox(height: 7),
            RouteField(
              label: 'GOING TO',
              controller: _toController,
              validator: _required,
              icon: Icons.location_on_outlined,
              iconColor: const Color(0xFFD46C68),
              iconBackground: kPeach,
              trailingIcon: Icons.search_rounded,
              focusNode: _toFocusNode,
              suggestionsBuilder: (value) =>
                  _placeSuggestions(_toController, value),
            ),
            const SizedBox(height: 7),
            DepartureTimeField(
              timeLabel: _departureTime == null
                  ? 'Any time'
                  : _timeOfDayLabel(_departureTime!),
              onTap: _chooseDepartureTime,
              onClear: _departureTime == null
                  ? null
                  : () => setState(() => _departureTime = null),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton.icon(
                onPressed: state.isSearching ? null : _findRoutes,
                icon: Icon(
                  state.isSearching
                      ? Icons.hourglass_top_rounded
                      : Icons.alt_route_rounded,
                  size: 15,
                ),
                label: Text(
                  state.isSearching
                      ? 'Finding routes...'
                      : 'Find available routes',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: kPurple,
                  disabledBackgroundColor: const Color(0xFF9A8BC9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: routeAlreadySaved
                          ? () =>
                                widget.onMessage('This route is already saved')
                          : _saveFavoriteRoute,
                      icon: Icon(
                        routeAlreadySaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 15,
                      ),
                      label: Text(
                        routeAlreadySaved
                            ? 'Route already saved'
                            : state.isGuest
                            ? 'Sign in to save route'
                            : 'Save as favourite route',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPurple,
                        side: const BorderSide(color: kPurple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                SizedBox(
                  width: 82,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: state.isSearching ? null : _resetPlan,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Reset',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTeal,
                      side: const BorderSide(color: kTeal),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                if (!state.permissionGranted) {
                  await state.requestLocationPermission();
                }
                if (!state.gpsEnabled) await state.requestGps();
              },
              child: const Center(
                child: Text(
                  'Location access helps us estimate walking time.',
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DepartureTimeField extends StatelessWidget {
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const DepartureTimeField({
    required this.timeLabel,
    required this.onTap,
    this.onClear,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        color: appFieldSurface(context),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kYellow,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: Color(0xFFB08B2F),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DEPART AT',
                    style: KickerStyle.small.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    timeLabel == 'Any time'
                        ? 'Show all scheduled routes'
                        : 'Show scheduled routes within the next 30 minutes',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 17),
                color: kMutedDark,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              )
            else
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class RouteField extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final FocusNode? focusNode;
  final Future<Iterable<TransitPlaceSuggestion>> Function(String)?
  suggestionsBuilder;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const RouteField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.subtitle,
    this.trailingIcon,
    this.onTrailingTap,
    this.focusNode,
    this.suggestionsBuilder,
    this.validator,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      color: appFieldSurface(context),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: KickerStyle.small.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _LocationInput(
                  controller: controller,
                  focusNode: focusNode,
                  validator: validator,
                  suggestionsBuilder: suggestionsBuilder,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailingIcon != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  trailingIcon,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.controller,
    required this.focusNode,
    required this.validator,
    required this.suggestionsBuilder,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final Future<Iterable<TransitPlaceSuggestion>> Function(String)?
  suggestionsBuilder;

  TextStyle _inputStyle(BuildContext context) => TextStyle(
    fontSize: 10,
    color: Theme.of(context).colorScheme.onSurface,
    fontWeight: FontWeight.w900,
  );

  InputDecoration get _inputDecoration => const InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    errorStyle: TextStyle(fontSize: 8.5),
  );

  @override
  Widget build(BuildContext context) {
    if (suggestionsBuilder == null) {
      return TextFormField(
        controller: controller,
        validator: validator,
        style: _inputStyle(context),
        decoration: _inputDecoration,
      );
    }

    return Autocomplete<TransitPlaceSuggestion>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (option) => option.title,
      optionsBuilder: (textEditingValue) =>
          suggestionsBuilder!(textEditingValue.text),
      onSelected: (option) {
        controller.value = TextEditingValue(
          text: option.title,
          selection: TextSelection.collapsed(offset: option.title.length),
        );
        focusNode?.unfocus();
      },
      optionsMaxHeight: 210,
      optionsViewBuilder: (context, onSelected, options) {
        final theme = Theme.of(context);
        final optionList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 5,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 30,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 5),
                shrinkWrap: true,
                itemCount: optionList.length,
                separatorBuilder: (_, index) => Divider(
                  height: 1,
                  indent: 44,
                  endIndent: 10,
                  color: theme.dividerColor,
                ),
                itemBuilder: (_, index) {
                  final option = optionList[index];
                  final isPlace = option.mode == 'Place';
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isPlace ? kPeach : kPurpleSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPlace
                                  ? Icons.place_outlined
                                  : Icons.train_rounded,
                              size: 15,
                              color: isPlace
                                  ? const Color(0xFFD46C68)
                                  : kPurple,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${option.mode} · ${option.subtitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.north_east_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          onTapOutside: (_) => focusNode.unfocus(),
          validator: validator,
          onFieldSubmitted: (_) => onSubmitted(),
          style: _inputStyle(context),
          decoration: _inputDecoration,
        );
      },
    );
  }
}

String _formatDistance(double distanceMeters) {
  if (distanceMeters >= 1000) {
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
  return '${distanceMeters.round()} m';
}
