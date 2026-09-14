import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/organization_controller.dart';
import '../../features/bom/bom_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/master_data/master_data_screen.dart';
import '../../features/materials/materials_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/production/production_screen.dart';
import '../../features/products/products_screen.dart';
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
      body: Container(
        color: PomgtColors.appBg,
        child: Row(
          children: [
            if (!narrow) const _Sidebar(),
            Expanded(
              child: Column(
                children: [
                  if (nav.section != AppSection.dashboard)
                    _TopBar(showMenu: narrow),
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
      case AppSection.documents:
        return const DocumentsScreen();
      case AppSection.masterData:
        return const MasterDataScreen();
      case AppSection.schema:
        return const SchemaCoverageScreen();
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenu});
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationController>().organization;
    final user = context.watch<AuthController>().user;
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        border: const Border(bottom: BorderSide(color: PomgtColors.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Abrir navegación',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(CupertinoIcons.sidebar_left, size: 20),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          const SizedBox(width: 16),
          if (org != null)
            Tooltip(
              message:
                  'Organización activa. Todos los registros mostrados pertenecen a esta empresa.',
              child: Text(
                org['display_name']?.toString() ?? 'Organización',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: PomgtColors.ink,
                ),
              ),
            ),
          const SizedBox(width: 18),
          PopupMenuButton<String>(
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
                child: SizedBox(
                  width: 220,
                  child: Text(
                    user?.email ?? '',
                    style: const TextStyle(color: PomgtColors.muted),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.square_arrow_right, size: 18),
                    SizedBox(width: 10),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: SizedBox(
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({this.forceExpanded = false});
  final bool forceExpanded;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();
    final collapsed = forceExpanded ? false : nav.sidebarCollapsed;
    final width = collapsed ? 82.0 : 300.0;
    return AnimatedContainer(
      duration: PomgtMotion.medium,
      curve: PomgtMotion.curve,
      width: width,
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        border: Border(right: const BorderSide(color: PomgtColors.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
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
                                CupertinoIcons.sidebar_left,
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
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _NavItem(
                    section: AppSection.dashboard,
                    icon: CupertinoIcons.rectangle_grid_2x2,
                    label: 'Inicio',
                    collapsed: collapsed,
                  ),
                  if (!collapsed) const _NavLabel('OPERACIÓN'),
                  _NavItem(
                    section: AppSection.customers,
                    icon: CupertinoIcons.building_2_fill,
                    label: 'Clientes',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.orders,
                    icon: CupertinoIcons.doc_plaintext,
                    label: 'Pedidos',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.products,
                    icon: CupertinoIcons.cube_box,
                    label: 'Productos',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.materials,
                    icon: CupertinoIcons.layers,
                    label: 'Materiales',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.bom,
                    icon: CupertinoIcons.square_stack_3d_up,
                    label: 'Estructuras de fabricación',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.routings,
                    icon: CupertinoIcons.arrow_branch,
                    label: 'Rutas de fabricación',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.production,
                    icon: CupertinoIcons.gear_alt,
                    label: 'Producción',
                    collapsed: collapsed,
                  ),
                  if (!collapsed) const _NavLabel('SISTEMA'),
                  _NavItem(
                    section: AppSection.documents,
                    icon: CupertinoIcons.folder,
                    label: 'Documentos',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.masterData,
                    icon: CupertinoIcons.slider_horizontal_3,
                    label: 'Datos maestros',
                    collapsed: collapsed,
                  ),
                  _NavItem(
                    section: AppSection.schema,
                    icon: CupertinoIcons.check_mark_circled,
                    label: 'Cobertura',
                    collapsed: collapsed,
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

class _NavLabel extends StatelessWidget {
  const _NavLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: PomgtColors.muted,
      ),
    ),
  );
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
        collapsed: true,
        selected: selected,
        onTap: onTap,
        builder: (context, hovered) => Icon(
          icon,
          size: 20,
          color: selected
              ? PomgtColors.canvas
              : hovered
              ? PomgtColors.blue
              : PomgtColors.muted,
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Tooltip(message: label, child: content),
        ),
      );
    }
    final content = _NavItemFrame(
      collapsed: false,
      selected: selected,
      onTap: onTap,
      builder: (context, hovered) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final iconColor = selected
                ? PomgtColors.canvas
                : hovered
                ? PomgtColors.blue
                : PomgtColors.muted;
            final textColor = selected
                ? PomgtColors.canvas
                : hovered
                ? PomgtColors.blue
                : PomgtColors.muted;
            if (constraints.maxWidth < 44) {
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              );
            }
            return Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: content,
    );
  }
}

class _NavItemFrame extends StatefulWidget {
  const _NavItemFrame({
    required this.selected,
    required this.collapsed,
    required this.onTap,
    required this.builder,
  });

  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_NavItemFrame> createState() => _NavItemFrameState();
}

class _NavItemFrameState extends State<_NavItemFrame> {
  bool _hovered = false;
  bool _suppressHoverUntilExit = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _enter() {
    if (_suppressHoverUntilExit) return;
    _setHovered(true);
  }

  void _exit() {
    _suppressHoverUntilExit = false;
    _setHovered(false);
  }

  void _tap() {
    _suppressHoverUntilExit = true;
    if (_hovered) _setHovered(false);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? PomgtColors.blue : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      opaque: true,
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: _tap,
          child: AnimatedContainer(
            duration: PomgtMotion.fast,
            curve: PomgtMotion.curve,
            width: widget.collapsed ? 48 : null,
            height: 48,
            alignment: widget.collapsed ? Alignment.center : null,
            padding: widget.collapsed
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: PomgtRadii.borderSm,
              boxShadow: null,
            ),
            child: widget.builder(context, _hovered),
          ),
        ),
      ),
    );
  }
}
