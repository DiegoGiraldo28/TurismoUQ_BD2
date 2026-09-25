/* ============================================================ 
   PROYECTO: TURISMO UQ 
   Plataforma de reservas turísticas del Quindío 
   ============================================================ */ 

-- 1. MUNICIPIO 
CREATE TABLE MUNICIPIO ( 
    id_municipio NUMBER NOT NULL, 
    nombre VARCHAR2(100), 
    descripcion VARCHAR2(500), 
    CONSTRAINT pk_municipio PRIMARY KEY (id_municipio) 
); 

-- 2. TIPO_ALOJAMIENTO 
CREATE TABLE TIPO_ALOJAMIENTO ( 
    id_tipo_alojamiento NUMBER NOT NULL, 
    nombre VARCHAR2(100), 
    descripcion VARCHAR2(500), 
    CONSTRAINT pk_tipo_alojamiento PRIMARY KEY (id_tipo_alojamiento) 
); 

-- 3. CLIENTE 
CREATE TABLE CLIENTE ( 
    cedula NUMBER NOT NULL, 
    nombres VARCHAR2(30), 
    apellidos VARCHAR2(100), 
    telefono VARCHAR2(30), 
    email VARCHAR2(150), 
    CONSTRAINT pk_cliente PRIMARY KEY (cedula) 
); 

-- 4. USUARIO_SISTEMA 
CREATE TABLE USUARIO_SISTEMA ( 
    id_usuario NUMBER NOT NULL, 
    nombre_usuario VARCHAR2(60) NOT NULL, 
    nombre_completo VARCHAR2(150), 
    rol VARCHAR2(50), 
    email VARCHAR2(150), 
    CONSTRAINT pk_usuario_sistema PRIMARY KEY (id_usuario), 
    CONSTRAINT uk_usuario_sistema_nombre UNIQUE (nombre_usuario) 
); 

-- 5. TEMPORADA 
CREATE TABLE TEMPORADA ( 
    id_temporada NUMBER NOT NULL, 
    nombre VARCHAR2(100), 
    fecha_inicio DATE, 
    fecha_fin DATE, 
    descripcion VARCHAR2(500), 
    CONSTRAINT pk_temporada PRIMARY KEY (id_temporada), 
    CONSTRAINT ck_temporada_fechas CHECK (fecha_fin >= fecha_inicio) 
); 

-- 6. ALOJAMIENTO 
CREATE TABLE ALOJAMIENTO ( 
    id_alojamiento NUMBER NOT NULL, 
    id_municipio NUMBER NOT NULL, 
    id_tipo_alojamiento NUMBER NOT NULL, 
    nombre VARCHAR2(150), 
    direccion VARCHAR2(250), 
    telefono VARCHAR2(30), 
    correo VARCHAR2(150), 
    capacidad_total NUMBER, 
    estado VARCHAR2(30), 
    CONSTRAINT pk_alojamiento PRIMARY KEY (id_alojamiento), 
    CONSTRAINT fk_alojamiento_municipio FOREIGN KEY (id_municipio) REFERENCES MUNICIPIO(id_municipio), 
    CONSTRAINT fk_alojamiento_tipo FOREIGN KEY (id_tipo_alojamiento) REFERENCES TIPO_ALOJAMIENTO(id_tipo_alojamiento), 
    CONSTRAINT ck_alojamiento_capacidad CHECK (capacidad_total > 0) 
); 

-- 7. HABITACION 
CREATE TABLE HABITACION ( 
    id_habitacion NUMBER NOT NULL, 
    id_alojamiento NUMBER NOT NULL, 
    numero VARCHAR2(20), 
    tipo_habitacion VARCHAR2(60), 
    capacidad NUMBER, 
    estado VARCHAR2(30), 
    descripcion VARCHAR2(500), 
    CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion), 
    CONSTRAINT fk_habitacion_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento), 
    CONSTRAINT ck_habitacion_capacidad CHECK (capacidad > 0) 
); 

-- 8. SERVICIO 
CREATE TABLE SERVICIO ( 
    id_servicio NUMBER NOT NULL, 
    id_alojamiento NUMBER NOT NULL, 
    nombre VARCHAR2(100), 
    descripcion VARCHAR2(500), 
    precio NUMBER(12,2), 
    estado VARCHAR2(30), 
    CONSTRAINT pk_servicio PRIMARY KEY (id_servicio), 
    CONSTRAINT fk_servicio_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento), 
    CONSTRAINT ck_servicio_precio CHECK (precio >= 0) 
); 

