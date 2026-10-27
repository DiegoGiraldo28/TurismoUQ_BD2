"""Acceso de lectura de diagnóstico al esquema Oracle existente."""
import logging
import re
from datetime import date, datetime, time
from datetime import timedelta
from decimal import Decimal
import math

from django.db import DatabaseError, connections, transaction

try:
    import oracledb
except ImportError:  # Permite cargar el proyecto antes de instalar dependencias.
    oracledb = None

logger = logging.getLogger(__name__)


# Identificadores fijos basados en 01_DDL.sql y 04_CapaPLSQL.sql. No provienen
# de la solicitud web y por ello pueden usarse como nombres de tabla Oracle.
TABLAS_DIAGNOSTICO = (
    "MUNICIPIO", "TIPO_ALOJAMIENTO", "CLIENTE", "USUARIO_SISTEMA", "TEMPORADA",
    "PERIODO_TEMPORADA", "ALOJAMIENTO", "HABITACION", "SERVICIO", "TARIFA",
    "RESERVA", "RESERVA_HABITACION", "RESERVA_SERVICIO", "PAGO", "RESENA",
    "AUDITORIA_TARIFA", "LIQUIDACION_MENSUAL",
)

MENSAJES_ORACLE = {
    -20001: "La habitación no está disponible para esas fechas.",
    -20002: "La fecha de salida debe ser posterior a la fecha de entrada.",
    -20003: "La cantidad de huéspedes supera la capacidad de la habitación.",
    -20004: "La habitación seleccionada no existe.",
    -20005: "La habitación tiene otra reserva que se cruza con esas fechas.",
    -20006: "La reserva seleccionada no existe.",
    -20007: "No hay tarifa configurada para todas las noches de la estadía.",
    -20010: "El mes seleccionado no es válido.",
    -2291: "No se encontró el cliente o el usuario del sistema seleccionado.",
    1: "Esta habitación ya está agregada a la reserva.",
}


def _es_error_oracle(exc):
    """Reconoce errores del driver aunque Django los envuelva."""
    current = exc
    while current is not None:
        if oracledb is not None and isinstance(current, oracledb.DatabaseError):
            return True
        current = current.__cause__ or current.__context__
    return False


def codigo_error_oracle(exc):
    """Retorna el código Oracle del error, incluso si Django lo envolvió."""
    current = exc
    while current is not None:
        if oracledb is not None and isinstance(current, oracledb.DatabaseError):
            args = current.args
            if args:
                codigo = getattr(args[0], "code", None)
                if codigo:
                    codigo = int(codigo)
                    return -codigo if 20000 <= codigo <= 20999 else codigo
        coincidencia = re.search(r"ORA-(\d{5})", str(current))
        if coincidencia:
            codigo = int(coincidencia.group(1))
            return -codigo if 20000 <= codigo <= 20999 else codigo
        current = current.__cause__ or current.__context__
    return None


def mensaje_error_oracle(exc):
    codigo = codigo_error_oracle(exc)
    return MENSAJES_ORACLE.get(codigo, "No fue posible completar la operación en la base de datos de TurismoUQ.")


def detalle_error_tecnico(exc):
    """Devuelve el código Oracle/driver y su texto para el modo DEBUG."""
    current = exc
    while current is not None:
        texto = str(current)
        coincidencia = re.search(r"(ORA-\d{5}|DPY-\d{4})", texto)
        if coincidencia:
            return f"{coincidencia.group(1)}: {texto}"
        current = current.__cause__ or current.__context__
    return f"{type(exc).__name__}: {exc}"


def conteos_tablas():
    conteos = []
    with connections["turismo"].cursor() as cursor:
        for tabla in TABLAS_DIAGNOSTICO:
            # `tabla` pertenece a la lista constante de arriba, nunca a entrada del usuario.
            cursor.execute(f"SELECT COUNT(*) FROM TURISMOUQ.{tabla}")
            conteos.append({"tabla": tabla, "filas": cursor.fetchone()[0]})
    return conteos


def _consultar_detallado(sql, parametros=()):
    with connections["turismo"].cursor() as cursor:
        cursor.execute(sql, parametros)
        columnas = [columna[0].lower() for columna in cursor.description]
        filas = [dict(zip(columnas, fila)) for fila in cursor.fetchall()]
        return columnas, filas


def _consultar(sql, parametros=()):
    return _consultar_detallado(sql, parametros)[1]


