-- =============================================================
-- CONSULTA 1: Ocupacion por municipio y mes, con PIVOT
-- =============================================================
SELECT *
FROM (
    SELECT m.nombre AS municipio,
           EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
           rh.id_reserva
    FROM RESERVA_HABITACION rh
    JOIN RESERVA r ON r.id_reserva = rh.id_reserva
    JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
    JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m ON m.id_municipio = a.id_municipio
)
PIVOT (
    COUNT(id_reserva)
    FOR mes IN (1 AS ENE, 2 AS FEB, 3 AS MAR, 4 AS ABR, 5 AS MAY, 6 AS JUN, 7 AS JUL, 8 AS AGO, 9 AS SEP, 10 AS OCT, 11 AS NOV, 12 AS DIC)
)
ORDER BY municipio;

-- =============================================================
-- CONSULTA 2: Ingresos por municipio, tipo de alojamiento y temporada, con ROLLUP
-- =============================================================
SELECT m.nombre AS municipio,
       ta.nombre AS tipo_alojamiento,
       t.nombre AS temporada,
       SUM(rh.valor_habitacion) AS ingresos,
       GROUPING(m.nombre) AS es_subtotal_municipio,
       GROUPING(ta.nombre) AS es_subtotal_tipo,
       GROUPING(t.nombre) AS es_subtotal_temporada
FROM RESERVA_HABITACION rh
JOIN RESERVA r ON r.id_reserva = rh.id_reserva
JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
JOIN MUNICIPIO m ON m.id_municipio = a.id_municipio
JOIN TIPO_ALOJAMIENTO ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
JOIN TEMPORADA t ON r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
GROUP BY ROLLUP(m.nombre, ta.nombre, t.nombre)
ORDER BY municipio, tipo_alojamiento, temporada;

-- =============================================================
-- CONSULTA 3: Top 3 alojamientos de mayor ingreso por municipio (RANK con PARTITION BY)
-- =============================================================
SELECT municipio, alojamiento, ingresos, ranking
FROM (
    SELECT m.nombre AS municipio,
           a.nombre AS alojamiento,
           SUM(rh.valor_habitacion) AS ingresos,
           RANK() OVER (PARTITION BY m.id_municipio ORDER BY SUM(rh.valor_habitacion) DESC) AS ranking
    FROM RESERVA_HABITACION rh
    JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
    JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m ON m.id_municipio = a.id_municipio
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)
WHERE ranking <= 3
ORDER BY municipio, ranking;

-- =============================================================
-- CONSULTA 4: Variacion de ingresos mes contra mes (LAG)
-- =============================================================
SELECT anio, mes, ingresos,
       LAG(ingresos) OVER (ORDER BY anio, mes) AS ingresos_mes_anterior,
       ingresos - LAG(ingresos) OVER (ORDER BY anio, mes) AS variacion,
       ROUND((ingresos - LAG(ingresos) OVER (ORDER BY anio, mes)) / LAG(ingresos) OVER (ORDER BY anio, mes) * 100, 2) AS variacion_pct
FROM (
    SELECT EXTRACT(YEAR FROM r.fecha_checkin) AS anio,
           EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
           SUM(rh.valor_habitacion) AS ingresos
    FROM RESERVA_HABITACION rh
    JOIN RESERVA r ON r.id_reserva = rh.id_reserva
    GROUP BY EXTRACT(YEAR FROM r.fecha_checkin), EXTRACT(MONTH FROM r.fecha_checkin)
)
ORDER BY anio, mes;

-- =============================================================
-- CONSULTA 5: Consulta parametrizada con variables de enlace
-- =============================================================
VARIABLE b_fecha_inicio VARCHAR2(10)
VARIABLE b_fecha_fin VARCHAR2(10)
EXEC :b_fecha_inicio := '2025-01-01';
EXEC :b_fecha_fin := '2025-12-31';

SELECT r.id_reserva,
       c.nombres || ' ' || c.apellidos AS cliente,
       r.fecha_checkin,
       r.fecha_checkout,
       rh.valor_habitacion,
       r.estado
FROM RESERVA r
JOIN CLIENTE c ON c.cedula = r.id_cliente
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE r.fecha_checkin BETWEEN TO_DATE(:b_fecha_inicio,'YYYY-MM-DD') AND TO_DATE(:b_fecha_fin,'YYYY-MM-DD')
ORDER BY r.fecha_checkin;

-- =============================================================
-- CONSULTA 6: Vista materializada de ocupacion mensual
-- (La creacion de la vista se ejecuta sola)
-- =============================================================
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT m.id_municipio,
       m.nombre AS municipio,
       EXTRACT(YEAR FROM r.fecha_checkin) AS anio,
       EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
       COUNT(*) AS reservas,
       SUM(rh.valor_habitacion) AS ingresos
FROM RESERVA_HABITACION rh
JOIN RESERVA r ON r.id_reserva = rh.id_reserva
JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
JOIN MUNICIPIO m ON m.id_municipio = a.id_municipio
GROUP BY m.id_municipio, m.nombre, EXTRACT(YEAR FROM r.fecha_checkin), EXTRACT(MONTH FROM r.fecha_checkin);

-- (Ejecuta esta linea por separado para consultar la vista ya creada)
SELECT * FROM mv_ocupacion_mensual ORDER BY municipio, anio, mes;

-- =============================================================
-- CONSULTA 7: UNPIVOT
-- =============================================================
SELECT municipio, metodo_pago, total
FROM (
    SELECT m.nombre AS municipio,
           SUM(CASE WHEN p.metodo_pago = 'TARJETA' THEN p.valor ELSE 0 END) AS TARJETA,
           SUM(CASE WHEN p.metodo_pago = 'TRANSFERENCIA' THEN p.valor ELSE 0 END) AS TRANSFERENCIA,
           SUM(CASE WHEN p.metodo_pago = 'PSE' THEN p.valor ELSE 0 END) AS PSE,
           SUM(CASE WHEN p.metodo_pago = 'EFECTIVO' THEN p.valor ELSE 0 END) AS EFECTIVO
    FROM PAGO p
    JOIN RESERVA r ON r.id_reserva = p.id_reserva
    JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
    JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
    JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m ON m.id_municipio = a.id_municipio
    GROUP BY m.nombre
)
UNPIVOT (
    total FOR metodo_pago IN (TARJETA, TRANSFERENCIA, PSE, EFECTIVO)
)
ORDER BY municipio, metodo_pago;

-- =============================================================
-- CONSULTA 8: Consulta libre (Top 5 clientes VIP)
-- =============================================================
SELECT *
FROM (
    SELECT c.cedula,
           c.nombres || ' ' || c.apellidos AS cliente,
           COUNT(*) AS num_reservas,
           SUM(t.total_reserva) AS gasto_total
    FROM CLIENTE c
    JOIN (
        SELECT r.id_reserva,
               r.id_cliente,
               NVL(rh.total_habitacion,0) + NVL(rs.total_servicio,0) AS total_reserva
        FROM RESERVA r
        LEFT JOIN (SELECT id_reserva, SUM(valor_habitacion) AS total_habitacion FROM RESERVA_HABITACION GROUP BY id_reserva) rh ON rh.id_reserva = r.id_reserva
        LEFT JOIN (SELECT id_reserva, SUM(subtotal) AS total_servicio FROM RESERVA_SERVICIO GROUP BY id_reserva) rs ON rs.id_reserva = r.id_reserva
    ) t ON t.id_cliente = c.cedula
    GROUP BY c.cedula, c.nombres, c.apellidos
    ORDER BY gasto_total DESC
)
WHERE ROWNUM <= 5;