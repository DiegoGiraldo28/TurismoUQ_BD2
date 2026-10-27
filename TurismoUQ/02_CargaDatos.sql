/* ============================================================
   TURISMOUQ - 02_CargaDatos.sql  (Oracle XE 21c, PL/SQL + DBMS_RANDOM)
   Volumen: 12 municipios, 60 alojamientos, 400 habitaciones, 3000 clientes,
            25000 reservas (2024-2026), 40000 lineas de servicios.

   Coherencia de los datos:
   - Temporadas generales ALTA / MEDIA / BAJA; el calendario (PERIODO_TEMPORADA)
     cubre cada dia de 2024 a 2028 sin huecos ni cruces.
   - Cada habitacion tiene una tarifa por temporada (ALTA > MEDIA > BAJA).
   - Las reservas de una misma habitacion NO se solapan.
   - Huespedes <= capacidad de la habitacion.
   - Los servicios de una reserva son del alojamiento donde se hospeda.
   - valor_habitacion y PAGO.valor son provisionales: se recalculan en
     04_CapaPLSQL.sql con fn_valor_estadia.
   - Todas las reservas tienen checkin entre 2024 y 2026.
   - Hay mas ocupacion en temporada ALTA que en MEDIA y BAJA (estacionalidad) y las
     reservas quedan repartidas parejo entre 2024 y 2026.
   - 800 reservas son futuras (desde el 26-oct-2026): hay estados PENDIENTE y CONFIRMADA.
   - Cliente, usuario, estado y metodo de pago se asignan con DBMS_RANDOM
     (sin patrones artificiales entre municipios, alojamientos y estados).
   ============================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- Semanas elegidas para las reservas: (habitacion, lunes de la semana)
    TYPE t_slot  IS RECORD (hab NUMBER, inicio DATE);
    TYPE t_slots IS TABLE OF t_slot;
    v_slots          t_slots;
    v_hab            NUMBER;
    v_cap            NUMBER;
    v_base           NUMBER;
    v_fecha_checkin  DATE;
    v_fecha_checkout DATE;
    v_fecha_reserva  DATE;
    v_estado         VARCHAR2(30);
    v_azar           NUMBER;

    -- Listas para generar nombres de clientes (sin tildes para no depender del juego de caracteres)
    TYPE t_txt IS TABLE OF VARCHAR2(30);
    v_fem  t_txt := t_txt('Maria','Luisa','Ana','Sofia','Valentina','Camila','Daniela','Laura','Paula','Juliana',
                          'Carolina','Natalia','Andrea','Catalina','Isabella','Mariana','Gabriela','Alejandra',
                          'Veronica','Diana','Lina','Sara','Manuela','Luz','Claudia','Sandra','Patricia',
                          'Johana','Viviana','Yesenia');
    v_masc t_txt := t_txt('Juan','Carlos','Andres','Santiago','Daniel','Camilo','David','Jorge','Luis','Felipe',
                          'Sebastian','Mateo','Nicolas','Alejandro','Julian','Diego','Miguel','Jhon','Oscar',
                          'Ricardo','Fabian','Cristian','Hector','Mauricio','Edwin','Jairo','Wilson','Alvaro',
                          'Esteban','Samuel');
    v_ape  t_txt := t_txt('Gomez','Rodriguez','Martinez','Lopez','Garcia','Hernandez','Gonzalez','Perez','Sanchez',
                          'Ramirez','Torres','Florez','Diaz','Vargas','Castro','Rojas','Moreno','Jimenez','Ospina',
                          'Restrepo','Arias','Giraldo','Marin','Salazar','Cardona','Zapata','Quintero','Betancur',
                          'Henao','Montoya','Osorio','Valencia','Ocampo','Ramos','Cruz','Mejia','Herrera',
                          'Aguirre','Duque','Londono');
    v_dom  t_txt := t_txt('gmail.com','gmail.com','gmail.com','gmail.com','hotmail.com','outlook.com','yahoo.com');
    v_dominio  VARCHAR2(30);
    v_nom1     VARCHAR2(30);
    v_nom2     VARCHAR2(30);
    v_ape1     VARCHAR2(30);
    v_ape2     VARCHAR2(30);
    v_nombres  VARCHAR2(60);

    -- Nombres de los 60 alojamientos. Clave = municipio * 10 + tipo
    -- (tipo: 1 Hotel, 2 Finca Cafetera, 3 Glamping, 4 Hostal, 5 Casa Campestre).
    -- Cada municipio tiene exactamente un alojamiento de cada tipo. Para usar un
    -- lugar real, cambia el texto de su linea (respetando municipio y tipo).
    TYPE t_nom_aloj IS TABLE OF VARCHAR2(80) INDEX BY PLS_INTEGER;
    v_aloj t_nom_aloj;
BEGIN
    DBMS_OUTPUT.PUT_LINE('INICIANDO GENERACION DE DATOS TURISMOUQ');

    -- 1. MUNICIPIOS (12)
    INSERT INTO MUNICIPIO VALUES (1,  'Armenia',    'Capital del departamento del Quindio');
    INSERT INTO MUNICIPIO VALUES (2,  'Calarca',    'Municipio turistico del Quindio');
    INSERT INTO MUNICIPIO VALUES (3,  'Circasia',   'Municipio del norte del Quindio');
    INSERT INTO MUNICIPIO VALUES (4,  'Filandia',   'Municipio turistico y cultural');
    INSERT INTO MUNICIPIO VALUES (5,  'Genova',     'Municipio del sur del Quindio');
    INSERT INTO MUNICIPIO VALUES (6,  'La Tebaida', 'Municipio cercano al aeropuerto El Eden');
    INSERT INTO MUNICIPIO VALUES (7,  'Montenegro', 'Municipio turistico del Quindio');
    INSERT INTO MUNICIPIO VALUES (8,  'Pijao',      'Municipio reconocido por su paisaje cafetero');
    INSERT INTO MUNICIPIO VALUES (9,  'Quimbaya',   'Municipio turistico del Quindio');
    INSERT INTO MUNICIPIO VALUES (10, 'Salento',    'Municipio turistico del Quindio');
    INSERT INTO MUNICIPIO VALUES (11, 'Buenavista', 'Municipio del Quindio');
    INSERT INTO MUNICIPIO VALUES (12, 'Cordoba',    'Municipio del Quindio');
    DBMS_OUTPUT.PUT_LINE('Municipios: 12');

    -- 2. TIPOS DE ALOJAMIENTO (5)
    INSERT INTO TIPO_ALOJAMIENTO VALUES (1, 'Hotel',          'Alojamiento hotelero tradicional');
    INSERT INTO TIPO_ALOJAMIENTO VALUES (2, 'Finca Cafetera', 'Finca turistica del paisaje cafetero');
    INSERT INTO TIPO_ALOJAMIENTO VALUES (3, 'Glamping',       'Alojamiento turistico tipo glamping');
    INSERT INTO TIPO_ALOJAMIENTO VALUES (4, 'Hostal',         'Alojamiento economico para turistas');
    INSERT INTO TIPO_ALOJAMIENTO VALUES (5, 'Casa Campestre', 'Alojamiento rural campestre');
    DBMS_OUTPUT.PUT_LINE('Tipos de alojamiento: 5');

    -- 3. CLIENTES (3000)
    --    Nombres y apellidos colombianos combinados al azar; el numero del cliente
    --    va en el correo para que sea unico (uk_cliente_email). Los dominios
    --    (gmail, hotmail, outlook, yahoo) se eligen al azar, con mas peso para gmail.
    FOR i IN 1..3000 LOOP
        IF DBMS_RANDOM.VALUE < 0.5 THEN
            v_nom1 := v_fem(TRUNC(DBMS_RANDOM.VALUE(1, v_fem.COUNT + 1)));
            v_nom2 := v_fem(TRUNC(DBMS_RANDOM.VALUE(1, v_fem.COUNT + 1)));
        ELSE
            v_nom1 := v_masc(TRUNC(DBMS_RANDOM.VALUE(1, v_masc.COUNT + 1)));
            v_nom2 := v_masc(TRUNC(DBMS_RANDOM.VALUE(1, v_masc.COUNT + 1)));
        END IF;
        v_ape1 := v_ape(TRUNC(DBMS_RANDOM.VALUE(1, v_ape.COUNT + 1)));
        v_ape2 := v_ape(TRUNC(DBMS_RANDOM.VALUE(1, v_ape.COUNT + 1)));

        IF DBMS_RANDOM.VALUE < 0.5 AND v_nom2 <> v_nom1 THEN
            v_nombres := v_nom1 || ' ' || v_nom2;      -- dos nombres
        ELSE
            v_nombres := v_nom1;                        -- un solo nombre
        END IF;

        v_dominio := v_dom(TRUNC(DBMS_RANDOM.VALUE(1, v_dom.COUNT + 1)));

        INSERT INTO CLIENTE (cedula, nombres, apellidos, telefono, email)
        VALUES (1000000000 + i, v_nombres, v_ape1 || ' ' || v_ape2,
                '3' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)), 9, '0'),
                LOWER(v_nom1) || '.' || LOWER(v_ape1) || i || '@' || v_dominio);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Clientes: 3000');

    -- 4. USUARIOS DEL SISTEMA (20)
    FOR i IN 1..20 LOOP
        INSERT INTO USUARIO_SISTEMA (id_usuario, nombre_usuario, nombre_completo, rol, email)
        VALUES (i, 'usuario_' || i, 'Administrador Turismo ' || i,
                CASE WHEN i <= 5 THEN 'ADMINISTRADOR' WHEN i <= 12 THEN 'OPERADOR' ELSE 'ASESOR' END,
                'usuario' || i || '@turismouq.com');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Usuarios del sistema: 20');

    -- 5. TEMPORADAS GENERALES (3)
    INSERT INTO TEMPORADA VALUES (1, 'ALTA',  'Periodos de mayor demanda turistica: festividades religiosas, vacaciones de mitad de año y de fin de año');
    INSERT INTO TEMPORADA VALUES (2, 'MEDIA', 'Periodos de demanda moderada: meses con puentes festivos y vacaciones cortas');
    INSERT INTO TEMPORADA VALUES (3, 'BAJA',  'Resto del año: demanda baja y tarifas mas economicas');
    DBMS_OUTPUT.PUT_LINE('Temporadas: 3');

    -- 5b. CALENDARIO DE TEMPORADAS: se clasifica cada dia de 2024 a 2028 y se
    --     agrupan los dias consecutivos de la misma temporada en un periodo
    --     ("gaps and islands"). Resultado: calendario completo, sin cruces.
    INSERT INTO PERIODO_TEMPORADA (id_periodo, id_temporada, fecha_inicio, fecha_fin)
    SELECT ROWNUM, id_temporada, fecha_inicio, fecha_fin
      FROM (SELECT id_temporada, MIN(dia) AS fecha_inicio, MAX(dia) AS fecha_fin
              FROM (SELECT dia, id_temporada,
                           dia - ROW_NUMBER() OVER (PARTITION BY id_temporada ORDER BY dia) AS grupo
                      FROM (SELECT d.dia,
                                   CASE
                                       -- ALTA: Semana Santa (rangos por año)
                                       WHEN d.dia BETWEEN DATE '2024-03-25' AND DATE '2024-04-07'
                                         OR d.dia BETWEEN DATE '2025-04-01' AND DATE '2025-04-20'
                                         OR d.dia BETWEEN DATE '2026-03-20' AND DATE '2026-04-10'
                                         OR d.dia BETWEEN DATE '2027-03-22' AND DATE '2027-04-04'
                                         OR d.dia BETWEEN DATE '2028-04-10' AND DATE '2028-04-23'
                                         -- ALTA: mitad de año (15-jun a 31-jul)
                                         OR TO_CHAR(d.dia, 'MMDD') BETWEEN '0615' AND '0731'
                                         -- ALTA: fin de año (15-dic a 15-ene)
                                         OR TO_CHAR(d.dia, 'MMDD') >= '1215'
                                         OR TO_CHAR(d.dia, 'MMDD') <= '0115' THEN 1
                                       -- MEDIA: agosto y octubre (puentes festivos)
                                       WHEN EXTRACT(MONTH FROM d.dia) IN (8, 10) THEN 2
                                       -- BAJA: todo lo demas
                                       ELSE 3
                                   END AS id_temporada
                              FROM (SELECT DATE '2024-01-01' + LEVEL - 1 AS dia
                                      FROM dual CONNECT BY LEVEL <= 1827) d))
             GROUP BY id_temporada, grupo
             ORDER BY MIN(dia));
    DBMS_OUTPUT.PUT_LINE('Periodos de temporada: ' || SQL%ROWCOUNT);

    -- 6. ALOJAMIENTOS (60): 5 por municipio, uno de cada tipo
    --    Armenia (1)
    v_aloj(11) := 'Hotel Portal del Cafe';         v_aloj(12) := 'Finca Cafetera El Mirador';
    v_aloj(13) := 'Glamping Nubes de Armenia';     v_aloj(14) := 'Hostal La Ceiba';
    v_aloj(15) := 'Casa Campestre Los Guaduales';
    --    Calarca (2)
    v_aloj(21) := 'Hotel Mirador de Calarca';      v_aloj(22) := 'Finca Cafetera La Aurora';
    v_aloj(23) := 'Glamping Bosque de Niebla';     v_aloj(24) := 'Hostal El Cafetal';
    v_aloj(25) := 'Casa Campestre Villa Barcelona';
    --    Circasia (3)
    v_aloj(31) := 'Hotel Plaza Circasia';          v_aloj(32) := 'Finca Cafetera Los Naranjos';
    v_aloj(33) := 'Glamping Cielo Abierto';        v_aloj(34) := 'Hostal La Estacion';
    v_aloj(35) := 'Casa Campestre El Saman';
    --    Filandia (4)
    v_aloj(41) := 'Hotel Balcon de Filandia';      v_aloj(42) := 'Finca Cafetera San Lorenzo';
    v_aloj(43) := 'Glamping Luna de Cafe';         v_aloj(44) := 'Hostal La Plazuela';
    v_aloj(45) := 'Casa Campestre Los Cambulos';
    --    Genova (5)
    v_aloj(51) := 'Hotel Villa Genova';            v_aloj(52) := 'Finca Cafetera La Esperanza';
    v_aloj(53) := 'Glamping Altos del Rio';        v_aloj(54) := 'Hostal El Viajero';
    v_aloj(55) := 'Casa Campestre La Cabana';
    --    La Tebaida (6)
    v_aloj(61) := 'Hotel Campestre El Eden';       v_aloj(62) := 'Finca Cafetera Las Acacias';
    v_aloj(63) := 'Glamping Sol Naciente';         v_aloj(64) := 'Hostal La Pista';
    v_aloj(65) := 'Casa Campestre Villa Tebaida';
    --    Montenegro (7)
    v_aloj(71) := 'Hotel Hacienda Montenegro';     v_aloj(72) := 'Finca Cafetera El Paraiso';
    v_aloj(73) := 'Glamping Canto del Rio';        v_aloj(74) := 'Hostal Camino Real';
    v_aloj(75) := 'Casa Campestre Las Heliconias';
    --    Pijao (8)
    v_aloj(81) := 'Hotel Casa del Pijao';          v_aloj(82) := 'Finca Cafetera La Cumbre';
    v_aloj(83) := 'Glamping Cumbres Verdes';       v_aloj(84) := 'Hostal La Pausa';
    v_aloj(85) := 'Casa Campestre El Mirlo';
    --    Quimbaya (9)
    v_aloj(91) := 'Hotel Quimbaya Real';           v_aloj(92) := 'Finca Cafetera Los Arrayanes';
    v_aloj(93) := 'Glamping Brisa Verde';          v_aloj(94) := 'Hostal El Sombrero';
    v_aloj(95) := 'Casa Campestre La Palma';
    --    Salento (10)
    v_aloj(101) := 'Hotel Mirador del Cocora';     v_aloj(102) := 'Finca Cafetera El Ocaso';
    v_aloj(103) := 'Glamping Palmas de Cera';      v_aloj(104) := 'Hostal El Trapiche';
    v_aloj(105) := 'Casa Campestre Los Nogales';
    --    Buenavista (11)
    v_aloj(111) := 'Hotel Balcon del Quindio';     v_aloj(112) := 'Finca Cafetera Alto Bonito';
    v_aloj(113) := 'Glamping Horizonte';           v_aloj(114) := 'Hostal La Parada';
    v_aloj(115) := 'Casa Campestre Miralindo';
    --    Cordoba (12)
    v_aloj(121) := 'Hotel Cordoba Real';           v_aloj(122) := 'Finca Cafetera La Palmera';
    v_aloj(123) := 'Glamping Rio Verde';           v_aloj(124) := 'Hostal El Descanso';
    v_aloj(125) := 'Casa Campestre Las Camelias';

    FOR i IN 1..60 LOOP
        INSERT INTO ALOJAMIENTO (id_alojamiento, id_municipio, id_tipo_alojamiento, nombre, direccion,
                                 telefono, correo, capacidad_total, estado)
        VALUES (i, MOD(i - 1, 12) + 1, MOD(i - 1, 5) + 1,
                v_aloj((MOD(i - 1, 12) + 1) * 10 + MOD(i - 1, 5) + 1),
                'Carrera ' || MOD(i, 20) || ' # ' || MOD(i, 80) || '-' || MOD(i, 50),
                '6' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)), 9, '0'),
                'alojamiento' || i || '@turismouq.com', TRUNC(DBMS_RANDOM.VALUE(10, 80)), 'ACTIVO');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Alojamientos: 60');

    -- 7. HABITACIONES (400)
    FOR i IN 1..400 LOOP
        INSERT INTO HABITACION (id_habitacion, id_alojamiento, numero, tipo_habitacion, capacidad, estado, descripcion)
        VALUES (i, MOD(i - 1, 60) + 1, 'H-' || LPAD(i, 4, '0'),
                CASE MOD(i, 4) WHEN 0 THEN 'Individual' WHEN 1 THEN 'Doble' WHEN 2 THEN 'Familiar' ELSE 'Suite' END,
                CASE MOD(i, 4) WHEN 0 THEN 1 WHEN 1 THEN 2 WHEN 2 THEN 4 ELSE 3 END,
                'DISPONIBLE', 'Habitacion turistica TurismoUQ ' || i);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Habitaciones: 400');

    -- 8. SERVICIOS (120: dos por alojamiento; servicio s pertenece al alojamiento MOD(s-1,60)+1)
    FOR i IN 1..120 LOOP
        INSERT INTO SERVICIO (id_servicio, id_alojamiento, nombre, descripcion, precio, estado)
        VALUES (i, MOD(i - 1, 60) + 1,
                CASE MOD(i, 6) WHEN 0 THEN 'Desayuno' WHEN 1 THEN 'Almuerzo' WHEN 2 THEN 'Cena'
                               WHEN 3 THEN 'Transporte' WHEN 4 THEN 'Tour cafetero' ELSE 'Piscina' END || ' ' || i,
                'Servicio turistico complementario', ROUND(DBMS_RANDOM.VALUE(15000, 180000), -2), 'ACTIVO');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Servicios: 120');

    -- 9. TARIFAS: 400 habitaciones x 3 temporadas = 1200 (ALTA > MEDIA > BAJA)
    FOR h IN 1..400 LOOP
        v_base := ROUND(DBMS_RANDOM.VALUE(80000, 220000), -3);
        INSERT INTO TARIFA VALUES ((h - 1) * 3 + 1, h, 1, ROUND(v_base * 1.60, -3));  -- ALTA
        INSERT INTO TARIFA VALUES ((h - 1) * 3 + 2, h, 2, ROUND(v_base * 1.25, -3));  -- MEDIA
        INSERT INTO TARIFA VALUES ((h - 1) * 3 + 3, h, 3, v_base);                    -- BAJA
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Tarifas: 1200');

    -- 10-11. RESERVAS (25000) y RESERVA_HABITACION (25000)
    --        El tiempo de cada habitacion se divide en SEMANAS. Cada reserva ocupa
    --        una semana distinta de su habitacion: entra entre el dia 0 y el 2 de la
    --        semana y dura de 1 a 4 noches, asi que termina antes de que empiece la
    --        semana siguiente (no hay solapes).
    --        - Historico (24200 reservas): se eligen al azar semanas entre el
    --          01-ene-2024 y el 25-oct-2026. Las semanas de temporada ALTA pesan 3,
    --          las de MEDIA 1.8 y las de BAJA 1, asi que hay mas reservas en ALTA
    --          (estacionalidad) y quedan repartidas parejo en los 3 años.
    --        - Futuras (800 reservas): semanas entre el 26-oct y el 20-dic de 2026,
    --          para que existan reservas PENDIENTE y CONFIRMADA ademas de FINALIZADA
    --          y CANCELADA.
    --        Cliente, usuario y estado se eligen al azar (DBMS_RANDOM).
    SELECT hab, inicio
      BULK COLLECT INTO v_slots
      FROM (SELECT hab, inicio
              FROM (SELECT s.hab, s.inicio
                      FROM (SELECT h.id_habitacion AS hab,
                                   DATE '2024-01-01' + 7 * (w.n - 1) AS inicio
                              FROM HABITACION h
                             CROSS JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 147) w) s
                      JOIN PERIODO_TEMPORADA p ON s.inicio BETWEEN p.fecha_inicio AND p.fecha_fin
                     ORDER BY DBMS_RANDOM.VALUE / CASE p.id_temporada WHEN 1 THEN 3 WHEN 2 THEN 1.8 ELSE 1 END
                     FETCH FIRST 24200 ROWS ONLY)
            UNION ALL
            SELECT hab, inicio
              FROM (SELECT h.id_habitacion AS hab,
                           DATE '2026-10-26' + 7 * (w.n - 1) AS inicio
                      FROM HABITACION h
                     CROSS JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 8) w
                     ORDER BY DBMS_RANDOM.VALUE
                     FETCH FIRST 800 ROWS ONLY))
     ORDER BY inicio, hab;

    FOR i IN 1..v_slots.COUNT LOOP
        v_hab := v_slots(i).hab;
        v_cap := CASE MOD(v_hab, 4) WHEN 0 THEN 1 WHEN 1 THEN 2 WHEN 2 THEN 4 ELSE 3 END;

        v_fecha_checkin  := v_slots(i).inicio + TRUNC(DBMS_RANDOM.VALUE(0, 3));   -- dia 0, 1 o 2
        v_fecha_checkout := v_fecha_checkin + TRUNC(DBMS_RANDOM.VALUE(1, 5));     -- 1 a 4 noches
        -- La reserva se hizo antes del checkin, pero nunca en el futuro
        v_fecha_reserva  := LEAST(v_fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(1, 31)), TRUNC(SYSDATE));

        -- Estado coherente con la fecha: lo que ya paso esta FINALIZADA (o se
        -- cancelo); lo que aun no llega esta CONFIRMADA, PENDIENTE o CANCELADA.
        v_azar := DBMS_RANDOM.VALUE;      -- un solo numero al azar en [0, 1)
        IF v_fecha_checkout <= TRUNC(SYSDATE) THEN
            IF v_azar < 0.88 THEN v_estado := 'FINALIZADA';
            ELSE                  v_estado := 'CANCELADA';
            END IF;
        ELSE
            IF    v_azar < 0.10 THEN v_estado := 'CANCELADA';
            ELSIF v_azar < 0.40 THEN v_estado := 'PENDIENTE';
            ELSE                     v_estado := 'CONFIRMADA';
            END IF;
        END IF;

        INSERT INTO RESERVA (id_reserva, id_usuario_sistema, id_cliente, fecha_reserva,
                             fecha_checkin, fecha_checkout, estado)
        VALUES (i, TRUNC(DBMS_RANDOM.VALUE(1, 21)), 1000000000 + TRUNC(DBMS_RANDOM.VALUE(1, 3001)),
                v_fecha_reserva, v_fecha_checkin, v_fecha_checkout, v_estado);

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes, valor_habitacion)
        VALUES (i, v_hab, TRUNC(DBMS_RANDOM.VALUE(1, v_cap + 1)), ROUND(DBMS_RANDOM.VALUE(80000, 450000), -3));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Reservas: ' || v_slots.COUNT);
    DBMS_OUTPUT.PUT_LINE('Reserva_Habitacion: ' || v_slots.COUNT);

    -- 12. RESERVA_SERVICIO (40000 lineas)
    --     Cada alojamiento A tiene dos servicios: el A y el A + 60.
    --     El alojamiento se toma de la habitacion que la reserva realmente ocupa
    --     (RESERVA_HABITACION -> HABITACION), asi los servicios siempre son del
    --     lugar donde se hospeda el cliente.
    --       - Las 25000 reservas consumen el servicio A.
    --       - 15000 reservas elegidas al azar consumen ademas el servicio A + 60.
    --     ROWNUM en cada rama evita que Oracle recalcule DBMS_RANDOM (asi el
    --     subtotal siempre es cantidad x precio).
    INSERT INTO RESERVA_SERVICIO (id_reserva, id_servicio, cantidad, precio_unitario, subtotal)
    SELECT x.id_reserva, s.id_servicio, x.cantidad, s.precio, x.cantidad * s.precio
      FROM (SELECT rh.id_reserva, h.id_alojamiento AS aloj,
                   TRUNC(DBMS_RANDOM.VALUE(1, 4)) AS cantidad, 0 AS extra, ROWNUM AS rn
              FROM RESERVA_HABITACION rh
              JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
            UNION ALL
            SELECT rh.id_reserva, h.id_alojamiento,
                   TRUNC(DBMS_RANDOM.VALUE(1, 4)), 60, ROWNUM
              FROM RESERVA_HABITACION rh
              JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
             WHERE rh.id_reserva IN (SELECT id_reserva
                                       FROM (SELECT id_reserva FROM RESERVA ORDER BY DBMS_RANDOM.VALUE)
                                      WHERE ROWNUM <= 15000)) x
      JOIN SERVICIO s ON s.id_servicio = x.aloj + x.extra;
    DBMS_OUTPUT.PUT_LINE('Reserva_Servicio: ' || SQL%ROWCOUNT);

    -- 13. PAGOS (25000, uno por reserva; el valor real se fija en el script 04)
    --     Metodo de pago al azar (TARJETA 35 %, PSE 30 %, TRANSFERENCIA 20 %, EFECTIVO 15 %).
    --     Estado del pago segun la reserva: cancelada -> REEMBOLSADO,
    --     pendiente -> PENDIENTE, confirmada o finalizada -> PAGADO.
    INSERT INTO PAGO (id_pago, id_reserva, fecha_pago, valor, metodo_pago, estado)
    --     El numero al azar se calcula una vez por fila en la subconsulta (ROWNUM
    --     evita que Oracle la fusione y lo recalcule en cada WHEN).
    SELECT x.id_reserva, x.id_reserva, x.fecha_reserva, ROUND(DBMS_RANDOM.VALUE(100000, 1500000), -3),
           CASE WHEN x.azar < 0.15 THEN 'EFECTIVO'
                WHEN x.azar < 0.35 THEN 'TRANSFERENCIA'
                WHEN x.azar < 0.65 THEN 'PSE'
                ELSE 'TARJETA' END,
           CASE x.estado WHEN 'CANCELADA' THEN 'REEMBOLSADO'
                         WHEN 'PENDIENTE' THEN 'PENDIENTE'
                         ELSE 'PAGADO' END
      FROM (SELECT r.id_reserva, r.fecha_reserva, r.estado, DBMS_RANDOM.VALUE AS azar, ROWNUM AS rn
              FROM RESERVA r) x;
    DBMS_OUTPUT.PUT_LINE('Pagos: ' || SQL%ROWCOUNT);

    -- 14. RESENAS (8000)
    FOR i IN 1..8000 LOOP
        INSERT INTO RESENA (id_resena, cedula_cliente, id_alojamiento, calificacion, comentario, fecha_resena)
        VALUES (i, MOD(i - 1, 3000) + 1 + 1000000000, MOD(i - 1, 60) + 1, TRUNC(DBMS_RANDOM.VALUE(1, 6)),
                CASE MOD(i, 5) WHEN 0 THEN 'Excelente experiencia' WHEN 1 THEN 'Muy buen alojamiento'
                               WHEN 2 THEN 'Buena atencion' WHEN 3 THEN 'Lugar agradable'
                               ELSE 'Experiencia turistica satisfactoria' END,
                DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 1095)));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Resenas: 8000');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('GENERACION TERMINADA CORRECTAMENTE');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        RAISE;
END;
/

-- Verificaciones rapidas
SELECT 'MUNICIPIO' AS tabla, COUNT(*) AS filas FROM MUNICIPIO
UNION ALL SELECT 'ALOJAMIENTO', COUNT(*) FROM ALOJAMIENTO
UNION ALL SELECT 'HABITACION', COUNT(*) FROM HABITACION
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'RESERVA', COUNT(*) FROM RESERVA
UNION ALL SELECT 'RESERVA_SERVICIO', COUNT(*) FROM RESERVA_SERVICIO;

-- Rango de fechas de las reservas (debe quedar dentro de 2024-2026)
SELECT MIN(fecha_checkin) AS primer_checkin, MAX(fecha_checkin) AS ultimo_checkin FROM RESERVA;

-- Reparto de estados y de metodos de pago
SELECT estado, COUNT(*) AS reservas FROM RESERVA GROUP BY estado ORDER BY estado;
SELECT metodo_pago, COUNT(*) AS pagos FROM PAGO GROUP BY metodo_pago ORDER BY metodo_pago;

-- Controles de coherencia: los dos deben dar 0
SELECT COUNT(*) AS reservas_solapadas
  FROM RESERVA_HABITACION a
  JOIN RESERVA_HABITACION b ON b.id_habitacion = a.id_habitacion AND b.id_reserva > a.id_reserva
  JOIN RESERVA ra ON ra.id_reserva = a.id_reserva
  JOIN RESERVA rb ON rb.id_reserva = b.id_reserva
 WHERE ra.fecha_checkin < rb.fecha_checkout
   AND ra.fecha_checkout > rb.fecha_checkin;

SELECT COUNT(*) AS servicios_de_otro_alojamiento
  FROM RESERVA_SERVICIO rs
  JOIN SERVICIO s            ON s.id_servicio    = rs.id_servicio
  JOIN RESERVA_HABITACION rh ON rh.id_reserva    = rs.id_reserva
  JOIN HABITACION h          ON h.id_habitacion  = rh.id_habitacion
 WHERE s.id_alojamiento <> h.id_alojamiento;

SELECT t.nombre AS temporada, p.fecha_inicio, p.fecha_fin
  FROM PERIODO_TEMPORADA p JOIN TEMPORADA t ON t.id_temporada = p.id_temporada
 WHERE p.fecha_inicio < DATE '2026-01-01' AND p.fecha_fin >= DATE '2025-01-01'
 ORDER BY p.fecha_inicio;