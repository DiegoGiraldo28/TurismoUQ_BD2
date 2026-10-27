/* ============================================================
   TURISMOUQ - 04_CapaPLSQL.sql  (ENTREGA 2: CAPA PL/SQL)

   Contenido:
     0. Objetos de apoyo (secuencia, auditoria, liquidacion)
     1. Paquete PKG_TURISMO
          - fn_valor_estadia        (tarifa de cada temporada que atraviesa la estadia)
          - fn_habitacion_disponible
          - sp_desglose_estadia     (muestra tramo por tramo; para la sustentacion)
          - sp_crear_reserva        (excepciones propias con RAISE_APPLICATION_ERROR)
          - sp_agregar_habitacion   (reserva con varias habitaciones)
          - sp_liquidacion_mensual  (cursor explicito con parametros)
     2. Disparador de sentencia: auditoria de TARIFA
     3. Disparadores de fila: anti-solapamiento de reservas
     4. Recalculo de valores con fn_valor_estadia y refresco de la vista materializada
   ============================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;

/* ------------------------------------------------------------
   0. OBJETOS DE APOYO
   ------------------------------------------------------------ */

-- 0.1 Secuencia para nuevas reservas (la carga uso los ids 1..25000)
CREATE SEQUENCE seq_reserva START WITH 25001 INCREMENT BY 1 NOCACHE;

-- 0.2 Auditoria de TARIFA: quien, cuando, valor anterior y nuevo.
--     Sin NULLs: en un INSERT el precio anterior es 0 y en un DELETE el nuevo es 0.
CREATE TABLE AUDITORIA_TARIFA (
    id_auditoria    NUMBER GENERATED ALWAYS AS IDENTITY,
    usuario         VARCHAR2(60) NOT NULL,
    fecha           DATE         NOT NULL,
    operacion       VARCHAR2(10) NOT NULL,
    id_tarifa       NUMBER       NOT NULL,
    precio_anterior NUMBER(12,2) NOT NULL,
    precio_nuevo    NUMBER(12,2) NOT NULL,
    CONSTRAINT pk_auditoria_tarifa PRIMARY KEY (id_auditoria),
    CONSTRAINT ck_aud_tarifa_op CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
);

-- 0.3 Resultado de la liquidacion mensual por alojamiento
CREATE TABLE LIQUIDACION_MENSUAL (
    id_alojamiento        NUMBER       NOT NULL,
    anio                  NUMBER(4)    NOT NULL,
    mes                   NUMBER(2)    NOT NULL,
    num_reservas          NUMBER       NOT NULL,
    ingresos_habitaciones NUMBER(14,2) NOT NULL,
    ingresos_servicios    NUMBER(14,2) NOT NULL,
    comision              NUMBER(14,2) NOT NULL,
    neto_alojamiento      NUMBER(14,2) NOT NULL,
    fecha_proceso         DATE         NOT NULL,
    CONSTRAINT pk_liquidacion_mensual PRIMARY KEY (id_alojamiento, anio, mes),
    CONSTRAINT fk_liquidacion_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento),
    CONSTRAINT ck_liquidacion_mes CHECK (mes BETWEEN 1 AND 12)
);

/* ------------------------------------------------------------
   1. PAQUETE PKG_TURISMO

   Excepciones propias (codigo  -> nombre en el paquete):
     -20001 habitacion no disponible (fechas ocupadas o fuera de servicio) -> e_no_disponible
     -20002 checkout anterior o igual al checkin                           -> e_fechas_invalidas
     -20003 capacidad excedida                                             -> e_capacidad_excedida
     -20004 habitacion inexistente                                         -> e_hab_inexistente
     -20005 reserva solapada (disparadores)                                -> e_solapamiento
     -20006 reserva inexistente                                            -> e_reserva_inexistente
     -20007 noches sin temporada o sin tarifa                              -> e_sin_tarifa
     -20010 mes invalido en la liquidacion                                 -> e_mes_invalido
   Con PRAGMA EXCEPTION_INIT quien llame al paquete puede capturarlas
   por nombre:  EXCEPTION WHEN pkg_turismo.e_no_disponible THEN ...
   ------------------------------------------------------------ */