def datos_tablero():
    resumen = _consultar("""
        SELECT
            (SELECT COUNT(*) FROM TURISMOUQ.ALOJAMIENTO) AS alojamientos,
            (SELECT COUNT(*) FROM TURISMOUQ.HABITACION) AS habitaciones,
            (SELECT COUNT(*) FROM TURISMOUQ.CLIENTE) AS clientes,
            (SELECT COUNT(*) FROM TURISMOUQ.RESERVA
              WHERE estado IN ('PENDIENTE', 'CONFIRMADA')) AS reservas_activas,
            NVL((SELECT SUM(rh.valor_habitacion)
                   FROM TURISMOUQ.RESERVA_HABITACION rh
                   JOIN TURISMOUQ.RESERVA r ON r.id_reserva = rh.id_reserva
                  WHERE r.fecha_checkin >= TRUNC(SYSDATE, 'MM')
                    AND r.fecha_checkin < ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1)
                    AND r.estado <> 'CANCELADA'), 0)
            + NVL((SELECT SUM(rs.subtotal)
                     FROM TURISMOUQ.RESERVA_SERVICIO rs
                     JOIN TURISMOUQ.RESERVA r ON r.id_reserva = rs.id_reserva
                    WHERE r.fecha_checkin >= TRUNC(SYSDATE, 'MM')
                      AND r.fecha_checkin < ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1)
                      AND r.estado <> 'CANCELADA'), 0) AS ingresos_mes
        FROM DUAL
    """)[0]
    ocupacion = _consultar("""
        SELECT anio, mes, reservas, ingresos
          FROM (SELECT anio, mes, SUM(reservas) AS reservas, SUM(ingresos) AS ingresos
                  FROM TURISMOUQ.MV_OCUPACION_MENSUAL
                 GROUP BY anio, mes
                 ORDER BY anio DESC, mes DESC
                 FETCH FIRST 12 ROWS ONLY)
         ORDER BY anio, mes
    """)
    return resumen, ocupacion


def opciones_alojamiento():
    municipios = _consultar("SELECT id_municipio, nombre FROM TURISMOUQ.MUNICIPIO ORDER BY nombre")
    tipos = _consultar("SELECT id_tipo_alojamiento, nombre FROM TURISMOUQ.TIPO_ALOJAMIENTO ORDER BY nombre")
    return municipios, tipos


def listar_alojamientos(municipio=None, tipo=None):
    sql = """
        SELECT a.id_alojamiento, a.nombre, a.direccion, a.capacidad_total,
               m.nombre AS municipio, ta.nombre AS tipo_alojamiento,
               COUNT(DISTINCT h.id_habitacion) AS num_habitaciones,
               ROUND(AVG(r.calificacion), 1) AS calificacion
          FROM TURISMOUQ.ALOJAMIENTO a
          JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
          JOIN TURISMOUQ.TIPO_ALOJAMIENTO ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
          LEFT JOIN TURISMOUQ.HABITACION h ON h.id_alojamiento = a.id_alojamiento
          LEFT JOIN TURISMOUQ.RESENA r ON r.id_alojamiento = a.id_alojamiento
         WHERE a.estado = 'ACTIVO'
    """
    parametros = []
    if municipio:
        sql += " AND a.id_municipio = %s"
        parametros.append(municipio)
    if tipo:
        sql += " AND a.id_tipo_alojamiento = %s"
        parametros.append(tipo)
    sql += """
         GROUP BY a.id_alojamiento, a.nombre, a.direccion, a.capacidad_total, m.nombre, ta.nombre
         ORDER BY m.nombre, a.nombre
    """
    return _consultar(sql, parametros)


