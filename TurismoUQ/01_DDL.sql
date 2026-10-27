/* ============================================================
   PROYECTO: TURISMO UQ
   Plataforma de reservas turisticas del Quindio

   Cambios respecto a la version anterior:
   - Correcion en columnas Null
   - TEMPORADA es general segun recomendacion profesora (ALTA, MEDIA, BAJA); los rangos de fechas viven en
     PERIODO_TEMPORADA y cubren todo el calendario (sin huecos).
   - RESERVA y sus tablas dependientes van al tablespace del historico.
   ============================================================ */

CREATE TABLE MUNICIPIO (
    id_municipio NUMBER        NOT NULL,
    nombre       VARCHAR2(100) NOT NULL,
    descripcion  VARCHAR2(500) NOT NULL,
    CONSTRAINT pk_municipio PRIMARY KEY (id_municipio),
    CONSTRAINT uk_municipio_nombre UNIQUE (nombre)
);

CREATE TABLE TIPO_ALOJAMIENTO (
    id_tipo_alojamiento NUMBER        NOT NULL,
    nombre              VARCHAR2(100) NOT NULL,
    descripcion         VARCHAR2(500) NOT NULL,
    CONSTRAINT pk_tipo_alojamiento PRIMARY KEY (id_tipo_alojamiento),
    CONSTRAINT uk_tipo_alojamiento_nombre UNIQUE (nombre)
);

CREATE TABLE CLIENTE (
    cedula    NUMBER        NOT NULL,
    nombres   VARCHAR2(60)  NOT NULL,
    apellidos VARCHAR2(100) NOT NULL,
    telefono  VARCHAR2(30)  NOT NULL,
    email     VARCHAR2(150) NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (cedula),
    CONSTRAINT uk_cliente_email UNIQUE (email)
);

CREATE TABLE USUARIO_SISTEMA (
    id_usuario      NUMBER        NOT NULL,
    nombre_usuario  VARCHAR2(60)  NOT NULL,
    nombre_completo VARCHAR2(150) NOT NULL,
    rol             VARCHAR2(50)  NOT NULL,
    email           VARCHAR2(150) NOT NULL,
    CONSTRAINT pk_usuario_sistema PRIMARY KEY (id_usuario),
    CONSTRAINT uk_usuario_sistema_nombre UNIQUE (nombre_usuario),
    CONSTRAINT ck_usuario_sistema_rol CHECK (rol IN ('ADMINISTRADOR', 'OPERADOR', 'ASESOR'))
);

CREATE TABLE TEMPORADA (
    id_temporada NUMBER        NOT NULL,
    nombre       VARCHAR2(20)  NOT NULL,
    descripcion  VARCHAR2(500) NOT NULL,
    CONSTRAINT pk_temporada PRIMARY KEY (id_temporada),
    CONSTRAINT uk_temporada_nombre UNIQUE (nombre),
    CONSTRAINT ck_temporada_nombre CHECK (nombre IN ('ALTA', 'MEDIA', 'BAJA'))
);

-- Fecha durante la cual se desarrollara la temporada
CREATE TABLE PERIODO_TEMPORADA (
    id_periodo   NUMBER NOT NULL,
    id_temporada NUMBER NOT NULL,
    fecha_inicio DATE   NOT NULL,
    fecha_fin    DATE   NOT NULL,
    CONSTRAINT pk_periodo_temporada PRIMARY KEY (id_periodo),
    CONSTRAINT fk_periodo_temporada FOREIGN KEY (id_temporada) REFERENCES TEMPORADA(id_temporada),
    CONSTRAINT ck_periodo_fechas CHECK (fecha_fin >= fecha_inicio)
);