CREATE OR REPLACE PACKAGE pkg_turismo AS

    c_comision CONSTANT NUMBER := 0.10;   -- comision de la plataforma (10 %)

    e_no_disponible       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_no_disponible,       -20001);
    e_fechas_invalidas    EXCEPTION;  PRAGMA EXCEPTION_INIT(e_fechas_invalidas,    -20002);
    e_capacidad_excedida  EXCEPTION;  PRAGMA EXCEPTION_INIT(e_capacidad_excedida,  -20003);
    e_hab_inexistente     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_hab_inexistente,     -20004);
    e_solapamiento        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_solapamiento,        -20005);
    e_reserva_inexistente EXCEPTION;  PRAGMA EXCEPTION_INIT(e_reserva_inexistente, -20006);
    e_sin_tarifa          EXCEPTION;  PRAGMA EXCEPTION_INIT(e_sin_tarifa,          -20007);
    e_mes_invalido        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_mes_invalido,        -20010);

    -- Valor de una estadia [fecha_in, fecha_out): aplica la tarifa de cada
    -- temporada (ALTA/MEDIA/BAJA) que la estadia atraviesa. La noche del
    -- checkout no se cobra. Se puede usar en SQL:
    --   SELECT pkg_turismo.fn_valor_estadia(1, DATE '2025-12-10', DATE '2025-12-20') FROM dual;
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- TRUE si la habitacion no tiene reservas activas que se crucen con el rango.
    -- p_excluir_reserva: reserva que no se cuenta (0 = ninguna).
    FUNCTION fn_habitacion_disponible (
        p_id_habitacion   IN NUMBER,
        p_fecha_in        IN DATE,
        p_fecha_out       IN DATE,
        p_excluir_reserva IN NUMBER DEFAULT 0
    ) RETURN BOOLEAN;

    -- Imprime el calculo de fn_valor_estadia tramo por tramo
    PROCEDURE sp_desglose_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    );

    -- Crea una reserva con una habitacion. No hace COMMIT: la transaccion
    -- la cierra quien llama (la atomicidad reserva + pago es de la Entrega 3).
    PROCEDURE sp_crear_reserva (
        p_id_usuario    IN  NUMBER,
        p_id_cliente    IN  NUMBER,
        p_id_habitacion IN  NUMBER,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_id_reserva    OUT NUMBER
    );

    -- Agrega otra habitacion a una reserva existente (misma estadia)
    PROCEDURE sp_agregar_habitacion (
        p_id_reserva    IN NUMBER,
        p_id_habitacion IN NUMBER,
        p_huespedes     IN NUMBER
    );

    -- Proceso masivo: liquidacion de un mes para todos los alojamientos
    PROCEDURE sp_liquidacion_mensual (
        p_anio IN NUMBER,
        p_mes  IN NUMBER
    );

END pkg_turismo;
/

