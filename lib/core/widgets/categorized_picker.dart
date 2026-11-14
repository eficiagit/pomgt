import 'motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';

String _norm(String value) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑ';
  const to = 'aaaaaeeeeiiiiooooouuuunAAAAAEEEEIIIIOOOOOUUUUN';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i == -1 ? ch : to[i].toLowerCase());
  }
  return buffer.toString();
}

// A query like "2 x 2" or "3.5x1" reads as a measurement, not independent
// keywords - split on whitespace it becomes ["2", "x", "2"], and matching
// each term as an unrelated substring anywhere in the row (SKU, name,
// category…) pulls in every row that merely contains a stray "2", not rows
// whose actual dimension is 2x2. These helpers recognize that shape of query
// and search for the combination itself instead.
final RegExp _dimensionQueryPattern = RegExp(
  r'^\d+(?:[.,]\d+)?(?:\s*[x×*]\s*\d+(?:[.,]\d+)?)+$',
  caseSensitive: false,
);
final RegExp _dimensionPairPattern = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*[x×*]\s*(\d+(?:[.,]\d+)?)',
  caseSensitive: false,
);
final RegExp _numberToken = RegExp(r'\d+(?:[.,]\d+)?');

/// Strips insignificant trailing zeros so "2.0000" and "2" - or "3.5000"
/// and "3.5" - compare as the same measurement.
String _normalizeDimensionNumber(String raw) {
  var n = raw.replaceAll(',', '.');
  if (n.contains('.')) {
    n = n.replaceFirst(RegExp(r'0+$'), '');
    n = n.replaceFirst(RegExp(r'\.$'), '');
  }
  return n;
}

/// Whether [query] is entirely a chain of numbers joined by x/×/* - a
/// measurement search such as "2 x 2" or "2.5x1x3" - rather than a mix of
/// ordinary search words.
bool _looksLikeDimensionQuery(String query) =>
    _dimensionQueryPattern.hasMatch(query.trim());

/// Whether [haystack] contains the same dimension [query] describes,
/// ignoring spacing, separator symbol and trailing zeros. A two-number query
/// also matches the reversed order ("2 x 3" finds "3 x 2"), since catalogs
/// aren't consistent about which side is width vs. height.
bool _haystackMatchesDimension(String haystack, String query) {
  final queryNumbers = query
      .trim()
      .split(RegExp(r'[xX×*]'))
      .map((p) => _normalizeDimensionNumber(p.trim()))
      .toList();
  if (queryNumbers.length == 2) {
    for (final match in _dimensionPairPattern.allMatches(haystack)) {
      final a = _normalizeDimensionNumber(match.group(1)!);
      final b = _normalizeDimensionNumber(match.group(2)!);
      if ((queryNumbers[0] == a && queryNumbers[1] == b) ||
          (queryNumbers[0] == b && queryNumbers[1] == a)) {
        return true;
      }
    }
    return false;
  }
  final normalizedHaystack = haystack.replaceAllMapped(
    _numberToken,
    (m) => _normalizeDimensionNumber(m.group(0)!),
  );
  final sequence = queryNumbers.map(RegExp.escape).join(r'\s*[xX×*]\s*');
  return RegExp(sequence).hasMatch(normalizedHaystack);
}

/// One selectable entry of a [CategorizedSearchPicker].
class PickerItem {
  const PickerItem({
    required this.id,
    required this.label,
    required this.category,
    this.subtitle,
  });

  final String id;
  final String label;
  final String category;
  final String? subtitle;
}

/// Search field whose dropdown groups the items by category.
///
/// With an empty search the categories are shown collapsed; tapping one opens
/// its items. Typing filters items (by label, subtitle or category) and opens
/// every category that still has matches.
class CategorizedSearchPicker extends StatefulWidget {
  const CategorizedSearchPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.label,
    this.hint = 'Buscar o elegir…',
    this.validator,
    this.emptyMessage = 'Sin resultados',
    this.enabled = true,
    this.helperText,
  });

  final List<PickerItem> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final String emptyMessage;
  final bool enabled;
  final String? helperText;

  @override
  State<CategorizedSearchPicker> createState() =>
      _CategorizedSearchPickerState();
}