def detalle_alojamiento(id_alojamiento):
    alojamientos = _consultar("""
        SELECT a.id_alojamiento, a.nombre, a.direccion, a.telefono, a.correo,
               a.capacidad_total, m.nombre AS municipio, m.descripcion AS descripcion_municipio,
               ta.nombre AS tipo_alojamiento,
               ROUND(AVG(r.calificacion), 1) AS calificacion,
               COUNT(r.id_resena) AS num_resenas
          FROM TURISMOUQ.ALOJAMIENTO a
          JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
          JOIN TURISMOUQ.TIPO_ALOJAMIENTO ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
          LEFT JOIN TURISMOUQ.RESENA r ON r.id_alojamiento = a.id_alojamiento
         WHERE a.id_alojamiento = %s AND a.estado = 'ACTIVO'
         GROUP BY a.id_alojamiento, a.nombre, a.direccion, a.telefono, a.correo,
                  a.capacidad_total, m.nombre, m.descripcion, ta.nombre
    """, [id_alojamiento])
    if not alojamientos:
        return None
    habitaciones = _consultar("""
        SELECT h.id_habitacion, h.numero, h.tipo_habitacion, h.capacidad,
               h.estado, h.descripcion,
               MAX(CASE WHEN t.nombre = 'ALTA' THEN tr.precio_noche END) AS tarifa_alta,
               MAX(CASE WHEN t.nombre = 'MEDIA' THEN tr.precio_noche END) AS tarifa_media,
               MAX(CASE WHEN t.nombre = 'BAJA' THEN tr.precio_noche END) AS tarifa_baja
          FROM TURISMOUQ.HABITACION h
          LEFT JOIN TURISMOUQ.TARIFA tr ON tr.id_habitacion = h.id_habitacion
          LEFT JOIN TURISMOUQ.TEMPORADA t ON t.id_temporada = tr.id_temporada
         WHERE h.id_alojamiento = %s
         GROUP BY h.id_habitacion, h.numero, h.tipo_habitacion, h.capacidad, h.estado, h.descripcion
         ORDER BY h.numero
    """, [id_alojamiento])
    servicios = _consultar("""
        SELECT nombre, descripcion, precio
          FROM TURISMOUQ.SERVICIO
         WHERE id_alojamiento = %s AND estado = 'ACTIVO'
         ORDER BY nombre
    """, [id_alojamiento])
    return {"alojamiento": alojamientos[0], "habitaciones": habitaciones, "servicios": servicios}


def opciones_usuarios_sistema():
    return _consultar("""
        SELECT id_usuario, nombre_completo, nombre_usuario, rol
          FROM TURISMOUQ.USUARIO_SISTEMA
         ORDER BY nombre_completo
    """)


def buscar_cliente_por_cedula(cedula):
    clientes = _consultar("""
        SELECT cedula, nombres, apellidos, telefono, email
          FROM TURISMOUQ.CLIENTE
         WHERE cedula = %s
    """, [cedula])
    return clientes[0] if clientes else None


def cotizar_habitacion(id_habitacion, fecha_entrada, fecha_salida):
    valor = _consultar(
        "SELECT TURISMOUQ.PKG_TURISMO.FN_VALOR_ESTADIA(%s, %s, %s) AS valor_total FROM DUAL",
        [id_habitacion, fecha_entrada, fecha_salida],
    )[0]["valor_total"]
    tramos = _consultar("""
        WITH tramos AS (
            SELECT t.nombre AS temporada, tr.precio_noche,
                   GREATEST(p.fecha_inicio, TRUNC(%s)) AS desde,
                   LEAST(p.fecha_fin + 1, TRUNC(%s)) AS hasta
              FROM TURISMOUQ.PERIODO_TEMPORADA p
              JOIN TURISMOUQ.TEMPORADA t ON t.id_temporada = p.id_temporada
              JOIN TURISMOUQ.TARIFA tr ON tr.id_temporada = p.id_temporada
             WHERE p.fecha_inicio < TRUNC(%s)
               AND p.fecha_fin >= TRUNC(%s)
               AND tr.id_habitacion = %s
        )
        SELECT temporada, precio_noche, hasta - desde AS noches,
               (hasta - desde) * precio_noche AS subtotal
          FROM tramos
         WHERE hasta > desde
         ORDER BY desde
    """, [fecha_entrada, fecha_salida, fecha_salida, fecha_entrada, id_habitacion])
    return valor, [{**tramo, "noches": int(tramo["noches"])} for tramo in tramos]


def habitaciones_disponibles(fecha_entrada, fecha_salida, huespedes, municipio=None, excluir_reserva=None):
    sql = """
        SELECT h.id_habitacion, h.id_alojamiento, h.numero, h.tipo_habitacion,
               h.capacidad, h.descripcion, a.nombre AS alojamiento,
               m.nombre AS municipio, ta.nombre AS tipo_alojamiento
          FROM TURISMOUQ.HABITACION h
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
          JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
          JOIN TURISMOUQ.TIPO_ALOJAMIENTO ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
         WHERE h.estado = 'DISPONIBLE'
           AND a.estado = 'ACTIVO'
           AND h.capacidad >= %s
           AND NOT EXISTS (
                SELECT 1
                  FROM TURISMOUQ.RESERVA_HABITACION rh
                  JOIN TURISMOUQ.RESERVA r ON r.id_reserva = rh.id_reserva
                 WHERE rh.id_habitacion = h.id_habitacion
                   AND r.estado <> 'CANCELADA'
                   AND r.fecha_checkin < %s
                   AND r.fecha_checkout > %s
    """
    parametros = [huespedes, fecha_salida, fecha_entrada]
    if excluir_reserva is not None:
        sql += " AND r.id_reserva <> %s"
        parametros.append(excluir_reserva)
    sql += ")"
    if excluir_reserva is not None:
        sql += " AND NOT EXISTS (SELECT 1 FROM TURISMOUQ.RESERVA_HABITACION propia WHERE propia.id_reserva = %s AND propia.id_habitacion = h.id_habitacion)"
        parametros.append(excluir_reserva)
    if municipio:
        sql += " AND a.id_municipio = %s"
        parametros.append(municipio)
    sql += " ORDER BY m.nombre, a.nombre, h.numero"

    habitaciones = _consultar(sql, parametros)
    for habitacion in habitaciones:
        valor, tramos = cotizar_habitacion(habitacion["id_habitacion"], fecha_entrada, fecha_salida)
        habitacion["valor_total"] = valor
        habitacion["desglose"] = tramos
    return habitaciones