CREATE OR REPLACE PACKAGE BODY pkg_turismo AS

    ------------------------------------------------------------------
    -- Cursor privado con parametros: los TRAMOS de una estadia.
    -- Un tramo es la parte de la estadia que cae dentro de un periodo del
    -- calendario (PERIODO_TEMPORADA). Para cada periodo que se cruza con
    -- [cp_in, cp_out):
    --     desde  = el mayor entre el inicio del periodo y el checkin
    --     hasta  = el menor entre (fin del periodo + 1) y el checkout
    --     noches = hasta - desde
    -- y se toma el precio de la TARIFA de esa habitacion en esa temporada.
    ------------------------------------------------------------------
    CURSOR c_tramos (cp_hab NUMBER, cp_in DATE, cp_out DATE) IS
        SELECT tm.nombre                                                  AS temporada,
               GREATEST(p.fecha_inicio, cp_in)                            AS desde,
               LEAST(p.fecha_fin + 1, cp_out)                             AS hasta,
               LEAST(p.fecha_fin + 1, cp_out) - GREATEST(p.fecha_inicio, cp_in) AS noches,
               t.precio_noche
          FROM PERIODO_TEMPORADA p
          JOIN TEMPORADA tm ON tm.id_temporada = p.id_temporada
          JOIN TARIFA t     ON t.id_temporada  = p.id_temporada
                           AND t.id_habitacion = cp_hab
         WHERE p.fecha_inicio <  cp_out
           AND p.fecha_fin    >= cp_in
         ORDER BY p.fecha_inicio;

    ------------------------------------------------------------------
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_in      DATE := TRUNC(p_fecha_in);
        v_out     DATE := TRUNC(p_fecha_out);
        v_existe  NUMBER;
        v_noches  NUMBER := 0;    -- noches que el calendario logro cubrir
        v_total   NUMBER := 0;
    BEGIN
        IF v_in IS NULL OR v_out IS NULL OR v_out <= v_in THEN
            RAISE_APPLICATION_ERROR(-20002, 'El checkout debe ser posterior al checkin');
        END IF;

        SELECT COUNT(*) INTO v_existe
          FROM HABITACION
         WHERE id_habitacion = p_id_habitacion;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'La habitacion ' || p_id_habitacion || ' no existe');
        END IF;

        -- Se suma cada tramo: noches del tramo x tarifa de su temporada
        FOR r IN c_tramos(p_id_habitacion, v_in, v_out) LOOP
            v_total  := v_total  + r.noches * r.precio_noche;
            v_noches := v_noches + r.noches;
        END LOOP;

        -- Si alguna noche no cayo en un periodo con tarifa, el valor estaria incompleto
        IF v_noches <> (v_out - v_in) THEN
            RAISE_APPLICATION_ERROR(-20007,
                'La estadia del ' || TO_CHAR(v_in, 'YYYY-MM-DD') || ' al ' || TO_CHAR(v_out, 'YYYY-MM-DD') ||
                ' tiene noches sin temporada o sin tarifa para la habitacion ' || p_id_habitacion);
        END IF;

        RETURN v_total;
    END fn_valor_estadia;

    ------------------------------------------------------------------
    FUNCTION fn_habitacion_disponible (
        p_id_habitacion   IN NUMBER,
        p_fecha_in        IN DATE,
        p_fecha_out       IN DATE,
        p_excluir_reserva IN NUMBER DEFAULT 0
    ) RETURN BOOLEAN IS
        v_n NUMBER;
    BEGIN
        -- Dos estadias [in1,out1) y [in2,out2) se cruzan si in1 < out2 Y out1 > in2.
        -- Que una salga el mismo dia en que la otra entra NO es cruce.
        SELECT COUNT(*)
          INTO v_n
          FROM RESERVA_HABITACION rh
          JOIN RESERVA r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion  = p_id_habitacion
           AND r.estado         <> 'CANCELADA'
           AND r.id_reserva     <> p_excluir_reserva
           AND r.fecha_checkin   < TRUNC(p_fecha_out)
           AND r.fecha_checkout  > TRUNC(p_fecha_in);
        RETURN (v_n = 0);
    END fn_habitacion_disponible;

    ------------------------------------------------------------------
    PROCEDURE sp_desglose_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Habitacion ' || p_id_habitacion || ': ' ||
                             TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ' a ' || TO_CHAR(p_fecha_out, 'YYYY-MM-DD'));
        FOR r IN c_tramos(p_id_habitacion, TRUNC(p_fecha_in), TRUNC(p_fecha_out)) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || RPAD(r.temporada, 6) ||
                                 TO_CHAR(r.desde, 'YYYY-MM-DD') || ' a ' || TO_CHAR(r.hasta, 'YYYY-MM-DD') ||
                                 ': ' || r.noches || ' noches x ' || r.precio_noche ||
                                 ' = ' || (r.noches * r.precio_noche));
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('  TOTAL fn_valor_estadia = ' ||
                             fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out));
    END sp_desglose_estadia;

    ------------------------------------------------------------------
    -- Validaciones comunes a crear reserva y agregar habitacion (privado)
    PROCEDURE validar (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE,
        p_huespedes     IN NUMBER,
        p_excluir       IN NUMBER DEFAULT 0
    ) IS
        v_cap    HABITACION.capacidad%TYPE;
        v_estado HABITACION.estado%TYPE;
    BEGIN
        -- 1. Checkout anterior o igual al checkin
        IF p_fecha_in IS NULL OR p_fecha_out IS NULL OR TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
            RAISE_APPLICATION_ERROR(-20002, 'El checkout debe ser posterior al checkin');
        END IF;

        -- 2. La habitacion existe (cursor implicito: NO_DATA_FOUND)
        BEGIN
            SELECT capacidad, estado
              INTO v_cap, v_estado
              FROM HABITACION
             WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20004, 'La habitacion ' || p_id_habitacion || ' no existe');
        END;

        -- 3. Habitacion no disponible: fuera de servicio
        IF v_estado <> 'DISPONIBLE' THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Habitacion ' || p_id_habitacion || ' no disponible: esta en estado ' || v_estado);
        END IF;

        -- 4. Capacidad excedida
        IF p_huespedes > v_cap THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Capacidad excedida: la habitacion ' || p_id_habitacion || ' admite ' || v_cap ||
                ' huespedes y se piden ' || p_huespedes);
        END IF;

        -- 5. Habitacion no disponible: ya reservada en esas fechas
        IF NOT fn_habitacion_disponible(p_id_habitacion, p_fecha_in, p_fecha_out, p_excluir) THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Habitacion ' || p_id_habitacion || ' no disponible del ' ||
                TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ' al ' || TO_CHAR(p_fecha_out, 'YYYY-MM-DD'));
        END IF;
    END validar;

    ------------------------------------------------------------------
    PROCEDURE sp_crear_reserva (
        p_id_usuario    IN  NUMBER,
        p_id_cliente    IN  NUMBER,
        p_id_habitacion IN  NUMBER,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_id_reserva    OUT NUMBER
    ) IS
        v_valor RESERVA_HABITACION.valor_habitacion%TYPE;
    BEGIN
        validar(p_id_habitacion, p_fecha_in, p_fecha_out, p_huespedes);

        v_valor      := fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);
        p_id_reserva := seq_reserva.NEXTVAL;

        INSERT INTO RESERVA (id_reserva, id_usuario_sistema, id_cliente,
                             fecha_reserva, fecha_checkin, fecha_checkout, estado)
        VALUES (p_id_reserva, p_id_usuario, p_id_cliente,
                TRUNC(SYSDATE), TRUNC(p_fecha_in), TRUNC(p_fecha_out), 'PENDIENTE');

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes, valor_habitacion)
        VALUES (p_id_reserva, p_id_habitacion, p_huespedes, v_valor);
    END sp_crear_reserva;

    ------------------------------------------------------------------
    PROCEDURE sp_agregar_habitacion (
        p_id_reserva    IN NUMBER,
        p_id_habitacion IN NUMBER,
        p_huespedes     IN NUMBER
    ) IS
        v_in  RESERVA.fecha_checkin%TYPE;
        v_out RESERVA.fecha_checkout%TYPE;
    BEGIN
        BEGIN
            SELECT fecha_checkin, fecha_checkout
              INTO v_in, v_out
              FROM RESERVA
             WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20006, 'La reserva ' || p_id_reserva || ' no existe');
        END;

        validar(p_id_habitacion, v_in, v_out, p_huespedes, p_id_reserva);

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes, valor_habitacion)
        VALUES (p_id_reserva, p_id_habitacion, p_huespedes,
                fn_valor_estadia(p_id_habitacion, v_in, v_out));
    END sp_agregar_habitacion;

    ------------------------------------------------------------------
    -- LIQUIDACION MENSUAL POR ALOJAMIENTO (proceso masivo)
    -- Cursor explicito con parametros: c_liq(p_desde, p_hasta).
    -- Una reserva pertenece al mes de su checkin; las canceladas no cuentan.
    -- La comision de la plataforma es c_comision sobre habitaciones + servicios.
    -- Se puede relanzar el mismo mes: borra la liquidacion anterior de ese mes.
    -- No hace COMMIT: lo decide quien llama.
    ------------------------------------------------------------------
    PROCEDURE sp_liquidacion_mensual (
        p_anio IN NUMBER,
        p_mes  IN NUMBER
    ) IS
        CURSOR c_liq (p_desde DATE, p_hasta DATE) IS
            SELECT a.id_alojamiento,
                   a.nombre,
                   (SELECT COUNT(DISTINCT rh.id_reserva)
                      FROM RESERVA_HABITACION rh
                      JOIN RESERVA r    ON r.id_reserva    = rh.id_reserva
                      JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
                     WHERE h.id_alojamiento = a.id_alojamiento
                       AND r.estado <> 'CANCELADA'
                       AND r.fecha_checkin >= p_desde AND r.fecha_checkin < p_hasta) AS num_reservas,
                   (SELECT NVL(SUM(rh.valor_habitacion), 0)
                      FROM RESERVA_HABITACION rh
                      JOIN RESERVA r    ON r.id_reserva    = rh.id_reserva
                      JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
                     WHERE h.id_alojamiento = a.id_alojamiento
                       AND r.estado <> 'CANCELADA'
                       AND r.fecha_checkin >= p_desde AND r.fecha_checkin < p_hasta) AS ing_hab,
                   (SELECT NVL(SUM(rs.subtotal), 0)
                      FROM RESERVA_SERVICIO rs
                      JOIN SERVICIO s ON s.id_servicio = rs.id_servicio
                      JOIN RESERVA r  ON r.id_reserva  = rs.id_reserva
                     WHERE s.id_alojamiento = a.id_alojamiento
                       AND r.estado <> 'CANCELADA'
                       AND r.fecha_checkin >= p_desde AND r.fecha_checkin < p_hasta) AS ing_serv
              FROM ALOJAMIENTO a
             WHERE a.estado = 'ACTIVO'
             ORDER BY a.id_alojamiento;

        v_fila       c_liq%ROWTYPE;
        v_ini        DATE;
        v_fin        DATE;
        v_comision   NUMBER;
        v_procesados PLS_INTEGER;
        v_total_com  NUMBER := 0;
    BEGIN
        -- Se valida ANTES de armar la fecha (un mes 13 haria fallar TO_DATE)
        IF p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Mes invalido: ' || p_mes);
        END IF;

        v_ini := TO_DATE(p_anio || '-' || LPAD(p_mes, 2, '0') || '-01', 'YYYY-MM-DD');
        v_fin := ADD_MONTHS(v_ini, 1);   -- limite superior exclusivo

        DELETE FROM LIQUIDACION_MENSUAL WHERE anio = p_anio AND mes = p_mes;

        OPEN c_liq(v_ini, v_fin);
        LOOP
            FETCH c_liq INTO v_fila;
            EXIT WHEN c_liq%NOTFOUND;

            v_comision  := ROUND((v_fila.ing_hab + v_fila.ing_serv) * c_comision, 2);
            v_total_com := v_total_com + v_comision;

            INSERT INTO LIQUIDACION_MENSUAL
                (id_alojamiento, anio, mes, num_reservas, ingresos_habitaciones,
                 ingresos_servicios, comision, neto_alojamiento, fecha_proceso)
            VALUES
                (v_fila.id_alojamiento, p_anio, p_mes, v_fila.num_reservas, v_fila.ing_hab,
                 v_fila.ing_serv, v_comision, (v_fila.ing_hab + v_fila.ing_serv) - v_comision, SYSDATE);
        END LOOP;
        v_procesados := c_liq%ROWCOUNT;   -- filas leidas por el cursor
        CLOSE c_liq;

        DBMS_OUTPUT.PUT_LINE('Liquidacion ' || p_anio || '-' || LPAD(p_mes, 2, '0') || ': ' ||
                             v_procesados || ' alojamientos, comision total ' || v_total_com);
    EXCEPTION
        WHEN OTHERS THEN
            IF c_liq%ISOPEN THEN
                CLOSE c_liq;
            END IF;
            RAISE;
    END sp_liquidacion_mensual;

