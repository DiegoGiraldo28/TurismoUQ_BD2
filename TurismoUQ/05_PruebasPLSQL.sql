/* ============================================================
   TURISMOUQ - 05_PruebasPLSQL.sql  (ENTREGA 2: pruebas de la capa PL/SQL)
   Ejecutar como TURISMOUQ despues de 04, como script completo (F5 en
   SQL Developer). Termina con ROLLBACK: se puede repetir cuantas veces
   se quiera sin dejar reservas, auditoria ni liquidaciones de prueba.

   Las reservas de prueba usan fechas de 2028 (los datos cargados llegan
   hasta 2026, asi que no chocan).
   ============================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;
VARIABLE b_reserva NUMBER

/* ------------------------------------------------------------
   1. fn_valor_estadia
   ------------------------------------------------------------ */

-- 1.1 Estadia que cruza DOS temporadas: habitacion 1, 10-dic a 20-dic de 2025.
--     Noches del 10 al 14 = BAJA; del 15 al 19 = ALTA (fin de año). 5 + 5 noches.
DECLARE
    v_baja TARIFA.precio_noche%TYPE;
    v_alta TARIFA.precio_noche%TYPE;
    v_func NUMBER;
BEGIN
    SELECT precio_noche INTO v_baja FROM TARIFA WHERE id_habitacion = 1 AND id_temporada = 3;
    SELECT precio_noche INTO v_alta FROM TARIFA WHERE id_habitacion = 1 AND id_temporada = 1;
    v_func := pkg_turismo.fn_valor_estadia(1, DATE '2025-12-10', DATE '2025-12-20');

    DBMS_OUTPUT.PUT_LINE('--- 1.1 Dos temporadas (BAJA -> ALTA)');
    pkg_turismo.sp_desglose_estadia(1, DATE '2025-12-10', DATE '2025-12-20');
    DBMS_OUTPUT.PUT_LINE('  Manual 5 x BAJA + 5 x ALTA = ' || (5 * v_baja + 5 * v_alta) ||
                         CASE WHEN v_func = 5 * v_baja + 5 * v_alta THEN '  -> OK' ELSE '  -> FALLA' END);
END;
/

-- 1.2 Estadia que cruza TRES temporadas: habitacion 1, 30-jul a 3-sep de 2025.
--     30 y 31 de julio = ALTA (2), agosto = MEDIA (31), 1 y 2 de sept = BAJA (2).
DECLARE
    v_alta  TARIFA.precio_noche%TYPE;
    v_media TARIFA.precio_noche%TYPE;
    v_baja  TARIFA.precio_noche%TYPE;
    v_func  NUMBER;
BEGIN
    SELECT precio_noche INTO v_alta  FROM TARIFA WHERE id_habitacion = 1 AND id_temporada = 1;
    SELECT precio_noche INTO v_media FROM TARIFA WHERE id_habitacion = 1 AND id_temporada = 2;
    SELECT precio_noche INTO v_baja  FROM TARIFA WHERE id_habitacion = 1 AND id_temporada = 3;
    v_func := pkg_turismo.fn_valor_estadia(1, DATE '2025-07-30', DATE '2025-09-03');

    DBMS_OUTPUT.PUT_LINE('--- 1.2 Tres temporadas (ALTA -> MEDIA -> BAJA)');
    pkg_turismo.sp_desglose_estadia(1, DATE '2025-07-30', DATE '2025-09-03');
    DBMS_OUTPUT.PUT_LINE('  Manual 2 x ALTA + 31 x MEDIA + 2 x BAJA = ' || (2 * v_alta + 31 * v_media + 2 * v_baja) ||
                         CASE WHEN v_func = 2 * v_alta + 31 * v_media + 2 * v_baja THEN '  -> OK' ELSE '  -> FALLA' END);
END;
/

-- 1.3 La funcion tambien se usa dentro de un SELECT
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2025-12-10', DATE '2025-12-20') AS valor_estadia FROM dual;

-- 1.4 Checkout igual al checkin: se captura la excepcion propia por su nombre
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 1.4 Fechas invalidas en la funcion');
    DBMS_OUTPUT.PUT_LINE(pkg_turismo.fn_valor_estadia(1, DATE '2025-05-05', DATE '2025-05-05'));