def crear_reserva(id_usuario, cedula_cliente, id_habitacion, fecha_entrada, fecha_salida, huespedes):
    if oracledb is None:
        raise RuntimeError("El driver oracledb no está instalado.")
    try:
        with transaction.atomic(using="turismo"):
            with connections["turismo"].cursor() as cursor:
                # python-oracledb recibe date/datetime nativos; `var` declara
                # explícitamente el OUT NUMBER de p_id_reserva.
                fecha_in_oracle = _fecha_oracle(fecha_entrada)
                fecha_out_oracle = _fecha_oracle(fecha_salida)
                out_id = cursor.var(oracledb.DB_TYPE_NUMBER)
                cursor.callproc("PKG_TURISMO.SP_CREAR_RESERVA", [
                    id_usuario,
                    cedula_cliente,
                    id_habitacion,
                    fecha_in_oracle,
                    fecha_out_oracle,
                    huespedes,
                    out_id.var,
                ])
                valor_out = out_id.var.getvalue()
                if valor_out is None:
                    raise RuntimeError("El procedimiento no devolvió el número de reserva.")
                id_reserva = int(valor_out)
    except Exception:
        logger.exception("Falló PKG_TURISMO.SP_CREAR_RESERVA en Oracle")
        raise
    return id_reserva


def obtener_reserva(id_reserva):
    reservas = _consultar("""
        SELECT r.id_reserva, r.id_cliente AS cedula_cliente, c.nombres, c.apellidos,
               r.fecha_reserva, r.fecha_checkin, r.fecha_checkout, r.estado
          FROM TURISMOUQ.RESERVA r
          JOIN TURISMOUQ.CLIENTE c ON c.cedula = r.id_cliente
         WHERE r.id_reserva = %s
    """, [id_reserva])
    if not reservas:
        return None
    habitaciones = _consultar("""
        SELECT h.id_habitacion, h.numero, h.tipo_habitacion, rh.cantidad_huespedes,
               rh.valor_habitacion, a.nombre AS alojamiento
          FROM TURISMOUQ.RESERVA_HABITACION rh
          JOIN TURISMOUQ.HABITACION h ON h.id_habitacion = rh.id_habitacion
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
         WHERE rh.id_reserva = %s
         ORDER BY h.numero
    """, [id_reserva])
    return {"reserva": reservas[0], "habitaciones": habitaciones}


def contexto_agregar_habitacion(id_reserva, id_habitacion):
    reservas = _consultar("""
        SELECT id_reserva, fecha_checkin, fecha_checkout
          FROM TURISMOUQ.RESERVA
         WHERE id_reserva = %s
    """, [id_reserva])
    habitaciones = _consultar("""
        SELECT h.id_habitacion, h.numero, h.tipo_habitacion, h.capacidad,
               h.estado, a.nombre AS alojamiento, a.estado AS estado_alojamiento
          FROM TURISMOUQ.HABITACION h
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
         WHERE h.id_habitacion = %s
    """, [id_habitacion])
    if not reservas or not habitaciones:
        return None
    reserva, habitacion = reservas[0], habitaciones[0]
    cotizacion, desglose = cotizar_habitacion(id_habitacion, reserva["fecha_checkin"], reserva["fecha_checkout"])
    return {"reserva": reserva, "habitacion": habitacion, "cotizacion": cotizacion, "desglose": desglose}


def agregar_habitacion(id_reserva, id_habitacion, huespedes):
    try:
        with transaction.atomic(using="turismo"):
            with connections["turismo"].cursor() as cursor:
                cursor.callproc("PKG_TURISMO.SP_AGREGAR_HABITACION", [id_reserva, id_habitacion, huespedes])
    except Exception:
        logger.exception("Falló PKG_TURISMO.SP_AGREGAR_HABITACION en Oracle")
        raise


