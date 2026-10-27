# TurismoUQ

Aplicación monolítica Django para consultar y gestionar reservas turísticas del Quindío. Oracle es la fuente de verdad del negocio; su esquema existente no se modifica. La base `default` de SQLite se reserva para las funciones internas de Django.

## Requisitos

- Windows 10/11
- Python 3.11 o superior
- Oracle XE 21c iniciado, con el servicio `XEPDB1` y el esquema TurismoUQ cargado con los scripts SQL del proyecto

## Instalación

Desde la raíz del proyecto, en PowerShell:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
Copy-Item .env.example .env
```

Edita `.env` y establece `ORACLE_PASSWORD` con la contraseña del usuario `TURISMOUQ`. No compartas ese archivo ni lo incluyas en control de versiones.

## Preparar Django y ejecutar

Las migraciones solo crean las tablas internas de Django en SQLite. El router bloquea las migraciones sobre Oracle.

```powershell
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

Abre <http://127.0.0.1:8000/> e inicia sesión con el superusuario creado. La pantalla inicial consulta los conteos de las tablas de negocio para confirmar la conexión a Oracle. El superusuario de ejemplo se crea en el momento de la instalación; no se guarda una contraseña de ejemplo en el código.

## Tablero y alojamientos

La página `/` requiere autenticación de Django (SQLite) y muestra indicadores, ingresos del mes y el gráfico mensual construido desde `MV_OCUPACION_MENSUAL`. `/alojamientos/` lista alojamientos activos y permite filtrar por municipio y tipo. Cada alojamiento tiene una página de detalle con habitaciones, tarifas por temporada, servicios y promedio de reseñas. `/diagnostico/` muestra los conteos de las tablas de negocio.

## Búsqueda, cotización y reservas

`/disponibilidad/` busca habitaciones por fechas, huéspedes y municipio opcional. El total se consulta con `PKG_TURISMO.FN_VALOR_ESTADIA` y se acompaña con el desglose por temporada. Para reservar, se busca el cliente por cédula y se selecciona un usuario de `USUARIO_SISTEMA`. La creación y la adición de habitaciones se ejecutan con `SP_CREAR_RESERVA` y `SP_AGREGAR_HABITACION`, dentro de transacciones Oracle; Django confirma la transacción cuando el procedimiento termina bien y la revierte si ocurre un error.

Los errores capturados quedan registrados con traceback en la consola del servidor. Con `DJANGO_DEBUG=true`, la alerta también incluye el detalle técnico Oracle/driver para facilitar el diagnóstico. ORA-02291 y ORA-00001 se traducen a mensajes en español.

## Reservas, clientes y tarifas

- `/reservas/`: listado paginado; filtra por estado, fechas de check-in y cédula del cliente. Las fechas se envían como variables de enlace Oracle.
- `/clientes/`: búsqueda por nombre, cédula o correo; desde allí se crean y editan clientes. La cédula no se modifica al editar.
- `/tarifas/`: lista las tarifas por habitación y temporada; los cambios actualizan Oracle y el disparador registra la auditoría.
- `/tarifas/auditoria/`: consulta los últimos cambios auditados.

El detalle de una reserva en `/reservas/<id>/` presenta habitaciones, servicios, pagos y total. La cancelación se envía por POST y se confirma en una transacción Oracle.

## Liquidación y reportes

- `/liquidaciones/`: el formulario ejecuta `PKG_TURISMO.SP_LIQUIDACION_MENSUAL` en una transacción Oracle y muestra las filas del mes, más los totales.
- `/reportes/`: índice de las ocho consultas analíticas del script `03_Consultas.sql`.
- `/reportes/ocupacion-mensual/`: consulta `MV_OCUPACION_MENSUAL`, muestra `USER_MVIEWS.LAST_REFRESH_DATE` y ofrece el refresco completo manual.

Si Oracle no está disponible, se presenta una alerta en español sin mostrar trazas técnicas.

`inspectdb --database turismo` sirve como punto de partida para los modelos `managed = False` cuando Oracle esté configurado:

```powershell
python manage.py inspectdb --database turismo
```

No ejecutes migraciones de negocio en Oracle. Los procedimientos del paquete se incorporarán en `turismo/services.py` durante las siguientes fases.