END pkg_turismo;
/

/* ------------------------------------------------------------
   2. DISPARADOR A NIVEL DE SENTENCIA: AUDITORIA DE TARIFA

   Un disparador de sentencia se ejecuta UNA vez por sentencia, pero no
   puede leer :OLD ni :NEW, y la auditoria pide el valor anterior y el nuevo.
   Por eso es un COMPOUND TRIGGER:
     - AFTER EACH ROW solo guarda en memoria (una coleccion) el antes y el
       despues de cada fila;
     - AFTER STATEMENT, el punto de sentencia, escribe la auditoria una sola
       vez al terminar la sentencia, con quien (usuario de la sesion) y cuando.
   Ejemplo: UPDATE TARIFA ... WHERE id_habitacion = 1 toca 3 filas y genera
   3 registros de auditoria, insertados en el AFTER STATEMENT.
   ------------------------------------------------------------ */
CREATE OR REPLACE TRIGGER trg_aud_tarifa
FOR INSERT OR UPDATE OF precio_noche OR DELETE ON TARIFA
COMPOUND TRIGGER

    TYPE t_aud_rec IS RECORD (
        operacion       VARCHAR2(10),
        id_tarifa       NUMBER,
        precio_anterior NUMBER(12,2),
        precio_nuevo    NUMBER(12,2)
    );
    TYPE t_aud_tab IS TABLE OF t_aud_rec INDEX BY PLS_INTEGER;
    g_aud t_aud_tab;

    BEFORE STATEMENT IS
    BEGIN
        g_aud.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
        v_n PLS_INTEGER := g_aud.COUNT + 1;
    BEGIN
        IF INSERTING THEN
            g_aud(v_n).operacion       := 'INSERT';
            g_aud(v_n).id_tarifa       := :NEW.id_tarifa;
            g_aud(v_n).precio_anterior := 0;                 -- no habia precio
            g_aud(v_n).precio_nuevo    := :NEW.precio_noche;
        ELSIF UPDATING THEN
            g_aud(v_n).operacion       := 'UPDATE';
            g_aud(v_n).id_tarifa       := :NEW.id_tarifa;
            g_aud(v_n).precio_anterior := :OLD.precio_noche;
            g_aud(v_n).precio_nuevo    := :NEW.precio_noche;
        ELSE
            g_aud(v_n).operacion       := 'DELETE';
            g_aud(v_n).id_tarifa       := :OLD.id_tarifa;
            g_aud(v_n).precio_anterior := :OLD.precio_noche;
            g_aud(v_n).precio_nuevo    := 0;                 -- ya no hay precio
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1 .. g_aud.COUNT LOOP
            INSERT INTO AUDITORIA_TARIFA
                (usuario, fecha, operacion, id_tarifa, precio_anterior, precio_nuevo)
            VALUES
                (SYS_CONTEXT('USERENV', 'SESSION_USER'), SYSDATE,
                 g_aud(i).operacion, g_aud(i).id_tarifa,
                 g_aud(i).precio_anterior, g_aud(i).precio_nuevo);
        END LOOP;
        g_aud.DELETE;
    END AFTER STATEMENT;