EXCEPTION
    WHEN pkg_turismo.e_fechas_invalidas THEN
        DBMS_OUTPUT.PUT_LINE('  Esperado -> ' || SQLERRM);
END;
/

/* ------------------------------------------------------------
   2. sp_crear_reserva: caso valido y las excepciones propias
      (habitacion 1 admite 2 huespedes; la 2 admite 4; la 3 admite 3)
   ------------------------------------------------------------ */
DECLARE
    v_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 2. sp_crear_reserva');

    -- 2.1 Reserva valida: habitacion 1, 1 al 4 de febrero de 2028
    pkg_turismo.sp_crear_reserva(1, 1000000001, 1, DATE '2028-02-01', DATE '2028-02-04', 2, v_id);
    :b_reserva := v_id;
    DBMS_OUTPUT.PUT_LINE('  2.1 OK reserva creada: ' || v_id);

    -- 2.2 Habitacion no disponible: se cruza con la reserva anterior
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 1, DATE '2028-02-03', DATE '2028-02-06', 2, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.2 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_no_disponible THEN
            DBMS_OUTPUT.PUT_LINE('  2.2 Esperado -> ' || SQLERRM);
    END;

    -- 2.3 Checkout igual al checkin
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 2, DATE '2028-03-05', DATE '2028-03-05', 2, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.3 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_fechas_invalidas THEN
            DBMS_OUTPUT.PUT_LINE('  2.3 Esperado -> ' || SQLERRM);
    END;

    -- 2.4 Checkout ANTERIOR al checkin
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 2, DATE '2028-03-10', DATE '2028-03-07', 2, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.4 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_fechas_invalidas THEN
            DBMS_OUTPUT.PUT_LINE('  2.4 Esperado -> ' || SQLERRM);
    END;

    -- 2.5 Capacidad excedida: 5 huespedes en una habitacion para 2
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 1, DATE '2028-04-01', DATE '2028-04-03', 5, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.5 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_capacidad_excedida THEN
            DBMS_OUTPUT.PUT_LINE('  2.5 Esperado -> ' || SQLERRM);
    END;

    -- 2.6 Habitacion no disponible porque esta en mantenimiento
    UPDATE HABITACION SET estado = 'MANTENIMIENTO' WHERE id_habitacion = 5;
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 5, DATE '2028-05-01', DATE '2028-05-03', 1, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.6 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_no_disponible THEN
            DBMS_OUTPUT.PUT_LINE('  2.6 Esperado -> ' || SQLERRM);
    END;

    -- 2.7 Habitacion que no existe
    BEGIN
        pkg_turismo.sp_crear_reserva(2, 1000000002, 9999, DATE '2028-05-01', DATE '2028-05-03', 1, v_id);
        DBMS_OUTPUT.PUT_LINE('  2.7 FALLA: debio rechazarse');
    EXCEPTION
        WHEN pkg_turismo.e_hab_inexistente THEN
            DBMS_OUTPUT.PUT_LINE('  2.7 Esperado -> ' || SQLERRM);
    END;
END;
/

/* ------------------------------------------------------------
   3. Reserva con varias habitaciones: se agrega la habitacion 3
      a la reserva creada en 2.1
   ------------------------------------------------------------ */
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 3. sp_agregar_habitacion');
    pkg_turismo.sp_agregar_habitacion(:b_reserva, 3, 3);
    DBMS_OUTPUT.PUT_LINE('  OK habitacion 3 agregada a la reserva ' || :b_reserva);
END;
/

SELECT rh.id_reserva, rh.id_habitacion, rh.cantidad_huespedes, rh.valor_habitacion,
       r.fecha_checkin, r.fecha_checkout, r.estado
  FROM RESERVA_HABITACION rh
  JOIN RESERVA r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_reserva = :b_reserva;

/* ------------------------------------------------------------
   4. Disparadores anti-solapamiento
   ------------------------------------------------------------ */

-- 4.1 INSERT directo en las tablas (sin pasar por el procedimiento):
--     el disparador de RESERVA_HABITACION lo bloquea
DECLARE
    v_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 4.1 Insert directo que se solapa');
    INSERT INTO RESERVA (id_reserva, id_usuario_sistema, id_cliente, fecha_reserva,
                         fecha_checkin, fecha_checkout, estado)
    VALUES (seq_reserva.NEXTVAL, 1, 1000000003, TRUNC(SYSDATE),
            DATE '2028-02-02', DATE '2028-02-05', 'PENDIENTE')
    RETURNING id_reserva INTO v_id;

    INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes, valor_habitacion)
    VALUES (v_id, 1, 2, 100000);
    DBMS_OUTPUT.PUT_LINE('  FALLA: el disparador debio bloquear esto');
