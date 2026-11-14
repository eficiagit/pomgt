import 'dart:math' as math;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/organization_controller.dart';
import '../../features/bom/bom_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/floor_map/floor_map_screen.dart';
import '../../features/master_data/master_data_screen.dart';
import '../../features/materials/materials_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/production/production_screen.dart';
import '../../features/products/products_screen.dart';
import '../../features/roles/roles_screen.dart';
import '../../features/routings/routings_screen.dart';
import '../../features/schema/schema_coverage_screen.dart';
import '../theme/pomgt_theme.dart';
import 'motion.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();
    final narrow = MediaQuery.sizeOf(context).width < 980;
    return Scaffold(
      drawer: narrow
          ? const Drawer(width: 306, child: _Sidebar(forceExpanded: true))
          : null,
      body: Stack(
        children: [
          Container(
            color: PomgtColors.appBg,
            child: Row(
              children: [
                if (!narrow) const _Sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      if (nav.section != AppSection.dashboard)
                        const _TopBar(showMenu: false),
                      Expanded(
                        child: SoftContentSwitch(
                          child: KeyedSubtree(
                            key: ValueKey(nav.section),
                            child: _body(nav.section),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (narrow) const _MobileNavButton(),
        ],
      ),
    );
  }

  Widget _body(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return const DashboardScreen();
      case AppSection.customers:
        return const CustomersScreen();
      case AppSection.orders:
        return const OrdersScreen();
      case AppSection.products:
        return const ProductsScreen();
      case AppSection.materials:
        return const MaterialsScreen();
      case AppSection.bom:
        return const BomScreen();
      case AppSection.routings:
        return const RoutingsScreen();
      case AppSection.production:
        return const ProductionScreen();
      case AppSection.floorMap:
        return const FloorMapScreen();
      case AppSection.documents:
        return const DocumentsScreen();
      case AppSection.masterData:
        return const MasterDataScreen();
      case AppSection.roles:
        return const RolesScreen();
      case AppSection.schema:
        return const SchemaCoverageScreen();
    }
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 0),
          child: Builder(
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: PomgtColors.canvas,
                borderRadius: PomgtRadii.borderSm,
                border: Border.all(color: PomgtColors.line),
              ),
              child: IconButton(
                tooltip: 'Abrir navegación',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(LucideIcons.panelLeft, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenu});
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationController>().organization;
    final user = context.watch<AuthController>().user;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 640;
    return Container(
      height: compact ? 64 : 82,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 32),
      decoration: const BoxDecoration(
        color: PomgtColors.canvas,
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Abrir navegación',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(LucideIcons.panelLeft, size: 20),
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
          ],
          const Spacer(),
          if (org != null && !compact)
            Tooltip(
              message: 'Organización activa. Todos los registros mostrados pertenecen a esta empresa.',
              child: Text(
                org['display_name']?.toString() ?? 'Organización',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: PomgtColors.ink,
                ),
              ),
            ),
          SizedBox(width: compact ? 8 : 18),
          PopupMenuButton<String>(
            popUpAnimationStyle: PomgtMotion.style(context),
            tooltip: 'Cuenta',
            offset: const Offset(0, 42),
            onSelected: (value) {
              if (value == 'logout') {
                context.read<AuthController>().signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (MediaQuery.sizeOf(context).width - 40).clamp(
                      0.0,
                      220.0,
                    ),
                  ),
                  child: Text(
                    user?.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PomgtColors.muted),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(LucideIcons.logOut, size: 18),
                    SizedBox(width: 10),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: Container(
              decoration: BoxDecoration(
                color: PomgtColors.blueSoft,
                borderRadius: PomgtRadii.borderSm,
                border: Border.all(color: PomgtColors.navySelectedBorder),
              ),
              width: 38,
              height: 38,
              child: Center(
                child: Text(
                  _initials(user?.email),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PomgtColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String? email) {
    if (email == null || email.isEmpty) return 'U';
    return email.substring(0, 1).toUpperCase();
  }
}

/// A nav item nested inside a [_NavGroupSpec], or the group header itself
/// when used standalone (Inicio).
class _NavItemSpec {
  const _NavItemSpec({
    required this.section,
    required this.icon,
    required this.label,
  });
  final AppSection section;
  final IconData icon;
  final String label;
}

/// A collapsible sidebar section, e.g. "Ventas" grouping Clientes y
/// Pedidos. Only rendered as a nested, collapsible group when the sidebar
/// is expanded — the icon-only collapsed rail stays a flat list since
/// there's no room to show a header there anyway.
class _NavGroupSpec {
  const _NavGroupSpec({
    required this.label,
    required this.icon,
    required this.items,
  });
  final String label;
  final IconData icon;
  final List<_NavItemSpec> items;
}

// Mixes standalone items (e.g. Producción, now that it's the only item left
// in what used to be its own group) with collapsible groups, in display
// order. Each entry is either a [_NavItemSpec] or a [_NavGroupSpec].
const _navEntries = <Object>[
  _NavGroupSpec(
    label: 'Ventas',
    icon: LucideIcons.tag,
    items: [
      _NavItemSpec(
        section: AppSection.customers,
        icon: LucideIcons.building2,
        label: 'Clientes',
      ),
      _NavItemSpec(
        section: AppSection.orders,
        icon: LucideIcons.fileText,
        label: 'Pedidos',
      ),
    ],
  ),
  _NavGroupSpec(
    label: 'Catálogo',
    icon: LucideIcons.layers,
    items: [
      _NavItemSpec(
        section: AppSection.products,
        icon: LucideIcons.box,
        label: 'Productos',
      ),
      _NavItemSpec(
        section: AppSection.materials,
        icon: LucideIcons.layers,
        label: 'Materiales',
      ),
      _NavItemSpec(
        section: AppSection.bom,
        icon: LucideIcons.layers,
        label: 'Estructuras de fabricación',
      ),
      _NavItemSpec(
        section: AppSection.routings,
        icon: LucideIcons.gitBranch,
        label: 'Rutas de fabricación',
      ),
    ],
  ),
  _NavItemSpec(
    section: AppSection.production,
    icon: LucideIcons.settings,
    label: 'Producción',
  ),
  _NavItemSpec(
    section: AppSection.floorMap,
    icon: LucideIcons.map,
    label: 'Mapa de planta',
  ),
  _NavGroupSpec(
    label: 'Sistema',
    icon: LucideIcons.slidersHorizontal,
    items: [
      _NavItemSpec(
        section: AppSection.documents,
        icon: LucideIcons.folder,
        label: 'Documentos',
      ),
      _NavItemSpec(
        section: AppSection.masterData,
        icon: LucideIcons.slidersHorizontal,
        label: 'Datos maestros',
      ),
      _NavItemSpec(
        section: AppSection.roles,
        icon: LucideIcons.shield,
        label: 'Roles y auditoría',
      ),
      _NavItemSpec(
        section: AppSection.schema,
        icon: LucideIcons.circleCheck,
        label: 'Cobertura',
      ),
    ],
  ),
];

class _Sidebar extends StatefulWidget {
  const _Sidebar({this.forceExpanded = false});
  final bool forceExpanded;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  // Groups the user has manually collapsed. Empty by default: every group
  // starts open, and clicking a header toggles it from there.
  final Set<String> _collapsedGroups = {};

  @override
  Widget build(BuildContext context) {
    final forceExpanded = widget.forceExpanded;
    final nav = context.watch<NavigationController>();
    final collapsed = forceExpanded ? false : nav.sidebarCollapsed;
    final width = collapsed ? 82.0 : 300.0;
    return AnimatedContainer(
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      curve: PomgtMotion.curve,
      width: width,
      decoration: const BoxDecoration(
        color: PomgtColors.canvas,
        border: Border(right: BorderSide(color: PomgtColors.line)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 82,
              child: collapsed
                  ? Center(
                      child: Tooltip(
                        message: 'Expandir navegación',
                        child: InkWell(
                          borderRadius: PomgtRadii.borderSm,
                          onTap: nav.toggleSidebar,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: PomgtColors.canvas,
                              borderRadius: PomgtRadii.borderSm,
                            ),
                            child: const Center(
                              child: _SidebarLogo(collapsed: true),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: const BoxDecoration(
                              color: PomgtColors.canvas,
                              borderRadius: PomgtRadii.borderSm,
                            ),
                            child: const _SidebarLogo(collapsed: false),
                          ),
                          const Spacer(),
                          if (!forceExpanded)
                            IconButton(
                              tooltip: 'Contraer navegación',
                              onPressed: nav.toggleSidebar,
                              icon: const Icon(
                                LucideIcons.panelLeft,
                                size: 18,
                                color: PomgtColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: PomgtListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _NavItem(
                    section: AppSection.dashboard,
                    icon: LucideIcons.panelsTopLeft,
                    label: 'Inicio',
                    collapsed: collapsed,
                  ),
                  const SizedBox(height: 6),
                  if (collapsed)
                    for (final entry in _navEntries)
                      if (entry is _NavGroupSpec)
                        for (final item in entry.items)
                          _NavItem(
                            section: item.section,
                            icon: item.icon,
                            label: item.label,
                            collapsed: true,
                          )
                      else if (entry is _NavItemSpec)
                        _NavItem(
                          section: entry.section,
                          icon: entry.icon,
                          label: entry.label,
                          collapsed: true,
                        ),
                  if (!collapsed)
                    for (final entry in _navEntries)
                      if (entry is _NavGroupSpec)
                        _NavGroup(
                          group: entry,
                          expanded: !_collapsedGroups.contains(entry.label),
                          activeSection: nav.section,
                          onToggle: () => setState(() {
                            if (!_collapsedGroups.add(entry.label)) {
                              _collapsedGroups.remove(entry.label);
                            }
                          }),
                        )
                      else if (entry is _NavItemSpec)
                        _NavItem(
                          section: entry.section,
                          icon: entry.icon,
                          label: entry.label,
                          collapsed: false,
                        ),
                ],
              ),
            ),
            if (!collapsed)
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 12, 28, 26),
                child: Text(
                  'Production Order Management',
                  style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible sidebar section: a clickable header (icon, label, chevron)
/// followed by its indented, guide-lined children when expanded.
class _NavGroup extends StatelessWidget {
  const _NavGroup({
    required this.group,
    required this.expanded,
    required this.activeSection,
    required this.onToggle,
  });
  final _NavGroupSpec group;
  final bool expanded;
  final AppSection activeSection;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = group.items.any((i) => i.section == activeSection);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavItemFrame(
            icon: group.icon,
            label: group.label,
            collapsed: false,
            // Never "selected" like a leaf item — the active child already
            // carries the full treatment, and the chevron below communicates
            // the group's own open/closed state. Two elements sharing the
            // same emphasis reads as two different "current page" signals.
            // Collapsed, though, the active child is hidden — a light-blue
            // background (no accent bar/bold text) says "it's in here".
            selected: false,
            subtleActive: active && !expanded,
            onTap: onToggle,
            trailing: AnimatedRotation(
              duration: PomgtMotion.duration(context, PomgtMotion.fast),
              turns: expanded ? 0.25 : 0,
              child: const Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: PomgtColors.muted,
              ),
            ),
          ),
          PomgtAnimatedSize(
            duration: PomgtMotion.duration(context, PomgtMotion.medium),
            curve: PomgtMotion.curve,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              duration: PomgtMotion.duration(context, PomgtMotion.medium),
              curve: PomgtMotion.curve,
              opacity: expanded ? 1 : 0,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 27),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: PomgtColors.line),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Column(
                            children: [
                              for (final item in group.items)
                                _NavItem(
                                  section: item.section,
                                  icon: item.icon,
                                  label: item.label,
                                  collapsed: false,
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: collapsed ? 44 : 152,
      height: collapsed ? 30 : 48,
      child: const Image(
        image: AssetImage('assets/POMGT-LOGO.png'),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.icon,
    required this.label,
    required this.collapsed,
  });
  final AppSection section;
  final IconData icon;
  final String label;
  final bool collapsed;
  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();
    final selected = nav.section == section;
    void onTap() {
      context.read<NavigationController>().go(section);
      if (!collapsed && Scaffold.maybeOf(context)?.hasDrawer == true) {
        Navigator.maybePop(context);
      }
    }

    if (collapsed) {
      final content = _NavItemFrame(
        icon: icon,
        collapsed: true,
        selected: selected,
        onTap: onTap,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Tooltip(message: label, child: content),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _NavItemFrame(
        icon: icon,
        label: label,
        collapsed: false,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

/// A nav row's interaction chrome and selection animation. Deliberately has
/// no hover visual at all (just the pointer cursor) — selection is the only
/// state worth signaling, shown as a sliding accent (expanded) or a soft
/// glow behind the icon (collapsed rail), plus a color/weight morph and a
/// small sine "pop" on the icon as it transitions. No filled background, no
/// border: one lightweight cue instead of four competing ones.
class _NavItemFrame extends StatefulWidget {
  const _NavItemFrame({
    required this.icon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.label,
    this.trailing,
    this.subtleActive = false,
  });

  final IconData icon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final String? label;
  final Widget? trailing;

  /// A quieter cue than [selected]: a light-blue background with no accent
  /// bar or bold text, for a collapsed group whose active child is hidden
  /// inside it — so "your page is in here" still reads without duplicating
  /// the child's own full selected treatment.
  final bool subtleActive;

  @override
  State<_NavItemFrame> createState() => _NavItemFrameState();
}

class _NavItemFrameState extends State<_NavItemFrame> {
  bool _pressed = false;
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: PomgtRadii.borderSm,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          focusColor: PomgtColors.blueSoft,
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (mounted) setState(() => _pressed = value);
          },
          child: AnimatedScale(
            scale: _pressed ? .96 : 1,
            duration: PomgtMotion.duration(context, PomgtMotion.fast),
            curve: PomgtMotion.curve,
            child: Stack(
              children: [
                // Each background is its own layer animating only its own
                // alpha against a fixed RGB — stacking them (rather than
                // swapping one `color` between different RGBs, or against
                // Colors.transparent) avoids any muddy cross-fade.
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: PomgtMotion.duration(context, PomgtMotion.medium),
                    curve: PomgtMotion.curve,
                    decoration: BoxDecoration(
                      color: PomgtColors.navySelected.withValues(
                        alpha: widget.subtleActive ? 1 : 0,
                      ),
                      borderRadius: PomgtRadii.borderSm,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: PomgtMotion.duration(context, PomgtMotion.fast),
                  curve: PomgtMotion.curve,
                  decoration: BoxDecoration(
                    color: PomgtColors.surfaceAlt.withValues(
                      alpha: _hovered ? 1 : 0,
                    ),
                    borderRadius: PomgtRadii.borderSm,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: widget.selected ? 1.0 : 0.0),
                    duration: PomgtMotion.duration(context, PomgtMotion.slow),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => widget.collapsed
                        ? _collapsedContent(t)
                        : _expandedContent(t),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(double t, {double size = 20}) {
    final color = Color.lerp(PomgtColors.navIcon, PomgtColors.blueHover, t)!;
    final pop = 1 + 0.14 * math.sin(t * math.pi);
    return Transform.scale(
      scale: pop,
      child: Icon(widget.icon, size: size, color: color),
    );
  }

  Widget _collapsedContent(double t) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 38 * (.6 + .4 * t),
              height: 38 * (.6 + .4 * t),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PomgtColors.blueSoft.withValues(alpha: t),
              ),
            ),
            _icon(t),
          ],
        ),
      ),
    );
  }

  Widget _expandedContent(double t) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 70) {
          return SizedBox(height: 48, child: Center(child: _icon(t)));
        }
        return SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 10,
                child: Center(
                  child: Transform.scale(
                    scaleY: t,
                    child: Container(
                      width: 3,
                      height: 22,
                      decoration: BoxDecoration(
                        color: PomgtColors.blueHover,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              _icon(t),
              const SizedBox(width: 14),
              if (widget.label != null)
                Expanded(
                  child: Text(
                    widget.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.lerp(
                        FontWeight.w500,
                        FontWeight.w600,
                        t,
                      ),
                      color: Color.lerp(
                        PomgtColors.ink,
                        PomgtColors.blueHover,
                        t,
                      ),
                    ),
                  ),
                ),
              if (widget.trailing != null) widget.trailing!,
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }
}