CREATE TABLE ALOJAMIENTO (
    id_alojamiento      NUMBER        NOT NULL,
    id_municipio        NUMBER        NOT NULL,
    id_tipo_alojamiento NUMBER        NOT NULL,
    nombre              VARCHAR2(150) NOT NULL,
    direccion           VARCHAR2(250) NOT NULL,
    telefono            VARCHAR2(30)  NOT NULL,
    correo              VARCHAR2(150) NOT NULL,
    capacidad_total     NUMBER        NOT NULL,
    estado              VARCHAR2(30)  NOT NULL,
    CONSTRAINT pk_alojamiento PRIMARY KEY (id_alojamiento),
    CONSTRAINT fk_alojamiento_municipio FOREIGN KEY (id_municipio) REFERENCES MUNICIPIO(id_municipio),
    CONSTRAINT fk_alojamiento_tipo FOREIGN KEY (id_tipo_alojamiento) REFERENCES TIPO_ALOJAMIENTO(id_tipo_alojamiento),
    CONSTRAINT uk_alojamiento_correo UNIQUE (correo),
    CONSTRAINT ck_alojamiento_capacidad CHECK (capacidad_total > 0),
    CONSTRAINT ck_alojamiento_estado CHECK (estado IN ('ACTIVO', 'INACTIVO'))
);

CREATE TABLE HABITACION (
    id_habitacion   NUMBER        NOT NULL,
    id_alojamiento  NUMBER        NOT NULL,
    numero          VARCHAR2(20)  NOT NULL,
    tipo_habitacion VARCHAR2(60)  NOT NULL,
    capacidad       NUMBER        NOT NULL,
    estado          VARCHAR2(30)  NOT NULL,
    descripcion     VARCHAR2(500) NOT NULL,
    CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion),
    CONSTRAINT fk_habitacion_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento),
    CONSTRAINT uk_habitacion_numero UNIQUE (id_alojamiento, numero),
    CONSTRAINT ck_habitacion_capacidad CHECK (capacidad > 0),
    CONSTRAINT ck_habitacion_estado CHECK (estado IN ('DISPONIBLE', 'MANTENIMIENTO', 'INACTIVA'))
);

CREATE TABLE SERVICIO (
    id_servicio    NUMBER        NOT NULL,
    id_alojamiento NUMBER        NOT NULL,
    nombre         VARCHAR2(100) NOT NULL,
    descripcion    VARCHAR2(500) NOT NULL,
    precio         NUMBER(12,2)  NOT NULL,
    estado         VARCHAR2(30)  NOT NULL,
    CONSTRAINT pk_servicio PRIMARY KEY (id_servicio),
    CONSTRAINT fk_servicio_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento),
    CONSTRAINT ck_servicio_precio CHECK (precio >= 0),
    CONSTRAINT ck_servicio_estado CHECK (estado IN ('ACTIVO', 'INACTIVO'))
);

CREATE TABLE TARIFA (
    id_tarifa     NUMBER       NOT NULL,
    id_habitacion NUMBER       NOT NULL,
    id_temporada  NUMBER       NOT NULL,
    precio_noche  NUMBER(12,2) NOT NULL,
    CONSTRAINT pk_tarifa PRIMARY KEY (id_tarifa),
    CONSTRAINT fk_tarifa_habitacion FOREIGN KEY (id_habitacion) REFERENCES HABITACION(id_habitacion),
    CONSTRAINT fk_tarifa_temporada FOREIGN KEY (id_temporada) REFERENCES TEMPORADA(id_temporada),
    CONSTRAINT uk_tarifa_habitacion_temporada UNIQUE (id_habitacion, id_temporada),
    CONSTRAINT ck_tarifa_precio CHECK (precio_noche >= 0)
);

/* ------------------------------------------------------------
   Tablas del HISTORICO DE RESERVAS -> tablespace ts_hist_reservas
   (tabla y el indice de su PK)
   ------------------------------------------------------------ */

CREATE TABLE RESERVA (
    id_reserva         NUMBER       NOT NULL,
    id_usuario_sistema NUMBER       NOT NULL,
    id_cliente         NUMBER       NOT NULL,
    fecha_reserva      DATE         NOT NULL,
    fecha_checkin      DATE         NOT NULL,
    fecha_checkout     DATE         NOT NULL,
    estado             VARCHAR2(30) NOT NULL,
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva) USING INDEX TABLESPACE ts_hist_reservas,
    CONSTRAINT fk_reserva_usuario FOREIGN KEY (id_usuario_sistema) REFERENCES USUARIO_SISTEMA(id_usuario),
    CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente) REFERENCES CLIENTE(cedula),
    CONSTRAINT ck_reserva_fechas CHECK (fecha_checkout > fecha_checkin),
    CONSTRAINT ck_reserva_anticipacion CHECK (fecha_reserva <= fecha_checkin),
    CONSTRAINT ck_reserva_estado CHECK (estado IN ('PENDIENTE', 'CONFIRMADA', 'FINALIZADA', 'CANCELADA'))
) TABLESPACE ts_hist_reservas;