def _fecha_oracle(valor):
    if isinstance(valor, datetime):
        return valor
    if isinstance(valor, date):
        return datetime.combine(valor, time.min)
    raise TypeError("La fecha debe ser datetime.date o datetime.datetime.")


def es_error_de_conexion_oracle(exc):
    return isinstance(exc, DatabaseError) or _es_error_oracle(exc)


def _filtros_reserva(filtros):
    condiciones = []
    parametros = []
    if filtros.get("estado"):
        condiciones.append("r.estado = %s")
        parametros.append(filtros["estado"])
    if filtros.get("fecha_desde"):
        condiciones.append("r.fecha_checkin >= %s")
        parametros.append(filtros["fecha_desde"])
    if filtros.get("fecha_hasta"):
        condiciones.append("r.fecha_checkin < %s")
        parametros.append(filtros["fecha_hasta"] + timedelta(days=1))
    if filtros.get("cliente"):
        condiciones.append("r.id_cliente = %s")
        parametros.append(filtros["cliente"])
    return (" WHERE " + " AND ".join(condiciones) if condiciones else ""), parametros


def listar_reservas_pagina(filtros, numero_pagina, por_pagina=25):
    where, parametros = _filtros_reserva(filtros)
    conteo = _consultar("SELECT COUNT(*) AS total FROM TURISMOUQ.RESERVA r" + where, parametros)[0]["total"]
    paginas = max(1, math.ceil(conteo / por_pagina))
    numero_pagina = min(max(1, numero_pagina), paginas)
    offset = (numero_pagina - 1) * por_pagina
    reservas = _consultar("""
        SELECT r.id_reserva, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout,
               r.estado, r.id_cliente AS cedula_cliente,
               c.nombres || ' ' || c.apellidos AS cliente,
               (SELECT NVL(SUM(rh.valor_habitacion), 0)
                  FROM TURISMOUQ.RESERVA_HABITACION rh
                 WHERE rh.id_reserva = r.id_reserva) AS total_habitaciones,
               (SELECT NVL(SUM(rs.subtotal), 0)
                  FROM TURISMOUQ.RESERVA_SERVICIO rs
                 WHERE rs.id_reserva = r.id_reserva) AS total_servicios
          FROM TURISMOUQ.RESERVA r
          JOIN TURISMOUQ.CLIENTE c ON c.cedula = r.id_cliente
    """ + where + " ORDER BY r.fecha_reserva DESC, r.id_reserva DESC OFFSET %s ROWS FETCH NEXT %s ROWS ONLY",
        [*parametros, offset, por_pagina])
    for reserva in reservas:
        reserva["total"] = reserva["total_habitaciones"] + reserva["total_servicios"]
    return reservas, conteo, numero_pagina, paginas


def detalle_reserva(id_reserva):
    reservas = _consultar("""
        SELECT r.id_reserva, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout,
               r.estado, r.id_cliente AS cedula_cliente, c.nombres, c.apellidos,
               c.telefono, c.email, u.nombre_completo AS usuario_responsable
          FROM TURISMOUQ.RESERVA r
          JOIN TURISMOUQ.CLIENTE c ON c.cedula = r.id_cliente
          JOIN TURISMOUQ.USUARIO_SISTEMA u ON u.id_usuario = r.id_usuario_sistema
         WHERE r.id_reserva = %s
    """, [id_reserva])
    if not reservas:
        return None
    habitaciones = _consultar("""
        SELECT rh.id_habitacion, h.numero, h.tipo_habitacion, a.nombre AS alojamiento,
               rh.cantidad_huespedes, rh.valor_habitacion
          FROM TURISMOUQ.RESERVA_HABITACION rh
          JOIN TURISMOUQ.HABITACION h ON h.id_habitacion = rh.id_habitacion
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
         WHERE rh.id_reserva = %s
         ORDER BY a.nombre, h.numero
    """, [id_reserva])
    servicios = _consultar("""
        SELECT rs.id_servicio, s.nombre, a.nombre AS alojamiento, rs.cantidad,
               rs.precio_unitario, rs.subtotal
          FROM TURISMOUQ.RESERVA_SERVICIO rs
          JOIN TURISMOUQ.SERVICIO s ON s.id_servicio = rs.id_servicio
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = s.id_alojamiento
         WHERE rs.id_reserva = %s
         ORDER BY s.nombre
    """, [id_reserva])
    pagos = _consultar("""
        SELECT id_pago, fecha_pago, valor, metodo_pago, estado
          FROM TURISMOUQ.PAGO
         WHERE id_reserva = %s
         ORDER BY fecha_pago DESC, id_pago DESC
    """, [id_reserva])
    total_habitaciones = sum((fila["valor_habitacion"] for fila in habitaciones), Decimal("0"))
    total_servicios = sum((fila["subtotal"] for fila in servicios), Decimal("0"))
    total_pagado = sum((fila["valor"] for fila in pagos if fila["estado"] == "PAGADO"), Decimal("0"))
    return {
        "reserva": reservas[0],
        "habitaciones": habitaciones,
        "servicios": servicios,
        "pagos": pagos,
        "total_habitaciones": total_habitaciones,
        "total_servicios": total_servicios,
        "total": total_habitaciones + total_servicios,
        "total_pagado": total_pagado,
    }


