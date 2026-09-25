-- CARGA DE DATOS TURISMO UQ 
-- TURISMOUQ - GENERACION MASIVA DE DATOS - Oracle XE 21c
-- PL/SQL + DBMS_RANDOM 
-- Volumen minimo: 12 municipios, 60 alojamientos, 400 habitaciones, 3000 clientes, 25000 reservas, 40000 lineas de servicios 

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE 
    v_fecha_checkin  DATE; 
    v_fecha_checkout DATE; 
    v_fecha_reserva  DATE; 
    v_id_habitacion  NUMBER; 
    v_id_servicio    NUMBER; 
    v_id_reserva     NUMBER; 
    v_cantidad       NUMBER; 
    v_precio         NUMBER; 
BEGIN 
    DBMS_OUTPUT.PUT_LINE('INICIANDO GENERACION DE DATOS TURISMOUQ'); 
    
    -- 1. MUNICIPIOS - 12 registros 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (1, 'Armenia', 'Capital del departamento del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (2, 'Calarca', 'Municipio turistico del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (3, 'Circasia', 'Municipio del norte del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (4, 'Filandia', 'Municipio turistico y cultural'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (5, 'Genova', 'Municipio del sur del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (6, 'La Tebaida', 'Municipio cercano al aeropuerto El Eden'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (7, 'Montenegro', 'Municipio turistico del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (8, 'Pijao', 'Municipio reconocido por su paisaje cafetero'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (9, 'Quimbaya', 'Municipio turistico del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (10, 'Salento', 'Municipio turistico del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (11, 'Buenavista', 'Municipio del Quindio'); 
    INSERT INTO MUNICIPIO (id_municipio, nombre, descripcion) VALUES (12, 'Cordoba', 'Municipio del Quindio'); 
    DBMS_OUTPUT.PUT_LINE('Municipios: 12'); 
    
    -- 2. TIPOS DE ALOJAMIENTO - 5 registros 
    INSERT INTO TIPO_ALOJAMIENTO (id_tipo_alojamiento, nombre, descripcion) VALUES (1, 'Hotel', 'Alojamiento hotelero tradicional'); 
    INSERT INTO TIPO_ALOJAMIENTO (id_tipo_alojamiento, nombre, descripcion) VALUES (2, 'Finca Cafetera', 'Finca turistica del paisaje cafetero'); 
    INSERT INTO TIPO_ALOJAMIENTO (id_tipo_alojamiento, nombre, descripcion) VALUES (3, 'Glamping', 'Alojamiento turistico tipo glamping'); 
    INSERT INTO TIPO_ALOJAMIENTO (id_tipo_alojamiento, nombre, descripcion) VALUES (4, 'Hostal', 'Alojamiento economico para turistas'); 
    INSERT INTO TIPO_ALOJAMIENTO (id_tipo_alojamiento, nombre, descripcion) VALUES (5, 'Casa Campestre', 'Alojamiento rural campestre'); 
    DBMS_OUTPUT.PUT_LINE('Tipos de alojamiento: 5'); 
    
    -- 3. CLIENTES - 3000 registros 
    FOR i IN 1..3000 LOOP 
        INSERT INTO CLIENTE (cedula, nombres, apellidos, telefono, email) 
        VALUES (1000000000 + i, 'Cliente' || i, 'Turismo' || i, '3' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100000000,999999999)),9,'0'), 'cliente' || i || '@turismouq.com'); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Clientes: 3000'); 
    
    -- 4. USUARIOS DEL SISTEMA - 20 registros 
    FOR i IN 1..20 LOOP 
        INSERT INTO USUARIO_SISTEMA (id_usuario, nombre_usuario, nombre_completo, rol, email) 
        VALUES (i, 'usuario_' || i, 'Administrador Turismo ' || i, 
                CASE WHEN i <= 5 THEN 'ADMINISTRADOR' 
                     WHEN i <= 12 THEN 'OPERADOR' 
                     ELSE 'ASESOR' END, 
                'usuario' || i || '@turismouq.com'); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Usuarios del sistema: 20'); 
    
    -- 5. TEMPORADAS - 9 registros 
    INSERT INTO TEMPORADA VALUES (1, 'Semana Santa 2024', DATE '2024-03-25', DATE '2024-04-07', 'Temporada alta de Semana Santa 2024'); 
    INSERT INTO TEMPORADA VALUES (2, 'Mitad de ano 2024', DATE '2024-06-15', DATE '2024-07-31', 'Temporada alta de mitad de ano 2024'); 
    INSERT INTO TEMPORADA VALUES (3, 'Fin de ano 2024', DATE '2024-12-15', DATE '2025-01-15', 'Temporada alta de fin de ano 2024'); 
    INSERT INTO TEMPORADA VALUES (4, 'Semana Santa 2025', DATE '2025-04-01', DATE '2025-04-20', 'Temporada alta de Semana Santa 2025'); 
    INSERT INTO TEMPORADA VALUES (5, 'Mitad de ano 2025', DATE '2025-06-15', DATE '2025-07-31', 'Temporada alta de mitad de ano 2025'); 
    INSERT INTO TEMPORADA VALUES (6, 'Fin de ano 2025', DATE '2025-12-15', DATE '2026-01-15', 'Temporada alta de fin de ano 2025'); 
    INSERT INTO TEMPORADA VALUES (7, 'Semana Santa 2026', DATE '2026-03-20', DATE '2026-04-10', 'Temporada alta de Semana Santa 2026'); 
    INSERT INTO TEMPORADA VALUES (8, 'Mitad de ano 2026', DATE '2026-06-15', DATE '2026-07-31', 'Temporada alta de mitad de ano 2026'); 
    INSERT INTO TEMPORADA VALUES (9, 'Fin de ano 2026', DATE '2026-12-15', DATE '2027-01-15', 'Temporada alta de fin de ano 2026'); 
    DBMS_OUTPUT.PUT_LINE('Temporadas: 9'); 
    
    -- 6. ALOJAMIENTOS - 60 registros 
    FOR i IN 1..60 LOOP 
        INSERT INTO ALOJAMIENTO (id_alojamiento, id_municipio, id_tipo_alojamiento, nombre, direccion, telefono, correo, capacidad_total, estado) 
        VALUES (i, MOD(i - 1, 12) + 1, MOD(i - 1, 5) + 1, 'Alojamiento TurismoUQ ' || i, 'Carrera ' || MOD(i,20) || ' # ' || MOD(i,80) || '-' || MOD(i,50), '6' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100000000,999999999)),9,'0'), 'alojamiento' || i || '@turismouq.com', TRUNC(DBMS_RANDOM.VALUE(10,80)), 'ACTIVO'); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Alojamientos: 60'); 
    
    -- 7. HABITACIONES - 400 registros 
    FOR i IN 1..400 LOOP 
        v_id_habitacion := i; 
        INSERT INTO HABITACION (id_habitacion, id_alojamiento, numero, tipo_habitacion, capacidad, estado, descripcion) 
        VALUES (v_id_habitacion, MOD(i - 1, 60) + 1, 'H-' || LPAD(i,4,'0'), 
                CASE MOD(i,4) WHEN 0 THEN 'Individual' WHEN 1 THEN 'Doble' WHEN 2 THEN 'Familiar' ELSE 'Suite' END, 
                CASE MOD(i,4) WHEN 0 THEN 1 WHEN 1 THEN 2 WHEN 2 THEN 4 ELSE 3 END, 
                'DISPONIBLE', 'Habitacion turistica TurismoUQ ' || i); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Habitaciones: 400'); 
    
    -- 8. SERVICIOS - 120 registros 
    FOR i IN 1..120 LOOP 
        INSERT INTO SERVICIO (id_servicio, id_alojamiento, nombre, descripcion, precio, estado) 
        VALUES (i, MOD(i - 1, 60) + 1, 
                CASE MOD(i,6) WHEN 0 THEN 'Desayuno' WHEN 1 THEN 'Almuerzo' WHEN 2 THEN 'Cena' WHEN 3 THEN 'Transporte' WHEN 4 THEN 'Tour cafetero' ELSE 'Piscina' END || ' ' || i, 
                'Servicio turistico complementario', ROUND(DBMS_RANDOM.VALUE(15000,180000),2), 'ACTIVO'); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Servicios: 120'); 
    
    -- 9. TARIFAS - 400 habitaciones x 9 temporadas = 3600 tarifas 
    FOR habitacion IN 1..400 LOOP 
        FOR temporada IN 1..9 LOOP 
            INSERT INTO TARIFA (id_tarifa, id_habitacion, id_temporada, precio_noche) 
            VALUES (((habitacion - 1) * 9) + temporada, habitacion, temporada, ROUND(DBMS_RANDOM.VALUE(80000,450000),2)); 
        END LOOP; 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Tarifas: 3600'); 
    
    -- 10. RESERVAS - 25000 registros distribuidas entre 2024 y 2026 
    FOR i IN 1..25000 LOOP 
        v_fecha_checkin := DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,1095)); 
        v_fecha_checkout := v_fecha_checkin + TRUNC(DBMS_RANDOM.VALUE(1,6)); 
        v_fecha_reserva := v_fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(1,31)); 
        INSERT INTO RESERVA (id_reserva, id_usuario_sistema, id_cliente, fecha_reserva, fecha_checkin, fecha_checkout, estado) 
        VALUES (i, MOD(i - 1,20) + 1, MOD(i - 1,3000) + 1 + 1000000000, v_fecha_reserva, v_fecha_checkin, v_fecha_checkout, 
                CASE MOD(i,5) WHEN 0 THEN 'CANCELADA' WHEN 1 THEN 'CONFIRMADA' WHEN 2 THEN 'CONFIRMADA' WHEN 3 THEN 'FINALIZADA' ELSE 'PENDIENTE' END); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Reservas: 25000'); 
    
    -- 11. RESERVA_HABITACION - 25000 registros 
    FOR i IN 1..25000 LOOP 
        v_id_habitacion := MOD(i - 1,400) + 1; 
        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes, valor_habitacion) 
        VALUES (i, v_id_habitacion, TRUNC(DBMS_RANDOM.VALUE(1,5)), ROUND(DBMS_RANDOM.VALUE(80000,450000),2)); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Reserva_Habitacion: 25000'); 
    
    -- 12. RESERVA_SERVICIO - 40000 lineas 
    FOR i IN 1..40000 LOOP 
        IF i <= 25000 THEN 
            v_id_reserva := i; 
            v_id_servicio := MOD((i * 7) + 13, 120) + 1; 
        ELSE 
            v_id_reserva := i - 25000; 
            v_id_servicio := MOD((v_id_reserva * 7) + 47, 120) + 1; 
        END IF; 
        v_cantidad := TRUNC(DBMS_RANDOM.VALUE(1,4)); 
        v_precio := ROUND(15000 + MOD(v_id_servicio * 137, 165000),2); 
        INSERT INTO RESERVA_SERVICIO (id_reserva, id_servicio, cantidad, precio_unitario, subtotal) 
        VALUES (v_id_reserva, v_id_servicio, v_cantidad, v_precio, ROUND(v_cantidad * v_precio,2)); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Reserva_Servicio: 40000'); 
    
    -- 13. PAGOS - 25000 registros 
    FOR i IN 1..25000 LOOP 
        INSERT INTO PAGO (id_pago, id_reserva, fecha_pago, valor, metodo_pago, estado) 
        VALUES (i, i, DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,1095)), ROUND(DBMS_RANDOM.VALUE(100000,1500000),2), 
                CASE MOD(i,4) WHEN 0 THEN 'TARJETA' WHEN 1 THEN 'TRANSFERENCIA' WHEN 2 THEN 'PSE' ELSE 'EFECTIVO' END, 
                CASE MOD(i,5) WHEN 0 THEN 'PENDIENTE' ELSE 'PAGADO' END); 
    END LOOP; 
    DBMS_OUTPUT.PUT_LINE('Pagos: 25000'); 
    
    -- 14. RESENAS - 8000 registros 
    FOR i IN 1..8000 LOOP 
        INSERT INTO RESENA (id_resena, cedula_cliente, id_alojamiento, calificacion, comentario, fecha_resena) 
        VALUES (i, MOD(i - 1,3000) + 1 + 1000000000, MOD(i - 1,60) + 1, TRUNC(DBMS_RANDOM.VALUE(1,6)), 
                CASE MOD(i,5) WHEN 0 THEN 'Excelente experiencia' WHEN 1 THEN 'Muy buen alojamiento' WHEN 2 THEN 'Buena atencion' WHEN 3 THEN 'Lugar agradable' ELSE 'Experiencia turistica satisfactoria' END, 
                DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,1095))); 
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