-- 9. TARIFA 
CREATE TABLE TARIFA ( 
    id_tarifa NUMBER NOT NULL, 
    id_habitacion NUMBER NOT NULL, 
    id_temporada NUMBER NOT NULL, 
    precio_noche NUMBER(12,2), 
    CONSTRAINT pk_tarifa PRIMARY KEY (id_tarifa), 
    CONSTRAINT fk_tarifa_habitacion FOREIGN KEY (id_habitacion) REFERENCES HABITACION(id_habitacion), 
    CONSTRAINT fk_tarifa_temporada FOREIGN KEY (id_temporada) REFERENCES TEMPORADA(id_temporada), 
    CONSTRAINT uk_tarifa_habitacion_temporada UNIQUE (id_habitacion, id_temporada), 
    CONSTRAINT ck_tarifa_precio CHECK (precio_noche >= 0) 
); 

-- 10. RESERVA 
CREATE TABLE RESERVA ( 
    id_reserva NUMBER NOT NULL, 
    id_usuario_sistema NUMBER NOT NULL, 
    id_cliente NUMBER NOT NULL, 
    fecha_reserva DATE, 
    fecha_checkin DATE, 
    fecha_checkout DATE, 
    estado VARCHAR2(30), 
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva), 
    CONSTRAINT fk_reserva_usuario FOREIGN KEY (id_usuario_sistema) REFERENCES USUARIO_SISTEMA(id_usuario), 
    CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente) REFERENCES CLIENTE(cedula), 
    CONSTRAINT ck_reserva_fechas CHECK (fecha_checkout >= fecha_checkin) 
); 

-- 11. RESERVA_HABITACION 
CREATE TABLE RESERVA_HABITACION ( 
    id_reserva NUMBER NOT NULL, 
    id_habitacion NUMBER NOT NULL, 
    cantidad_huespedes NUMBER, 
    valor_habitacion NUMBER(12,2), 
    CONSTRAINT pk_reserva_habitacion PRIMARY KEY (id_reserva, id_habitacion), 
    CONSTRAINT fk_reserva_habitacion_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva), 
    CONSTRAINT fk_reserva_habitacion_habitacion FOREIGN KEY (id_habitacion) REFERENCES HABITACION(id_habitacion), 
    CONSTRAINT ck_reserva_hab_huespedes CHECK (cantidad_huespedes > 0), 
    CONSTRAINT ck_reserva_hab_valor CHECK (valor_habitacion >= 0) 
); 

-- 12. RESERVA_SERVICIO 
CREATE TABLE RESERVA_SERVICIO ( 
    id_reserva NUMBER NOT NULL, 
    id_servicio NUMBER NOT NULL, 
    cantidad NUMBER, 
    precio_unitario NUMBER(12,2), 
    subtotal NUMBER(12,2), 
    CONSTRAINT pk_reserva_servicio PRIMARY KEY (id_reserva, id_servicio), 
    CONSTRAINT fk_reserva_servicio_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva), 
    CONSTRAINT fk_reserva_servicio_servicio FOREIGN KEY (id_servicio) REFERENCES SERVICIO(id_servicio), 
    CONSTRAINT ck_reserva_serv_cantidad CHECK (cantidad > 0), 
    CONSTRAINT ck_reserva_serv_precio CHECK (precio_unitario >= 0), 
    CONSTRAINT ck_reserva_serv_subtotal CHECK (subtotal >= 0) 
); 

-- 13. PAGO 
CREATE TABLE PAGO ( 
    id_pago NUMBER NOT NULL, 
    id_reserva NUMBER NOT NULL, 
    fecha_pago DATE, 
    valor NUMBER(12,2), 
    metodo_pago VARCHAR2(40), 
    estado VARCHAR2(30), 
    CONSTRAINT pk_pago PRIMARY KEY (id_pago), 
    CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva), 
    CONSTRAINT ck_pago_valor CHECK (valor >= 0) 
); 

-- 14. RESENA 
CREATE TABLE RESENA ( 
    id_resena NUMBER NOT NULL, 
    cedula_cliente NUMBER NOT NULL, 
    id_alojamiento NUMBER NOT NULL, 
    calificacion NUMBER(2), 
    comentario VARCHAR2(1000), 
    fecha_resena DATE, 
    CONSTRAINT pk_resena PRIMARY KEY (id_resena), 
    CONSTRAINT fk_resena_cliente FOREIGN KEY (cedula_cliente) REFERENCES CLIENTE(cedula), 
    CONSTRAINT fk_resena_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento), 
    CONSTRAINT ck_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5) 
);