-- una reserva puede tomar varias habitaciones
CREATE TABLE RESERVA_HABITACION (
    id_reserva         NUMBER       NOT NULL,
    id_habitacion      NUMBER       NOT NULL,
    cantidad_huespedes NUMBER       NOT NULL,
    valor_habitacion   NUMBER(12,2) NOT NULL,
    CONSTRAINT pk_reserva_habitacion PRIMARY KEY (id_reserva, id_habitacion) USING INDEX TABLESPACE ts_hist_reservas,
    CONSTRAINT fk_reserva_habitacion_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva),
    CONSTRAINT fk_reserva_habitacion_habitacion FOREIGN KEY (id_habitacion) REFERENCES HABITACION(id_habitacion),
    CONSTRAINT ck_reserva_hab_huespedes CHECK (cantidad_huespedes > 0),
    CONSTRAINT ck_reserva_hab_valor CHECK (valor_habitacion >= 0)
) TABLESPACE ts_hist_reservas;

CREATE TABLE RESERVA_SERVICIO (
    id_reserva      NUMBER       NOT NULL,
    id_servicio     NUMBER       NOT NULL,
    cantidad        NUMBER       NOT NULL,
    precio_unitario NUMBER(12,2) NOT NULL,
    subtotal        NUMBER(12,2) NOT NULL,
    CONSTRAINT pk_reserva_servicio PRIMARY KEY (id_reserva, id_servicio) USING INDEX TABLESPACE ts_hist_reservas,
    CONSTRAINT fk_reserva_servicio_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva),
    CONSTRAINT fk_reserva_servicio_servicio FOREIGN KEY (id_servicio) REFERENCES SERVICIO(id_servicio),
    CONSTRAINT ck_reserva_serv_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_reserva_serv_precio CHECK (precio_unitario >= 0),
    CONSTRAINT ck_reserva_serv_subtotal CHECK (subtotal >= 0)
) TABLESPACE ts_hist_reservas;

CREATE TABLE PAGO (
    id_pago     NUMBER       NOT NULL,
    id_reserva  NUMBER       NOT NULL,
    fecha_pago  DATE         NOT NULL,
    valor       NUMBER(12,2) NOT NULL,
    metodo_pago VARCHAR2(40) NOT NULL,
    estado      VARCHAR2(30) NOT NULL,
    CONSTRAINT pk_pago PRIMARY KEY (id_pago) USING INDEX TABLESPACE ts_hist_reservas,
    CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA(id_reserva),
    CONSTRAINT ck_pago_valor CHECK (valor >= 0),
    CONSTRAINT ck_pago_metodo CHECK (metodo_pago IN ('TARJETA', 'TRANSFERENCIA', 'PSE', 'EFECTIVO')),
    CONSTRAINT ck_pago_estado CHECK (estado IN ('PENDIENTE', 'PAGADO', 'REEMBOLSADO'))
) TABLESPACE ts_hist_reservas;

CREATE TABLE RESENA (
    id_resena      NUMBER         NOT NULL,
    cedula_cliente NUMBER         NOT NULL,
    id_alojamiento NUMBER         NOT NULL,
    calificacion   NUMBER(2)      NOT NULL,
    comentario     VARCHAR2(1000) NOT NULL,
    fecha_resena   DATE           NOT NULL,
    CONSTRAINT pk_resena PRIMARY KEY (id_resena),
    CONSTRAINT fk_resena_cliente FOREIGN KEY (cedula_cliente) REFERENCES CLIENTE(cedula),
    CONSTRAINT fk_resena_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento),
    CONSTRAINT ck_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5)
);

SELECT table_name, tablespace_name FROM user_tables ORDER BY tablespace_name, table_name;
