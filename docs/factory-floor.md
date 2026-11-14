# Mapa de planta

El mapa abre mostrando las máquinas en marcha y su flujo de producción. Los
controles **Solo máquinas en marcha** y **Flujo de producción** están dentro
del plano. La actividad se calcula a partir del estado del equipo y de la
operación activa de cada orden. Se muestran las máquinas de todos los pasos de
las órdenes listas y en producción, incluidos los pasos posteriores en cola.
Si aún no existe la copia de operaciones de una OP, el mapa reconstruye sus
pasos desde la revisión de ruta asignada; también reconoce los pasos de
preparación.
Cuando una operación solo tiene centro de trabajo, se asocia a la única máquina
elegible de ese centro y el mapa marca esa asignación como inferida. Cada
equipo presenta las órdenes asignadas, el paso actual, el avance de la ruta y
si la operación está en ejecución, en espera o necesita continuar. **Solo
máquinas en marcha** permite ampliar la vista a todas las máquinas, incluidas
las que están en mantenimiento. Al seleccionar una orden, el plano muestra su
recorrido completo. Incluye pasillos, siluetas industriales, minimapa navegable
y controles de zoom. Las posiciones son de referencia, no dimensiones físicas
de la fábrica. En el plano 2D, las conexiones completadas quedan sólidas; la
conexión que sale del paso en ejecución lleva una animación continua y el icono
de esa máquina pulsa al mismo ritmo. El flujo por orden usa las mismas flechas,
colores y animación; al abrir el plano, el encuadre centra la primera máquina
en ejecución. Las máquinas enlazadas reciben posiciones sugeridas próximas si
aún no tienen coordenadas guardadas, y cada ficha muestra como máximo dos OP.

Una máquina solo admite una OP en ejecución a la vez. La migración
`202611030003_machine_execution_exclusivity.sql` valida el inicio y los cambios
de máquina dentro de la transacción; si el equipo está ocupado, el cambio de
estado se rechaza con el número de la orden que lo está usando.

## Base de datos

Ejecutar **`supabase/factory_floor_upgrade.sql` completo** en el SQL Editor del
proyecto de la app. El archivo contiene las migraciones del mapa y la regla de
exclusividad de máquina, dentro de una transacción, y admite ejecuciones
repetidas. No se ha aplicado remotamente. El flujo habitual de migraciones puede usar los archivos
`202611030001_machine_floor_position.sql` y
`202611030002_complete_factory_floor.sql`, más
`202611030003_machine_execution_exclusivity.sql`.

Se agregan coordenadas de máquinas, áreas (`floor_zones`) y almacenes. Se
restauran `warehouses`, `inventory_stock` e `inventory_movements`, eliminadas del
MVP anterior. No se crean saldos ficticios ni se convierten consumos históricos
en existencias. El saldo inicial se registra como una entrada de inventario.

Las existencias y el kardex son de lectura para los usuarios de la app; las
entradas y salidas se registran mediante un RPC validado, con permisos por
organización, comprobación de unidad base, bloqueo transaccional y clave de
idempotencia. Las salidas sin saldo se rechazan. Desde el detalle de una orden,
**Surtir desde almacén** y **Devolver a almacén** actualizan la orden y el saldo
en una sola transacción usando el RPC de producción existente. Si cualquiera
de los dos pasos falla, toda la operación se revierte. Los movimientos de
producción registrados sin seleccionar un almacén en otras pantallas mantienen
su comportamiento anterior y no generan movimientos de inventario retroactivos.

## Uso

- Selecciona una máquina para ver su ficha y sus operaciones, o una orden para
  consultar el detalle de producción y resaltar su recorrido entre equipos.
- El mapa es una vista operativa de la planta. Las fichas, especificaciones,
  movimientos y administración de materiales, productos y almacenes permanecen
  en sus módulos correspondientes.
- El detalle de producción permite expandir/minimizar máquina, centro de
  trabajo, operadores, operaciones, materiales, parámetros, calidad,
  verificaciones, costos, eventos y dependencias. El botón de producción abre
  la pantalla operativa existente.
- En móvil los filtros se despliegan con **Filtros de máquinas** y el detalle ocupa
  un panel inferior. La leyenda se desplaza horizontalmente.

Las consultas se actualizan cada nueve segundos mientras el módulo está
visible y la app está activa. Se conserva el zoom, la selección y el último
snapshot si falla la conexión. Los errores se muestran y permiten reintentar.
El detalle abierto también se actualiza y descarta respuestas de otra orden.
El estado de marcha usa las operaciones en ejecución y la orden activa en su
primer paso pendiente; el resto de los estados se toma del equipo. Varias
operaciones simultáneas se muestran sin sobrescribirse. Esto refleja los
registros de producción, no telemetría de PLC. Una ficha de máquina muestra
hasta dos órdenes y resume las restantes para conservar espacio.

## Validación

```sh
flutter test --no-pub test/floor_map_test.dart test/floor_repository_test.dart
flutter test --no-pub
flutter build web --no-pub
```

Las pruebas SQL usan PostgreSQL embebido en una base aislada, sin conectar a
Supabase. Con Node y `@electric-sql/pglite` instalado:

```sh
node test/sql/factory_floor_inventory_test.mjs
```

También se puede apuntar `PGLITE_MODULE` al `dist/index.js` de una instalación
externa de PGlite. Se comprueba repetición de migraciones, aislamiento por
organización, permisos, saldo insuficiente, idempotencia y reversión atómica de
surtidos. El fixture reproduce la firma del RPC de producción; la integración
con el esquema desplegado se verifica después de aplicar el SQL.
