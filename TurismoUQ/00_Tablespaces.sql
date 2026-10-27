/* ============================================================
   TURISMOUQ - 00_Tablespaces.sql
   Ejecutar PRIMERO, conectado como SYSTEM al PDB de XE:
       sqlplus system@localhost:1521/XEPDB1
   (si estas en el CDB, descomenta la siguiente linea)
   ============================================================ */
-- ALTER SESSION SET CONTAINER = XEPDB1;
SET SERVEROUTPUT ON;

/* ------------------------------------------------------------
   JUSTIFICACION DEL TABLESPACE PROPIO PARA EL HISTORICO DE RESERVAS
   1. Volumen y crecimiento: RESERVA, RESERVA_HABITACION, RESERVA_SERVICIO y PAGO
      son las tablas que mas crecen (decenas de miles de filas por año y nunca
      se borran). El catalogo (municipios, alojamientos, habitaciones, tarifas)
      es pequeño y casi estatico. Separarlos evita que el historico invada el
      espacio del catalogo.
   2. Administracion independiente: el datafile del historico puede crecer,
      moverse a otro disco, respaldarse o ponerse en modo READ ONLY (por
      ejemplo para años cerrados) sin afectar el catalogo ni el resto del sistema.
   3. Backup y recuperacion: se respalda con distinta frecuencia (el catalogo
      cambia poco; el historico se respalda por incrementales).
   4. Rendimiento: al estar en otro datafile, el I/O del historico (consultas
      de analisis) no compite con el del catalogo, y se puede ubicar en
      almacenamiento mas barato.
   ------------------------------------------------------------ */

-- Cada tablespace necesita un datafile con ruta. En muchas instalaciones de XE
-- no hay carpeta automatica configurada (error ORA-02236 si se omite la ruta),
-- asi que el script toma la carpeta donde ya esta el datafile del tablespace
-- SYSTEM del PDB y crea ahi los dos datafiles nuevos. Funciona en Windows y Linux.
--
-- Sentencias que ejecuta el bloque (con v_dir = carpeta de datos del PDB):
--   CREATE TABLESPACE ts_turismo_datos
--       DATAFILE '<v_dir>ts_turismo_datos01.dbf' SIZE 100M AUTOEXTEND ON NEXT 20M MAXSIZE 1G
--       EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO;
--   CREATE TABLESPACE ts_hist_reservas
--       DATAFILE '<v_dir>ts_hist_reservas01.dbf' SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G
--       EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO;
--
-- EXTENT MANAGEMENT LOCAL AUTOALLOCATE: Oracle decide el tamaño de los extents.
-- SEGMENT SPACE MANAGEMENT AUTO: gestion automatica del espacio dentro de los segmentos.
DECLARE
    v_dir VARCHAR2(500);
BEGIN
    SELECT SUBSTR(file_name, 1, GREATEST(INSTR(file_name, '\', -1), INSTR(file_name, '/', -1)))
      INTO v_dir
      FROM dba_data_files
     WHERE tablespace_name = 'SYSTEM'
       AND ROWNUM = 1;

    EXECUTE IMMEDIATE
        'CREATE TABLESPACE ts_turismo_datos DATAFILE ''' || v_dir || 'ts_turismo_datos01.dbf'' ' ||
        'SIZE 100M AUTOEXTEND ON NEXT 20M MAXSIZE 1G ' ||
        'EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO';

    EXECUTE IMMEDIATE
        'CREATE TABLESPACE ts_hist_reservas DATAFILE ''' || v_dir || 'ts_hist_reservas01.dbf'' ' ||
        'SIZE 200M AUTOEXTEND ON NEXT 50M MAXSIZE 2G ' ||
        'EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO';

    DBMS_OUTPUT.PUT_LINE('Tablespaces creados en: ' || v_dir);
END;
/

-- Esquema dueño del proyecto (cambia la clave)
CREATE USER turismouq IDENTIFIED BY "TurismoUQ_2026"
    DEFAULT TABLESPACE ts_turismo_datos
    TEMPORARY TABLESPACE temp
    QUOTA UNLIMITED ON ts_turismo_datos
    QUOTA UNLIMITED ON ts_hist_reservas;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE MATERIALIZED VIEW TO turismouq;

-- Verificacion con el diccionario de datos
SELECT tablespace_name, status, contents, extent_management, segment_space_management
  FROM dba_tablespaces
 WHERE tablespace_name IN ('TS_TURISMO_DATOS', 'TS_HIST_RESERVAS');

SELECT tablespace_name, file_name, ROUND(bytes / 1024 / 1024) AS mb, autoextensible
  FROM dba_data_files
 WHERE tablespace_name IN ('TS_TURISMO_DATOS', 'TS_HIST_RESERVAS');

-- Espacio libre de cada tablespace (DBA_FREE_SPACE)
SELECT tablespace_name, ROUND(SUM(bytes) / 1024 / 1024) AS mb_libres
  FROM dba_free_space
 WHERE tablespace_name IN ('TS_TURISMO_DATOS', 'TS_HIST_RESERVAS')
 GROUP BY tablespace_name;

-- Cuando ya exista el esquema cargado (como SYSTEM), ver que segmentos estan donde:
--   SELECT segment_name, segment_type, tablespace_name
--     FROM dba_segments WHERE owner = 'TURISMOUQ' ORDER BY tablespace_name, segment_name;

-- A partir de aqui, conectate como TURISMOUQ y ejecuta 01, 02, 03, 04 y 05 en orden:
--   CONNECT turismouq/"TurismoUQ_2026"@localhost:1521/XEPDB1