END trg_aud_tarifa;
/

/* ------------------------------------------------------------
   3. DISPARADORES A NIVEL DE FILA: NO SOLAPAR RESERVAS DE UNA HABITACION

   Las fechas viven en RESERVA y la habitacion en RESERVA_HABITACION, asi que
   un solape se puede crear por dos caminos:
     a) insertando (o cambiando) una fila de RESERVA_HABITACION   -> trg_rh_no_solape
     b) cambiando las fechas o reactivando una RESERVA existente   -> trg_reserva_no_solape

   Por que COMPOUND TRIGGER: un BEFORE INSERT ... FOR EACH ROW que consulte
   la misma tabla que se esta modificando lanza ORA-04091 (tabla mutante).
   La parte FOR EACH ROW registra cada fila afectada (:NEW) y la validacion
   se hace en AFTER STATEMENT, cuando la tabla ya se puede leer. Si hay solape,
   RAISE_APPLICATION_ERROR deshace la sentencia completa.
   ------------------------------------------------------------ */
CREATE OR REPLACE TRIGGER trg_rh_no_solape
FOR INSERT OR UPDATE OF id_reserva, id_habitacion ON RESERVA_HABITACION
COMPOUND TRIGGER

    TYPE t_par IS RECORD (id_reserva NUMBER, id_habitacion NUMBER);
    TYPE t_pares IS TABLE OF t_par INDEX BY PLS_INTEGER;
    g_pares t_pares;

    BEFORE STATEMENT IS
    BEGIN
        g_pares.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
        v_n PLS_INTEGER := g_pares.COUNT + 1;
    BEGIN
        g_pares(v_n).id_reserva    := :NEW.id_reserva;
        g_pares(v_n).id_habitacion := :NEW.id_habitacion;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_cnt NUMBER;
        v_res NUMBER;
        v_hab NUMBER;
    BEGIN
        FOR i IN 1 .. g_pares.COUNT LOOP
            v_res := g_pares(i).id_reserva;
            v_hab := g_pares(i).id_habitacion;

            SELECT COUNT(*)
              INTO v_cnt
              FROM RESERVA nueva
              JOIN RESERVA_HABITACION rh ON rh.id_habitacion = v_hab
                                        AND rh.id_reserva   <> nueva.id_reserva
              JOIN RESERVA otra          ON otra.id_reserva  = rh.id_reserva
             WHERE nueva.id_reserva     = v_res
               AND nueva.estado        <> 'CANCELADA'
               AND otra.estado         <> 'CANCELADA'
               AND otra.fecha_checkin   < nueva.fecha_checkout
               AND otra.fecha_checkout  > nueva.fecha_checkin;

            IF v_cnt > 0 THEN
                RAISE_APPLICATION_ERROR(-20005,
                    'La habitacion ' || v_hab ||
                    ' ya tiene una reserva que se solapa con la reserva ' || v_res);
            END IF;
        END LOOP;
        g_pares.DELETE;
    END AFTER STATEMENT;

