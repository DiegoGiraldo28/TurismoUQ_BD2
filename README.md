# TurismoUQ · Bases de Datos II (2026-2)

Base de datos de la plataforma de reservas turísticas del Quindío, sobre Oracle XE 21c.

## Orden de ejecución (base limpia)

| # | Script | Conexión | Qué hace |
|---|---|---|---|
| 00 | `00_Tablespaces.sql` | SYSTEM (servicio XEPDB1) | Tablespaces `ts_turismo_datos` y `ts_hist_reservas`, usuario TURISMOUQ y permisos |
| 01 | `01_DDL.sql` | TURISMOUQ | 15 tablas con PK, FK, CHECK, UNIQUE y NOT NULL |
| 02 | `02_CargaDatos.sql` | TURISMOUQ | Carga con PL/SQL y DBMS_RANDOM (25.000 reservas 2024-2026) |
| 03 | `03_Consultas.sql` | TURISMOUQ | 8 consultas de análisis y vista materializada |
| 04 | `04_CapaPLSQL.sql` | TURISMOUQ | Entrega 2: paquete `PKG_TURISMO` y disparadores |
| 05 | `05_PruebasPLSQL.sql` | TURISMOUQ | Pruebas de la capa PL/SQL (termina en ROLLBACK) |

Cada script se ejecuta completo con F5 (Ejecutar script) en SQL Developer.

## Entregas

- **Entrega 1** (00 a 03): modelo, carga, tablespace del histórico y consultas.
- **Entrega 2** (04 y 05): `fn_valor_estadia`, `sp_crear_reserva` con excepciones propias, liquidación mensual con cursor explícito con parámetros, disparador de sentencia (auditoría de TARIFA) y disparadores de fila (no solapar reservas). Las decisiones de diseño están en `DECISIONES_ENTREGA2.md`.

Los datos de clientes, alojamientos, contactos y reseñas son generados con fines académicos.