class _CategorizedSearchPickerState extends State<CategorizedSearchPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _expanded = <String>{};
  bool _dismissed = false;

  PickerItem? get _selected {
    for (final item in widget.items) {
      if (item.id == widget.value) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = _selected?.label ?? '';
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant CategorizedSearchPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _controller.text = _selected?.label ?? '';
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _dismissed = false;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      // Leaving the field without choosing: show the current selection again.
      _controller.text = _selected?.label ?? '';
    }
  }

  bool get _searching {
    final text = _controller.text.trim();
    return text.isNotEmpty && text != (_selected?.label ?? '');
  }

  List<PickerItem> _filter(String text) {
    final selectedLabel = _selected?.label ?? '';
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == selectedLabel) return widget.items;
    if (_looksLikeDimensionQuery(trimmed)) {
      return widget.items
          .where(
            (item) => _haystackMatchesDimension(
              '${item.label} ${item.subtitle ?? ''} ${item.category}',
              trimmed,
            ),
          )
          .toList();
    }
    final query = _norm(trimmed);
    final terms = query.split(RegExp(r'\s+'));
    return widget.items.where((item) {
      final haystack = _norm(
        '${item.label} ${item.subtitle ?? ''} ${item.category}',
      );
      return terms.every(haystack.contains);
    }).toList();
  }

  void _reopen() {
    if (!_dismissed) return;
    _dismissed = false;
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return RawAutocomplete<PickerItem>(
          textEditingController: _controller,
          focusNode: _focus,
          optionsBuilder: (value) {
            final options = _filter(value.text);
            // Keep the overlay alive to show the "no results" message.
            return options.isEmpty
                ? const [PickerItem(id: '', label: '', category: '')]
                : options;
          },
          displayStringForOption: (item) => item.label,
          onSelected: (item) {
            if (item.id.isEmpty) return;
            _dismissed = true;
            widget.onChanged(item.id);
            _focus.unfocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return FormField<String>(
              initialValue: widget.value,
              validator: (_) => widget.validator?.call(widget.value),
              builder: (state) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: widget.enabled,
                  onTap: widget.enabled ? _reopen : null,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.hint,
                    error: state.errorText == null
                        ? null
                        : pomgtValidationMessage(context, state.errorText!),
                    helperText: widget.helperText,
                    helperMaxLines: 2,
                    prefixIcon: const Icon(LucideIcons.search, size: 17),
                    suffixIcon: widget.enabled
                        ? const Icon(
                            LucideIcons.chevronDown,
                            color: PomgtColors.muted,
                          )
                        : null,
                  ),
                );
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.where((o) => o.id.isNotEmpty).toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: PomgtReveal(
                  child: _PickerPanel(
                    width: width,
                    items: list,
                    selectedId: widget.value,
                    forceOpen: _searching,
                    expanded: _expanded,
                    emptyMessage: widget.emptyMessage,
                    onSelected: (item) => onSelected(item),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    required this.width,
    required this.items,
    required this.selectedId,
    required this.forceOpen,
    required this.expanded,
    required this.emptyMessage,
    required this.onSelected,
  });

  final double width;
  final List<PickerItem> items;
  final String? selectedId;
  final bool forceOpen;
  final Set<String> expanded;
  final String emptyMessage;
  final ValueChanged<PickerItem> onSelected;

  @override
  State<_PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<_PickerPanel> {
  @override
  void initState() {
    super.initState();
    // Reveal the category of the current selection when opening the list.
    for (final item in widget.items) {
      if (item.id == widget.selectedId) widget.expanded.add(item.category);
    }
    // Otherwise don't open on a stack of collapsed folders — expand
    // whichever category sorts first, same as the first one shown below.
    if (widget.expanded.isEmpty && widget.items.isNotEmpty) {
      final names = widget.items.map((e) => e.category).toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      widget.expanded.add(names.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<PickerItem>>{};
    for (final item in widget.items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Material(
      elevation: 6,
      color: PomgtColors.canvas,
      shadowColor: const Color(0x24152737),
      shape: const RoundedRectangleBorder(
        borderRadius: PomgtRadii.borderMd,
        side: BorderSide(color: PomgtColors.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.width,
          minWidth: widget.width,
          maxHeight: 380,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(PomgtRadii.md),
          child: names.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    widget.emptyMessage,
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 13,
                    ),
                  ),
                )
              : PomgtListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final name in names)
                      _CategorySection(
                        name: name,
                        items: groups[name]!,
                        open:
                            widget.forceOpen || widget.expanded.contains(name),
                        locked: widget.forceOpen,
                        selectedId: widget.selectedId,
                        onToggle: () => setState(() {
                          if (!widget.expanded.add(name)) {
                            widget.expanded.remove(name);
                          }
                        }),
                        onSelected: widget.onSelected,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.name,
    required this.items,
    required this.open,
    required this.locked,
    required this.selectedId,
    required this.onToggle,
    required this.onSelected,
  });

  final String name;
  final List<PickerItem> items;
  final bool open;
  final bool locked;
  final String? selectedId;
  final VoidCallback onToggle;
  final ValueChanged<PickerItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return PomgtAnimatedSize(
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      curve: PomgtMotion.curve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: locked ? null : onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    open ? LucideIcons.folderOpen : LucideIcons.folder,
                    size: 17,
                    color: PomgtColors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: PomgtColors.surfaceAlt,
                      borderRadius: BorderRadius.all(PomgtRadii.pillRadius),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? .25 : 0,
                    duration: PomgtMotion.duration(context, PomgtMotion.fast),
                    child: const Icon(
                      LucideIcons.chevronRight,
                      size: 14,
                      color: PomgtColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final item in items)
              InkWell(
                onTap: () => onSelected(item),
                child: AnimatedContainer(
                  duration: PomgtMotion.duration(context, PomgtMotion.fast),
                  curve: PomgtMotion.curve,
                  color: item.id == selectedId
                      ? PomgtColors.blueSoft
                      : Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(40, 9, 14, 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PomgtColors.ink,
                                fontSize: 13,
                              ),
                            ),
                            if (item.subtitle != null)
                              Text(
                                item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (item.id == selectedId)
                        const Icon(
                          LucideIcons.check,
                          size: 15,
                          color: PomgtColors.blue,
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Search field whose dropdown lets the user check off several items at
/// once, grouped by category. Checking an item keeps the dropdown open so
/// more can be picked in the same pass; the caller renders the running
/// selection itself (see the "Productos" step of the order wizard).
class MultiCategorizedPicker extends StatefulWidget {
  const MultiCategorizedPicker({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.onToggle,
    required this.label,
    this.hint = 'Buscar y marcar…',
    this.emptyMessage = 'Sin resultados',
  });

  final List<PickerItem> items;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final String label;
  final String hint;
  final String emptyMessage;

  @override
  State<MultiCategorizedPicker> createState() => _MultiCategorizedPickerState();
}

class _MultiCategorizedPickerState extends State<MultiCategorizedPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  // Groups the field and its overlay so Flutter treats a tap on either as
  // "inside": TextField's own default is to unfocus itself (closing the
  // overlay) on any tap it doesn't recognize as part of its own region,
  // which otherwise fires for every tap on the overlay since it lives in a
  // separate layer.
  final Object _groupId = Object();
  OverlayEntry? _entry;
  final _expanded = <String>{};

  void _toggleExpand(String name) {
    if (!_expanded.add(name)) _expanded.remove(name);
    _entry?.markNeedsBuild();
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant MultiCategorizedPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Checking a box updates state in the parent (to record the pick),
    // which rebuilds this widget while Flutter is still mid-build; the
    // overlay lives in a different part of the tree (the root Overlay), so
    // asking it to rebuild synchronously right here is illegal. Defer it to
    // the next frame instead.
    if (_entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _entry?.markNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width;
    // Open every category by default the first time this picker is used, so
    // it reads the same as before groups became collapsible; once the user
    // collapses one, that choice sticks across searches in this session.
    if (_expanded.isEmpty) {
      for (final item in widget.items) {
        _expanded.add(item.category);
      }
    }
    _entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: TapRegion(
            groupId: _groupId,
            child: PomgtReveal(
              child: _MultiPickerOverlay(
                width: width,
                controllerListenable: _controller,
                items: widget.items,
                selectedIds: widget.selectedIds,
                onToggle: widget.onToggle,
                emptyMessage: widget.emptyMessage,
                expanded: _expanded,
                onToggleExpand: _toggleExpand,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _groupId,
      onTapOutside: (_) => _focus.unfocus(),
      child: CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          // The TapRegion above already decides what counts as "outside";
          // suppress TextField's own default (unfocus on any tap it can't
          // see as part of itself), which would otherwise fire for every
          // tap on the overlay and close it before the tap registers.
          onTapOutside: (_) {},
          onChanged: (_) => _entry?.markNeedsBuild(),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(LucideIcons.search, size: 17),
            suffixIcon: const Icon(
              LucideIcons.chevronDown,
              color: PomgtColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiPickerOverlay extends StatelessWidget {
  const _MultiPickerOverlay({
    required this.width,
    required this.controllerListenable,
    required this.items,
    required this.selectedIds,
    required this.onToggle,
    required this.emptyMessage,
    required this.expanded,
    required this.onToggleExpand,
  });

  final double? width;
  final TextEditingController controllerListenable;
  final List<PickerItem> items;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final String emptyMessage;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controllerListenable,
      builder: (context, _) {
        final rawQuery = controllerListenable.text.trim();
        final query = _norm(rawQuery);
        final terms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
        final filtered = query.isEmpty
            ? items
            : _looksLikeDimensionQuery(rawQuery)
            ? items
                  .where(
                    (item) => _haystackMatchesDimension(
                      '${item.label} ${item.subtitle ?? ''} ${item.category}',
                      rawQuery,
                    ),
                  )
                  .toList()
            : items.where((item) {
                final haystack = _norm(
                  '${item.label} ${item.subtitle ?? ''} ${item.category}',
                );
                return terms.every(haystack.contains);
              }).toList();
        final groups = <String, List<PickerItem>>{};
        for (final item in filtered) {
          groups.putIfAbsent(item.category, () => []).add(item);
        }
        final names = groups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        // While searching, force every matching group open so results don't
        // hide behind a collapsed section the user has to notice and expand.
        final searching = query.isNotEmpty;

        // Without this, tapping a checkbox/row steals focus away from the
        // search field, which immediately closes this overlay before the
        // tap is even registered as a selection.
        return ExcludeFocus(
          child: Material(
            elevation: 6,
            color: PomgtColors.canvas,
            shadowColor: const Color(0x24152737),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtRadii.borderMd,
              side: BorderSide(color: PomgtColors.line),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width ?? 360,
                minWidth: width ?? 360,
                maxHeight: 340,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(PomgtRadii.md),
                child: names.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          emptyMessage,
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : PomgtListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        children: [
                          for (final name in names)
                            _MultiCategorySection(
                              name: name,
                              items: groups[name]!,
                              open: searching || expanded.contains(name),
                              locked: searching,
                              selectedIds: selectedIds,
                              onToggleExpand: () => onToggleExpand(name),
                              onToggle: onToggle,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A collapsible category group for [MultiCategorizedPicker], mirroring
/// [_CategorySection]'s accordion folder but with a checkbox per row instead
/// of single selection.
class _MultiCategorySection extends StatelessWidget {
  const _MultiCategorySection({
    required this.name,
    required this.items,
    required this.open,
    required this.locked,
    required this.selectedIds,
    required this.onToggleExpand,
    required this.onToggle,
  });

  final String name;
  final List<PickerItem> items;
  final bool open;
  final bool locked;
  final Set<String> selectedIds;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return PomgtAnimatedSize(
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      curve: PomgtMotion.curve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: locked ? null : onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    open ? LucideIcons.folderOpen : LucideIcons.folder,
                    size: 17,
                    color: PomgtColors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: PomgtColors.surfaceAlt,
                      borderRadius: BorderRadius.all(PomgtRadii.pillRadius),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? .25 : 0,
                    duration: PomgtMotion.duration(context, PomgtMotion.fast),
                    child: const Icon(
                      LucideIcons.chevronRight,
                      size: 14,
                      color: PomgtColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final item in items)
              InkWell(
                onTap: () => onToggle(item.id),
                child: AnimatedContainer(
                  duration: PomgtMotion.duration(context, PomgtMotion.fast),
                  curve: PomgtMotion.curve,
                  color: selectedIds.contains(item.id)
                      ? PomgtColors.blueSoft
                      : Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(26, 8, 14, 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: selectedIds.contains(item.id),
                        onChanged: (_) => onToggle(item.id),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PomgtColors.ink,
                                fontSize: 13,
                              ),
                            ),
                            if (item.subtitle != null)
                              Text(
                                item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