END trg_rh_no_solape;
/

CREATE OR REPLACE TRIGGER trg_reserva_no_solape
FOR UPDATE OF fecha_checkin, fecha_checkout, estado ON RESERVA
COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_ids t_ids;

    BEFORE STATEMENT IS
    BEGIN
        g_ids.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        -- Cancelar una reserva nunca crea un solape: solo se revisan las activas
        IF :NEW.estado <> 'CANCELADA' THEN
            g_ids(g_ids.COUNT + 1) := :NEW.id_reserva;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_cnt NUMBER;
        v_res NUMBER;
    BEGIN
        FOR i IN 1 .. g_ids.COUNT LOOP
            v_res := g_ids(i);

            SELECT COUNT(*)
              INTO v_cnt
              FROM RESERVA nueva
              JOIN RESERVA_HABITACION mia ON mia.id_reserva    = nueva.id_reserva
              JOIN RESERVA_HABITACION rh  ON rh.id_habitacion  = mia.id_habitacion
                                         AND rh.id_reserva    <> nueva.id_reserva
              JOIN RESERVA otra           ON otra.id_reserva   = rh.id_reserva
             WHERE nueva.id_reserva     = v_res
               AND otra.estado         <> 'CANCELADA'
               AND otra.fecha_checkin   < nueva.fecha_checkout
               AND otra.fecha_checkout  > nueva.fecha_checkin;

            IF v_cnt > 0 THEN
                RAISE_APPLICATION_ERROR(-20005,
                    'Con las nuevas fechas la reserva ' || v_res ||
                    ' se solapa con otra reserva de la misma habitacion');
            END IF;
        END LOOP;
        g_ids.DELETE;
    END AFTER STATEMENT;