def cancelar_reserva(id_reserva):
    with transaction.atomic(using="turismo"):
        with connections["turismo"].cursor() as cursor:
            cursor.execute(
                "UPDATE TURISMOUQ.RESERVA SET estado = %s WHERE id_reserva = %s",
                ["CANCELADA", id_reserva],
            )
            return cursor.rowcount


def listar_clientes_pagina(termino="", numero_pagina=1, por_pagina=50):
    where = ""
    parametros = []
    if termino:
        where = " WHERE UPPER(c.nombres || ' ' || c.apellidos) LIKE %s OR TO_CHAR(c.cedula) LIKE %s OR UPPER(c.email) LIKE %s"
        patron = f"%{termino.upper()}%"
        parametros = [patron, f"%{termino}%", patron]
    total = _consultar("SELECT COUNT(*) AS total FROM TURISMOUQ.CLIENTE c" + where, parametros)[0]["total"]
    paginas = max(1, math.ceil(total / por_pagina))
    numero_pagina = min(max(1, numero_pagina), paginas)
    offset = (numero_pagina - 1) * por_pagina
    clientes = _consultar("""
        SELECT c.cedula, c.nombres, c.apellidos, c.telefono, c.email
          FROM TURISMOUQ.CLIENTE c
    """ + where + " ORDER BY c.apellidos, c.nombres, c.cedula OFFSET %s ROWS FETCH NEXT %s ROWS ONLY",
        [*parametros, offset, por_pagina])
    return clientes, total, numero_pagina, paginas


def obtener_cliente(cedula):
    clientes = _consultar("""
        SELECT cedula, nombres, apellidos, telefono, email
          FROM TURISMOUQ.CLIENTE
         WHERE cedula = %s
    """, [cedula])
    return clientes[0] if clientes else None


def crear_cliente(datos):
    with transaction.atomic(using="turismo"):
        with connections["turismo"].cursor() as cursor:
            cursor.execute("""
                INSERT INTO TURISMOUQ.CLIENTE (cedula, nombres, apellidos, telefono, email)
                VALUES (%s, %s, %s, %s, %s)
            """, [datos["cedula"], datos["nombres"], datos["apellidos"], datos["telefono"], datos["email"]])


def actualizar_cliente(cedula, datos):
    with transaction.atomic(using="turismo"):
        with connections["turismo"].cursor() as cursor:
            cursor.execute("""
                UPDATE TURISMOUQ.CLIENTE
                   SET nombres = %s, apellidos = %s, telefono = %s, email = %s
                 WHERE cedula = %s
            """, [datos["nombres"], datos["apellidos"], datos["telefono"], datos["email"], cedula])
            return cursor.rowcount


def listar_tarifas():
    return _consultar("""
        SELECT tr.id_tarifa, tr.precio_noche, h.id_habitacion, h.numero,
               h.tipo_habitacion, a.nombre AS alojamiento, m.nombre AS municipio,
               t.nombre AS temporada
          FROM TURISMOUQ.TARIFA tr
          JOIN TURISMOUQ.HABITACION h ON h.id_habitacion = tr.id_habitacion
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
          JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
          JOIN TURISMOUQ.TEMPORADA t ON t.id_temporada = tr.id_temporada
         ORDER BY m.nombre, a.nombre, h.numero,
                  CASE t.nombre WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 2 ELSE 3 END
    """)


