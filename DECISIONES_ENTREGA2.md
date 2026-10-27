# TurismoUQ · Entrega 2 · Decisiones de diseño de la capa PL/SQL

## Orden de ejecución (base limpia)

| Script | Usuario | Qué hace |
|---|---|---|
| 00_Tablespaces.sql | SYSTEM | Tablespaces, usuario TURISMOUQ y cuotas |
| 01_DDL.sql | TURISMOUQ | Tablas, PK, FK, CHECK, UNIQUE, NOT NULL |
| 02_CargaDatos.sql | TURISMOUQ | Datos con PL/SQL y DBMS_RANDOM |
| 03_Consultas.sql | TURISMOUQ | Las 8 consultas y la vista materializada |
| 04_CapaPLSQL.sql | TURISMOUQ | Paquete, disparadores y recálculo de valores |
| 05_PruebasPLSQL.sql | TURISMOUQ | Pruebas; termina en ROLLBACK y se puede repetir |

## 1. fn_valor_estadia: estadía que atraviesa varias temporadas

- El calendario (PERIODO_TEMPORADA) asigna cada día de 2024 a 2028 a una temporada (ALTA, MEDIA o BAJA), sin huecos ni cruces.
- La estadía es el rango [checkin, checkout). La noche del checkout no se cobra.
- Un cursor con parámetros, `c_tramos(habitacion, checkin, checkout)`, devuelve un tramo por cada periodo que se cruza con la estadía:
  - desde = el mayor entre el inicio del periodo y el checkin
  - hasta = el menor entre el fin del periodo + 1 y el checkout
  - noches = hasta − desde
- Valor = Σ noches del tramo × tarifa de la habitación en la temporada del tramo.
- Control: si la suma de noches de los tramos no da checkout − checkin, alguna noche quedó sin temporada o sin tarifa, y se lanza -20007 en lugar de devolver un valor incompleto.
- Ejemplo: habitación 1, del 30-jul al 3-sep de 2025, son 2 noches ALTA + 31 MEDIA + 2 BAJA. `sp_desglose_estadia` lo imprime tramo por tramo.
- Calcular por tramos hace una consulta por estadía, no una por noche. Es más eficiente, y la función se puede usar dentro de un SELECT.

## 2. Reserva con varias habitaciones

RESERVA guarda las fechas y el cliente. RESERVA_HABITACION guarda una fila por habitación, con sus huéspedes y su valor. `sp_crear_reserva` crea la reserva con la primera habitación, y `sp_agregar_habitacion` agrega las demás con las mismas fechas y las mismas validaciones.

## 3. Excepciones propias

| Código | Nombre en el paquete | Cuándo |
|---|---|---|
| -20001 | e_no_disponible | Fechas ocupadas, o habitación en MANTENIMIENTO o INACTIVA |
| -20002 | e_fechas_invalidas | Checkout anterior o igual al checkin |
| -20003 | e_capacidad_excedida | Más huéspedes que la capacidad |
| -20004 | e_hab_inexistente | La habitación no existe |
| -20005 | e_solapamiento | Los disparadores detectan un cruce |
| -20006 | e_reserva_inexistente | Agregar habitación a una reserva que no existe |
| -20007 | e_sin_tarifa | Noches sin temporada o sin tarifa |
| -20010 | e_mes_invalido | Mes fuera de 1..12 en la liquidación |

Se lanzan con RAISE_APPLICATION_ERROR y se declaran en el paquete con PRAGMA EXCEPTION_INIT, para que quien llame las capture por nombre: `WHEN pkg_turismo.e_capacidad_excedida THEN ...`.

## 4. Liquidación mensual (cursor explícito con parámetros)

`sp_liquidacion_mensual(anio, mes)` abre `c_liq(p_desde, p_hasta)` con OPEN, FETCH y CLOSE, y usa %NOTFOUND, %ROWCOUNT e %ISOPEN. Por cada alojamiento activo calcula las reservas no canceladas con checkin en el mes, los ingresos de habitaciones, los de servicios, la comisión (10 %) y el neto.

Se puede relanzar el mismo mes, porque borra antes la liquidación de ese mes. No hace COMMIT; la transacción la cierra quien lo llama.

## 5. Disparadores

**Sentencia, auditoría de TARIFA (`trg_aud_tarifa`).** Un disparador de sentencia corre una vez por sentencia, pero no ve :OLD ni :NEW, y la auditoría pide el valor anterior y el nuevo. Se usa un COMPOUND TRIGGER: la sección por fila solo guarda el antes y el después en una colección, y la sección AFTER STATEMENT escribe la auditoría una vez al terminar la sentencia, con quién (SESSION_USER) y cuándo (SYSDATE). Sin NULLs: el precio anterior es 0 en un INSERT y el nuevo es 0 en un DELETE.

**Fila, anti-solapamiento (`trg_rh_no_solape` y `trg_reserva_no_solape`).** Un solape se puede crear por dos caminos: insertando una habitación en una reserva, o cambiando las fechas (o reactivando) una reserva existente. Hay un disparador para cada camino. Un BEFORE ... FOR EACH ROW que consulte la misma tabla que se modifica produce ORA-04091 (tabla mutante). Por eso la sección FOR EACH ROW registra cada fila afectada y la validación se hace en AFTER STATEMENT, donde ya se puede leer la tabla. Si hay cruce, RAISE_APPLICATION_ERROR deshace la sentencia completa.

Regla de cruce: [in1, out1) y [in2, out2) se cruzan si in1 < out2 y out1 > in2. Las reservas CANCELADAS no bloquean. Salir y entrar el mismo día no es cruce.

## 6. Recálculo de valores

La carga dejó valores provisionales. 04 recalcula `valor_habitacion` con fn_valor_estadia y `PAGO.valor` como habitaciones + servicios, y después refresca la vista materializada según su política (COMPLETE ON DEMAND).

## Pendiente para la Entrega 3

- Los disparadores anti-solape buscan por `RESERVA_HABITACION.id_habitacion`, que no tiene índice propio (la PK empieza por `id_reserva`). Es buen candidato para el punto de índices.
- La validación de `sp_crear_reserva` más el disparador no evitan que dos sesiones reserven la misma habitación al mismo tiempo. Es justo el experimento de concurrencia, y se resuelve con SELECT ... FOR UPDATE.