EXCEPTION
    WHEN pkg_turismo.e_solapamiento THEN
        DBMS_OUTPUT.PUT_LINE('  Esperado -> ' || SQLERRM);
END;
/

-- 4.2 Cambiar las fechas de una reserva existente para que choque con otra:
--     el disparador de RESERVA lo bloquea
DECLARE
    v_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 4.2 Cambio de fechas que se solapa');
    -- Reserva valida en la habitacion 1, despues de la de 2.1 (que va del 1 al 4)
    pkg_turismo.sp_crear_reserva(1, 1000000004, 1, DATE '2028-02-10', DATE '2028-02-12', 1, v_id);
    DBMS_OUTPUT.PUT_LINE('  Reserva ' || v_id || ' creada del 10 al 12 de febrero');

    -- Se intenta adelantarla al 3 de febrero: choca con la reserva de 2.1
    UPDATE RESERVA SET fecha_checkin = DATE '2028-02-03' WHERE id_reserva = v_id;
    DBMS_OUTPUT.PUT_LINE('  FALLA: el disparador debio bloquear esto');
EXCEPTION
    WHEN pkg_turismo.e_solapamiento THEN
        DBMS_OUTPUT.PUT_LINE('  Esperado -> ' || SQLERRM);
END;
/

-- 4.3 Una reserva CANCELADA libera la habitacion: se cancela la de 2.1
--     y ya se puede reservar en esas fechas
DECLARE
    v_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 4.3 Reserva cancelada libera la habitacion');
    UPDATE RESERVA SET estado = 'CANCELADA' WHERE id_reserva = :b_reserva;
    pkg_turismo.sp_crear_reserva(1, 1000000005, 1, DATE '2028-02-02', DATE '2028-02-04', 2, v_id);
    DBMS_OUTPUT.PUT_LINE('  OK reserva ' || v_id || ' creada en las fechas liberadas');
END;
/

/* ------------------------------------------------------------
   5. Disparador de auditoria de TARIFA
      Una sola sentencia que toca 3 filas (ALTA, MEDIA y BAJA de la
      habitacion 1) deja 3 registros de auditoria.
   ------------------------------------------------------------ */
UPDATE TARIFA SET precio_noche = precio_noche * 1.10 WHERE id_habitacion = 1;

SELECT a.id_auditoria, a.usuario, TO_CHAR(a.fecha, 'YYYY-MM-DD HH24:MI:SS') AS fecha,
       a.operacion, a.id_tarifa, tm.nombre AS temporada, a.precio_anterior, a.precio_nuevo
  FROM AUDITORIA_TARIFA a
  JOIN TARIFA t     ON t.id_tarifa     = a.id_tarifa
  JOIN TEMPORADA tm ON tm.id_temporada = t.id_temporada
 ORDER BY a.id_auditoria;

/* ------------------------------------------------------------
   6. Liquidacion mensual (cursor explicito con parametros)
   ------------------------------------------------------------ */
EXEC pkg_turismo.sp_liquidacion_mensual(2025, 7);

SELECT l.id_alojamiento, a.nombre, l.num_reservas, l.ingresos_habitaciones,
       l.ingresos_servicios, l.comision, l.neto_alojamiento
  FROM LIQUIDACION_MENSUAL l
  JOIN ALOJAMIENTO a ON a.id_alojamiento = l.id_alojamiento
 WHERE l.anio = 2025 AND l.mes = 7
 ORDER BY l.neto_alojamiento DESC
 FETCH FIRST 10 ROWS ONLY;

-- 6.1 Mes invalido
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 6.1 Mes invalido');
    pkg_turismo.sp_liquidacion_mensual(2025, 13);
EXCEPTION
    WHEN pkg_turismo.e_mes_invalido THEN
        DBMS_OUTPUT.PUT_LINE('  Esperado -> ' || SQLERRM);
END;
/

-- Deshace todas las pruebas (reservas, mantenimiento, auditoria y liquidacion)
ROLLBACK;
