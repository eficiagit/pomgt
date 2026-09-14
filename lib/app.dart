import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'controllers/auth_controller.dart';
import 'controllers/feature_controllers.dart';
import 'controllers/navigation_controller.dart';
import 'controllers/organization_controller.dart';
import 'controllers/runtime_data_controller.dart';
import 'core/theme/pomgt_theme.dart';
import 'core/widgets/app_shell.dart';
import 'data/repositories/base_repository.dart';
import 'data/repositories/bom_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/document_repository.dart';
import 'data/repositories/generic_repository.dart';
import 'data/repositories/lookup_repository.dart';
import 'data/repositories/material_repository.dart';
import 'data/repositories/order_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/routing_repository.dart';
import 'data/services/auth_service.dart';
import 'data/services/document_storage_service.dart';
import 'data/services/supabase_database_service.dart';
import 'features/auth/login_screen.dart';
import 'features/setup/organization_setup_screen.dart';

class PomgtApp extends StatefulWidget {
  const PomgtApp({super.key});
  @override
  State<PomgtApp> createState() => _PomgtAppState();
}

class _PomgtAppState extends State<PomgtApp> {
  late final SupabaseClient client;
  late final SupabaseDatabaseService db;
  late final AuthService authService;
  late final DocumentStorageService storage;
  late final GenericRepository generic;
  late final CustomerRepository customers;
  late final OrderRepository orders;
  late final ProductRepository products;
  late final MaterialRepository materials;
  late final BomRepository boms;
  late final RoutingRepository routings;
  late final DocumentRepository documents;
  late final LookupRepository lookups;
  late final RuntimeDataController runtimeData;
  late final AuthController authController;
  late final OrganizationController organizationController;

  @override
  void initState() {
    super.initState();
    client = Supabase.instance.client;
    db = SupabaseDatabaseService(client);
    authService = AuthService(client);
    storage = DocumentStorageService(client);
    runtimeData = RuntimeDataController();
    generic = GenericRepository(db, client, runtimeData: runtimeData);
    customers = CustomerRepository(db, client);
    orders = OrderRepository(db, client);
    products = ProductRepository(db, client);
    materials = MaterialRepository(db, client);
    boms = BomRepository(db, client);
    routings = RoutingRepository(db, client);
    documents = DocumentRepository(db, client, storage);
    lookups = LookupRepository(generic, runtimeData);
    final tenantRepos = <BaseRepository>[
      generic,
      customers,
      orders,
      products,
      materials,
      boms,
      routings,
      documents,
    ];
    authController = AuthController(authService);
    organizationController = OrganizationController(db, tenantRepos);
  }

  @override
  void dispose() {
    authController.dispose();
    organizationController.dispose();
    runtimeData.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: client),
        Provider.value(value: db),
        Provider.value(value: generic),
        Provider.value(value: customers),
        Provider.value(value: orders),
        Provider.value(value: products),
        Provider.value(value: materials),
        Provider.value(value: boms),
        Provider.value(value: routings),
        Provider.value(value: documents),
        Provider.value(value: lookups),
        ChangeNotifierProvider.value(value: runtimeData),
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider.value(value: organizationController),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider(create: (_) => CustomersController()),
        ChangeNotifierProvider(create: (_) => OrdersController()),
        ChangeNotifierProvider(create: (_) => ProductsController()),
        ChangeNotifierProvider(create: (_) => MaterialsController()),
        ChangeNotifierProvider(create: (_) => BomController()),
        ChangeNotifierProvider(create: (_) => RoutingsController()),
        ChangeNotifierProvider(create: (_) => DocumentsController()),
        ChangeNotifierProvider(create: (_) => ProductionController()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'POMGT',
        theme: buildPomgtTheme(),
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _AppGate(),
      ),
    );
  }
}

class _AppGate extends StatefulWidget {
  const _AppGate();
  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  String? _loadedUserId;

  void _ensureOrganizationLoad(String userId) {
    if (_loadedUserId == userId) return;
    _loadedUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrganizationController>().loadForUser(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.authenticated) {
      _loadedUserId = null;
      return const LoginScreen();
    }
    final userId = auth.user!.id;
    _ensureOrganizationLoad(userId);
    final org = context.watch<OrganizationController>();
    if (org.loading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (org.error != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 34,
                    color: PomgtColors.danger,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No pudimos cargar tu organización',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    org.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: PomgtColors.muted),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => org.loadForUser(userId),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (org.organizationId == null) return const OrganizationSetupScreen();
    return const AppShell();
  }
}