def obtener_tarifa(id_tarifa):
    filas = _consultar("""
        SELECT tr.id_tarifa, tr.precio_noche, h.id_habitacion, h.numero,
               h.tipo_habitacion, a.nombre AS alojamiento, m.nombre AS municipio,
               t.nombre AS temporada
          FROM TURISMOUQ.TARIFA tr
          JOIN TURISMOUQ.HABITACION h ON h.id_habitacion = tr.id_habitacion
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
          JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
          JOIN TURISMOUQ.TEMPORADA t ON t.id_temporada = tr.id_temporada
         WHERE tr.id_tarifa = %s
    """, [id_tarifa])
    return filas[0] if filas else None


def actualizar_tarifa(id_tarifa, precio_noche):
    with transaction.atomic(using="turismo"):
        with connections["turismo"].cursor() as cursor:
            cursor.execute(
                "UPDATE TURISMOUQ.TARIFA SET precio_noche = %s WHERE id_tarifa = %s",
                [precio_noche, id_tarifa],
            )
            return cursor.rowcount


def listar_auditoria_tarifas(limite=500):
    return _consultar("""
        SELECT au.id_auditoria, au.usuario, au.fecha, au.operacion,
               au.id_tarifa, h.numero AS habitacion, a.nombre AS alojamiento,
               t.nombre AS temporada, au.precio_anterior, au.precio_nuevo
          FROM TURISMOUQ.AUDITORIA_TARIFA au
          LEFT JOIN TURISMOUQ.TARIFA tr ON tr.id_tarifa = au.id_tarifa
          LEFT JOIN TURISMOUQ.HABITACION h ON h.id_habitacion = tr.id_habitacion
          LEFT JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
          LEFT JOIN TURISMOUQ.TEMPORADA t ON t.id_temporada = tr.id_temporada
         ORDER BY au.id_auditoria DESC
         FETCH FIRST %s ROWS ONLY
    """, [limite])


def ejecutar_liquidacion_mensual(anio, mes):
    try:
        with transaction.atomic(using="turismo"):
            with connections["turismo"].cursor() as cursor:
                cursor.callproc("PKG_TURISMO.SP_LIQUIDACION_MENSUAL", [anio, mes])
    except Exception:
        logger.exception("Falló PKG_TURISMO.SP_LIQUIDACION_MENSUAL en Oracle")
        raise


def obtener_liquidacion_mensual(anio, mes):
    filas = _consultar("""
        SELECT l.id_alojamiento, a.nombre AS alojamiento, l.num_reservas,
               l.ingresos_habitaciones, l.ingresos_servicios,
               l.comision, l.neto_alojamiento, l.fecha_proceso
          FROM TURISMOUQ.LIQUIDACION_MENSUAL l
          JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = l.id_alojamiento
         WHERE l.anio = %s AND l.mes = %s
         ORDER BY l.neto_alojamiento DESC, a.nombre
    """, [anio, mes])
    totales = {
        "num_reservas": sum((fila["num_reservas"] for fila in filas), 0),
        "ingresos_habitaciones": sum((fila["ingresos_habitaciones"] for fila in filas), Decimal("0")),
        "ingresos_servicios": sum((fila["ingresos_servicios"] for fila in filas), Decimal("0")),
        "comision": sum((fila["comision"] for fila in filas), Decimal("0")),
        "neto_alojamiento": sum((fila["neto_alojamiento"] for fila in filas), Decimal("0")),
    }
    return filas, totales