END trg_reserva_no_solape;
/

/* ------------------------------------------------------------
   4. RECALCULO DE VALORES
   La carga (02) dejo valor_habitacion y PAGO.valor provisionales. Se
   recalculan con fn_valor_estadia para que los ingresos sean coherentes
   con TARIFA y el calendario de temporadas.
   (trg_rh_no_solape no se dispara: solo vigila id_reserva e id_habitacion.)
   ------------------------------------------------------------ */
UPDATE RESERVA_HABITACION rh
   SET valor_habitacion = (SELECT pkg_turismo.fn_valor_estadia(rh.id_habitacion, r.fecha_checkin, r.fecha_checkout)
                             FROM RESERVA r
                            WHERE r.id_reserva = rh.id_reserva);

-- El pago de cada reserva = habitaciones + servicios
UPDATE PAGO p
   SET valor = (SELECT NVL(SUM(rh.valor_habitacion), 0) FROM RESERVA_HABITACION rh WHERE rh.id_reserva = p.id_reserva)
             + (SELECT NVL(SUM(rs.subtotal), 0)         FROM RESERVA_SERVICIO rs   WHERE rs.id_reserva = p.id_reserva);

COMMIT;

-- La vista materializada del script 03 quedo con los valores viejos:
-- se aplica su politica de refresco (COMPLETE ON DEMAND)
BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/

-- Verificacion: todos los objetos PL/SQL deben quedar VALID
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'SEQUENCE')
 ORDER BY object_type, object_name;

-- Si algo quedo INVALID, aqui sale el error de compilacion
SELECT name, type, line, position, text FROM user_errors ORDER BY name, sequence;