REPORTES_SQL = {
    "pivot": ("Ocupación por municipio y mes (PIVOT)", """
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
    FOR mes IN (1 AS ENE, 2 AS FEB, 3 AS MAR, 4 AS ABR, 5 AS MAY, 6 AS JUN,
                7 AS JUL, 8 AS AGO, 9 AS SEP, 10 AS OCT, 11 AS NOV, 12 AS DIC)
)
ORDER BY municipio
"""),
    "rollup": ("Ingresos por municipio, tipo y temporada (ROLLUP)", """
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
JOIN PERIODO_TEMPORADA pt ON r.fecha_checkin BETWEEN pt.fecha_inicio AND pt.fecha_fin
JOIN TEMPORADA t ON t.id_temporada = pt.id_temporada
GROUP BY ROLLUP(m.nombre, ta.nombre, t.nombre)
ORDER BY municipio, tipo_alojamiento, temporada
"""),
    "top-alojamientos": ("Top 3 alojamientos por municipio (RANK)", """
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
ORDER BY municipio, ranking
"""),
    "variacion": ("Variación de ingresos mes a mes (LAG)", """
SELECT anio, mes, ingresos,
       LAG(ingresos) OVER (ORDER BY anio, mes) AS ingresos_mes_anterior,
       ingresos - LAG(ingresos) OVER (ORDER BY anio, mes) AS variacion,
       ROUND((ingresos - LAG(ingresos) OVER (ORDER BY anio, mes)) /
             LAG(ingresos) OVER (ORDER BY anio, mes) * 100, 2) AS variacion_pct
FROM (
    SELECT EXTRACT(YEAR FROM r.fecha_checkin) AS anio,
           EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
           SUM(rh.valor_habitacion) AS ingresos
    FROM RESERVA_HABITACION rh
    JOIN RESERVA r ON r.id_reserva = rh.id_reserva
    GROUP BY EXTRACT(YEAR FROM r.fecha_checkin), EXTRACT(MONTH FROM r.fecha_checkin)
)
ORDER BY anio, mes
"""),
    "por-fechas": ("Reservas por rango de fechas", """
SELECT r.id_reserva,
       c.nombres || ' ' || c.apellidos AS cliente,
       r.fecha_checkin,
       r.fecha_checkout,
       rh.valor_habitacion,
       r.estado
FROM RESERVA r
JOIN CLIENTE c ON c.cedula = r.id_cliente
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE r.fecha_checkin >= %s AND r.fecha_checkin < %s
ORDER BY r.fecha_checkin
"""),
    "ocupacion-mensual": ("Vista materializada de ocupación mensual", """
SELECT *
FROM MV_OCUPACION_MENSUAL
ORDER BY municipio, anio, mes
"""),
    "unpivot": ("Ingresos por método de pago y municipio (UNPIVOT)", """
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
UNPIVOT (total FOR metodo_pago IN (TARJETA, TRANSFERENCIA, PSE, EFECTIVO))
ORDER BY municipio, metodo_pago
"""),
    "top-clientes": ("Top 5 clientes por gasto", """
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
               NVL(rh.total_habitacion, 0) + NVL(rs.total_servicio, 0) AS total_reserva
        FROM RESERVA r
        LEFT JOIN (SELECT id_reserva, SUM(valor_habitacion) AS total_habitacion
                     FROM RESERVA_HABITACION GROUP BY id_reserva) rh ON rh.id_reserva = r.id_reserva
        LEFT JOIN (SELECT id_reserva, SUM(subtotal) AS total_servicio
                     FROM RESERVA_SERVICIO GROUP BY id_reserva) rs ON rs.id_reserva = r.id_reserva
    ) t ON t.id_cliente = c.cedula
    GROUP BY c.cedula, c.nombres, c.apellidos
    ORDER BY gasto_total DESC
)
WHERE ROWNUM <= 5
"""),
}

MONETARY_REPORT_COLUMNS = {
    "ingresos", "ingresos_mes_anterior", "variacion", "valor_habitacion", "total",
    "tarjeta", "transferencia", "pse", "efectivo", "gasto_total",
}


def obtener_reporte(slug, fecha_inicio=None, fecha_fin=None):
    titulo, sql = REPORTES_SQL[slug]
    if slug == "por-fechas":
        nombres_columnas, filas = _consultar_detallado(sql, [fecha_inicio, fecha_fin + timedelta(days=1)])
    else:
        nombres_columnas, filas = _consultar_detallado(sql)
    columnas = [
        {"nombre": nombre, "etiqueta": nombre.replace("_", " ").title(),
         "monetaria": nombre in MONETARY_REPORT_COLUMNS}
        for nombre in nombres_columnas
    ]
    datos = {"titulo": titulo, "sql": sql.strip(), "columnas": columnas, "filas": filas}
    if slug == "ocupacion-mensual":
        refresco = _consultar(
            "SELECT LAST_REFRESH_DATE FROM USER_MVIEWS WHERE MVIEW_NAME = %s",
            ["MV_OCUPACION_MENSUAL"],
        )
        datos["fecha_refresco"] = refresco[0]["last_refresh_date"] if refresco else None
        datos["sql_auxiliar"] = (
            "BEGIN DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C'); END;\n"
            "SELECT LAST_REFRESH_DATE FROM USER_MVIEWS WHERE MVIEW_NAME = %s"
        )
    return datos


def refrescar_vista_ocupacion():
    try:
        with connections["turismo"].cursor() as cursor:
            cursor.callproc("DBMS_MVIEW.REFRESH", ["MV_OCUPACION_MENSUAL", "C"])
            cursor.execute("SELECT LAST_REFRESH_DATE FROM USER_MVIEWS WHERE MVIEW_NAME = %s", ["MV_OCUPACION_MENSUAL"])
            fila = cursor.fetchone()
        return fila[0] if fila else None
    except Exception:
        logger.exception("Falló DBMS_MVIEW.REFRESH para MV_OCUPACION_MENSUAL")
        raise
