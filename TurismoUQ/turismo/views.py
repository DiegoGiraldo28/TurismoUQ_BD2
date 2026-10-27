from datetime import date
import logging

from django.conf import settings
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import redirect, render
from django.views.decorators.http import require_POST
from django.utils import timezone

from .forms import (
    AgregarHabitacionForm,
    AlojamientoFiltroForm,
    ClienteCrearForm,
    ClienteEditarForm,
    DisponibilidadForm,
    LiquidacionMensualForm,
    ReservaFiltroForm,
    ReservaForm,
    ReporteFechasForm,
    TarifaEditarForm,
)
from .services import (
    agregar_habitacion as servicio_agregar_habitacion,
    actualizar_cliente,
    actualizar_tarifa,
    buscar_cliente_por_cedula,
    cancelar_reserva as servicio_cancelar_reserva,
    conteos_tablas,
    contexto_agregar_habitacion,
    crear_cliente,
    crear_reserva as servicio_crear_reserva,
    datos_tablero,
    detalle_error_tecnico,
    detalle_alojamiento,
    detalle_reserva,
    ejecutar_liquidacion_mensual,
    es_error_de_conexion_oracle,
    habitaciones_disponibles,
    listar_alojamientos,
    listar_auditoria_tarifas,
    listar_clientes_pagina,
    listar_reservas_pagina,
    listar_tarifas,
    mensaje_error_oracle,
    codigo_error_oracle,
    obtener_cliente,
    obtener_liquidacion_mensual,
    obtener_reporte,
    obtener_reserva,
    obtener_tarifa,
    opciones_alojamiento,
    opciones_usuarios_sistema,
    REPORTES_SQL,
    refrescar_vista_ocupacion,
)

logger = logging.getLogger(__name__)


def _mostrar_error(request, exc, mensaje_personalizado=None):
    logger.exception("Error durante una operación de base de datos o una solicitud TurismoUQ")
    if mensaje_personalizado:
        messages.error(request, mensaje_personalizado)
    elif es_error_de_conexion_oracle(exc):
        mensaje = mensaje_error_oracle(exc)
        if mensaje.startswith("No fue posible completar"):
            mensaje = (
                "No fue posible consultar la base de datos de TurismoUQ. "
                "Verifica que Oracle XE esté iniciado y que la configuración sea correcta."
            )
        messages.error(request, mensaje)
    else:
        messages.error(request, "No fue posible consultar la información de TurismoUQ.")
    if settings.DEBUG:
        messages.error(request, f"Detalle técnico (DEBUG): {detalle_error_tecnico(exc)}")


@login_required
def diagnostico(request):
    try:
        filas = conteos_tablas()
    except Exception as exc:
        _mostrar_error(request, exc)
        filas = []
    return render(request, "turismo/diagnostico.html", {"filas": filas})


@login_required
def tablero(request):
    try:
        resumen, ocupacion = datos_tablero()
    except Exception as exc:
        _mostrar_error(request, exc)
        resumen, ocupacion = {}, []
    return render(request, "turismo/tablero.html", {
        "resumen": resumen,
        "ocupacion": ocupacion,
        "grafico_labels": [f"{fila['mes']:02d}/{fila['anio']}" for fila in ocupacion],
        "grafico_reservas": [int(fila["reservas"]) for fila in ocupacion],
    })


@login_required
def alojamientos(request):
    try:
        municipios, tipos = opciones_alojamiento()
        form = AlojamientoFiltroForm(request.GET or None)
        form.fields["municipio"].choices += [(str(fila["id_municipio"]), fila["nombre"]) for fila in municipios]
        form.fields["tipo"].choices += [(str(fila["id_tipo_alojamiento"]), fila["nombre"]) for fila in tipos]
        resultados = []
        if not form.is_bound:
            resultados = listar_alojamientos()
        elif form.is_valid():
            municipio = form.cleaned_data["municipio"] or None
            tipo = form.cleaned_data["tipo"] or None
            resultados = listar_alojamientos(municipio, tipo)
    except Exception as exc:
        _mostrar_error(request, exc)
        form = AlojamientoFiltroForm(request.GET or None)
        resultados = []
    return render(request, "turismo/alojamientos.html", {"form": form, "alojamientos": resultados})


@login_required
def alojamiento_detalle(request, id_alojamiento):
    try:
        datos = detalle_alojamiento(id_alojamiento)
    except Exception as exc:
        _mostrar_error(request, exc)
        datos = None
    if datos is None:
        raise Http404("No se encontró el alojamiento solicitado.")
    return render(request, "turismo/alojamiento_detalle.html", datos)


@login_required
def disponibilidad(request):
    resultados = []
    reserva = None
    busqueda = None
    try:
        municipios, _ = opciones_alojamiento()
        form = DisponibilidadForm(request.GET or None)
        form.fields["municipio"].choices += [
            (str(fila["id_municipio"]), fila["nombre"]) for fila in municipios
        ]
        if form.is_bound and form.is_valid():
            datos = form.cleaned_data
            busqueda = datos
            reserva_id = datos.get("reserva")
            resultados = habitaciones_disponibles(
                datos["fecha_entrada"],
                datos["fecha_salida"],
                datos["huespedes"],
                datos.get("municipio") or None,
                reserva_id,
            )
            if reserva_id:
                reserva = obtener_reserva(reserva_id)
                if reserva is None:
                    form.add_error("reserva", "No se encontró la reserva seleccionada.")
                    resultados = []
    except Exception as exc:
        _mostrar_error(request, exc)
        form = DisponibilidadForm(request.GET or None)
    return render(request, "turismo/disponibilidad.html", {
        "form": form,
        "habitaciones": resultados,
        "reserva": reserva,
        "busqueda": busqueda,
    })


def _contexto_nueva_reserva(id_habitacion, form, cliente=None):
    cotizacion = None
    habitacion = None
    fecha_entrada = form.data.get("fecha_entrada") if form.is_bound else form.initial.get("fecha_entrada")
    fecha_salida = form.data.get("fecha_salida") if form.is_bound else form.initial.get("fecha_salida")
    try:
        fecha_entrada = fecha_entrada if hasattr(fecha_entrada, "year") else date.fromisoformat(str(fecha_entrada))
        fecha_salida = fecha_salida if hasattr(fecha_salida, "year") else date.fromisoformat(str(fecha_salida))
        from .services import cotizar_habitacion
        cotizacion, desglose = cotizar_habitacion(id_habitacion, fecha_entrada, fecha_salida)
        habitacion = _habitacion_por_id(id_habitacion)
    except (ValueError, TypeError):
        desglose = []
    return {
        "id_habitacion": id_habitacion,
        "habitacion": habitacion,
        "cotizacion": cotizacion,
        "desglose": desglose,
        "cliente": cliente,
    }


def _habitacion_por_id(id_habitacion):
    from django.db import connections

    with connections["turismo"].cursor() as cursor:
        cursor.execute("""
            SELECT h.id_habitacion, h.numero, h.tipo_habitacion, h.capacidad,
                   a.nombre AS alojamiento, m.nombre AS municipio
              FROM TURISMOUQ.HABITACION h
              JOIN TURISMOUQ.ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
              JOIN TURISMOUQ.MUNICIPIO m ON m.id_municipio = a.id_municipio
             WHERE h.id_habitacion = %s
        """, [id_habitacion])
        fila = cursor.fetchone()
        if fila is None:
            return None
        columnas = [columna[0].lower() for columna in cursor.description]
        return dict(zip(columnas, fila))


@login_required
def crear_reserva(request, id_habitacion):
    try:
        usuarios = opciones_usuarios_sistema()
        if request.method == "POST":
            if request.POST.get("accion") == "buscar_cliente":
                datos = {campo: request.POST.get(campo, "") for campo in (
                    "fecha_entrada", "fecha_salida", "huespedes", "cedula_cliente", "id_usuario"
                )}
                form = ReservaForm(initial=datos, usuarios=usuarios)
                try:
                    cedula = int(datos["cedula_cliente"])
                    cliente = buscar_cliente_por_cedula(cedula) if cedula > 0 else None
                    if cliente:
                        messages.success(request, f'Cliente encontrado: {cliente["nombres"]} {cliente["apellidos"]}.')
                    else:
                        form.add_error("cedula_cliente", "No existe un cliente con esa cédula.")
                except (ValueError, TypeError):
                    cliente = None
                    form.add_error("cedula_cliente", "Ingresa una cédula válida para buscar el cliente.")
            else:
                form = ReservaForm(request.POST, usuarios=usuarios)
                cliente = None
                if form.is_valid():
                    cliente = buscar_cliente_por_cedula(form.cleaned_data["cedula_cliente"])
                    if cliente is None:
                        form.add_error("cedula_cliente", "No existe un cliente con esa cédula.")
                    else:
                        contexto = _contexto_nueva_reserva(id_habitacion, form, cliente)
                        try:
                            id_reserva = servicio_crear_reserva(
                                int(form.cleaned_data["id_usuario"]),
                                form.cleaned_data["cedula_cliente"],
                                id_habitacion,
                                form.cleaned_data["fecha_entrada"],
                                form.cleaned_data["fecha_salida"],
                                form.cleaned_data["huespedes"],
                            )
                        except Exception as exc:
                            _mostrar_error(request, exc)
                        else:
                            messages.success(request, f"Reserva {id_reserva} creada correctamente.")
                            return redirect("reserva_confirmacion", id_reserva=id_reserva)
        else:
            initial = {
                "fecha_entrada": request.GET.get("fecha_entrada", ""),
                "fecha_salida": request.GET.get("fecha_salida", ""),
                "huespedes": request.GET.get("huespedes", "1"),
            }
            form = ReservaForm(initial=initial, usuarios=usuarios)
            cliente = None
        contexto = _contexto_nueva_reserva(id_habitacion, form, cliente)
    except Exception as exc:
        _mostrar_error(request, exc)
        form = ReservaForm(request.POST or None, usuarios=())
        contexto = {"id_habitacion": id_habitacion, "habitacion": None, "cotizacion": None, "desglose": [], "cliente": None}
    contexto["form"] = form
    return render(request, "turismo/reserva_nueva.html", contexto)


@login_required
def reserva_confirmacion(request, id_reserva):
    try:
        datos = detalle_reserva(id_reserva)
    except Exception as exc:
        _mostrar_error(request, exc)
        datos = None
    if datos is None:
        raise Http404("No se encontró la reserva solicitada.")
    return render(request, "turismo/reserva_confirmacion.html", datos)


@login_required
def reservar_otra_habitacion(request, id_reserva, id_habitacion):
    contexto = None
    try:
        contexto = contexto_agregar_habitacion(id_reserva, id_habitacion)
        if contexto is None:
            raise Http404("No se encontró la reserva o la habitación solicitada.")
        form = AgregarHabitacionForm(request.POST or None)
        if request.method == "POST" and form.is_valid():
            servicio_agregar_habitacion(id_reserva, id_habitacion, form.cleaned_data["huespedes"])
            messages.success(request, f"La habitación se agregó a la reserva {id_reserva}.")
            return redirect("reserva_confirmacion", id_reserva=id_reserva)
    except Http404:
        raise
    except Exception as exc:
        _mostrar_error(request, exc)
        contexto = contexto or {"reserva": {"id_reserva": id_reserva}, "habitacion": {"id_habitacion": id_habitacion}, "cotizacion": None, "desglose": []}
        form = AgregarHabitacionForm(request.POST or None)
    contexto["form"] = form
    return render(request, "turismo/reserva_agregar_habitacion.html", contexto)


def _numero_pagina(request):
    try:
        return max(1, int(request.GET.get("page", "1")))
    except (TypeError, ValueError):
        return 1


def _enlaces_paginacion(request, actual, total):
    return [
        {"numero": pagina, "url": _url_pagina(request, pagina)}
        for pagina in range(max(1, actual - 2), min(total, actual + 2) + 1)
    ]


def _url_pagina(request, pagina):
    parametros = request.GET.copy()
    parametros.pop("page", None)
    base = parametros.urlencode()
    return f"?{base + '&' if base else ''}page={pagina}"


@login_required
def reservas(request):
    form = ReservaFiltroForm(request.GET or None)
    filtros = {}
    if form.is_bound and form.is_valid():
        filtros = form.cleaned_data
    try:
        filas, total, pagina, total_paginas = listar_reservas_pagina(filtros, _numero_pagina(request))
    except Exception as exc:
        _mostrar_error(request, exc)
        filas, total, pagina, total_paginas = [], 0, 1, 1
    return render(request, "turismo/reservas.html", {
        "form": form,
        "reservas": filas,
        "total": total,
        "pagina": pagina,
        "total_paginas": total_paginas,
        "paginas": _enlaces_paginacion(request, pagina, total_paginas),
        "hay_anterior": pagina > 1,
        "hay_siguiente": pagina < total_paginas,
        "url_anterior": _url_pagina(request, pagina - 1),
        "url_siguiente": _url_pagina(request, pagina + 1),
    })


@login_required
@require_POST
def cancelar_reserva(request, id_reserva):
    try:
        filas = servicio_cancelar_reserva(id_reserva)
        if filas:
            messages.success(request, f"La reserva {id_reserva} fue cancelada.")
        else:
            messages.warning(request, "No se encontró la reserva para cancelar.")
    except Exception as exc:
        _mostrar_error(request, exc)
    return redirect("reserva_confirmacion", id_reserva=id_reserva)


@login_required
def clientes(request):
    termino = request.GET.get("q", "").strip()[:100]
    try:
        filas, total, pagina, total_paginas = listar_clientes_pagina(termino, _numero_pagina(request))
    except Exception as exc:
        _mostrar_error(request, exc)
        filas, total, pagina, total_paginas = [], 0, 1, 1
    return render(request, "turismo/clientes.html", {
        "clientes": filas,
        "termino": termino,
        "total": total,
        "pagina": pagina,
        "total_paginas": total_paginas,
        "paginas": _enlaces_paginacion(request, pagina, total_paginas),
        "hay_anterior": pagina > 1,
        "hay_siguiente": pagina < total_paginas,
        "url_anterior": _url_pagina(request, pagina - 1),
        "url_siguiente": _url_pagina(request, pagina + 1),
    })


@login_required
def cliente_nuevo(request):
    form = ClienteCrearForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        try:
            crear_cliente(form.cleaned_data)
        except Exception as exc:
            if codigo_error_oracle(exc) == 1:
                _mostrar_error(request, exc, "Ya existe un cliente con esa cédula o correo electrónico.")
            else:
                _mostrar_error(request, exc)
        else:
            messages.success(request, "Cliente creado correctamente.")
            return redirect("clientes")
    return render(request, "turismo/cliente_formulario.html", {"form": form, "titulo": "Crear cliente"})


@login_required
def cliente_editar(request, cedula):
    try:
        cliente = obtener_cliente(cedula)
    except Exception as exc:
        _mostrar_error(request, exc)
        cliente = None
    if cliente is None:
        raise Http404("No se encontró el cliente solicitado.")
    form = ClienteEditarForm(request.POST or None, initial={
        campo: cliente[campo] for campo in ("nombres", "apellidos", "telefono", "email")
    })
    if request.method == "POST" and form.is_valid():
        try:
            actualizadas = actualizar_cliente(cedula, form.cleaned_data)
            if not actualizadas:
                raise Http404("No se encontró el cliente solicitado.")
        except Http404:
            raise
        except Exception as exc:
            if codigo_error_oracle(exc) == 1:
                _mostrar_error(request, exc, "Ese correo electrónico ya está registrado para otro cliente.")
            else:
                _mostrar_error(request, exc)
        else:
            messages.success(request, "Cliente actualizado correctamente.")
            return redirect("clientes")
    return render(request, "turismo/cliente_formulario.html", {
        "form": form, "titulo": "Editar cliente", "cliente": cliente,
    })


@login_required
def tarifas(request):
    try:
        filas = listar_tarifas()
    except Exception as exc:
        _mostrar_error(request, exc)
        filas = []
    return render(request, "turismo/tarifas.html", {"tarifas": filas})


@login_required
def tarifa_editar(request, id_tarifa):
    try:
        tarifa = obtener_tarifa(id_tarifa)
    except Exception as exc:
        _mostrar_error(request, exc)
        tarifa = None
    if tarifa is None:
        raise Http404("No se encontró la tarifa solicitada.")
    form = TarifaEditarForm(request.POST or None, initial={"precio_noche": tarifa["precio_noche"]})
    if request.method == "POST" and form.is_valid():
        try:
            actualizadas = actualizar_tarifa(id_tarifa, form.cleaned_data["precio_noche"])
            if not actualizadas:
                raise Http404("No se encontró la tarifa solicitada.")
        except Http404:
            raise
        except Exception as exc:
            _mostrar_error(request, exc)
        else:
            messages.success(request, "Tarifa actualizada; el cambio quedó registrado en la auditoría Oracle.")
            return redirect("tarifas")
    return render(request, "turismo/tarifa_editar.html", {"tarifa": tarifa, "form": form})


@login_required
def auditoria_tarifas(request):
    try:
        filas = listar_auditoria_tarifas()
    except Exception as exc:
        _mostrar_error(request, exc)
        filas = []
    return render(request, "turismo/auditoria_tarifas.html", {"auditoria": filas})


@login_required
def liquidaciones(request):
    hoy = timezone.localdate()
    resultados = []
    totales = None
    if request.method == "POST":
        form = LiquidacionMensualForm(request.POST)
        if form.is_valid():
            anio, mes = form.cleaned_data["anio"], form.cleaned_data["mes"]
            try:
                ejecutar_liquidacion_mensual(anio, mes)
                resultados, totales = obtener_liquidacion_mensual(anio, mes)
            except Exception as exc:
                _mostrar_error(request, exc)
            else:
                messages.success(request, f"Liquidación de {mes:02d}/{anio} ejecutada correctamente.")
    else:
        form = LiquidacionMensualForm(request.GET or None, initial={"anio": hoy.year, "mes": hoy.month})
        if form.is_bound and form.is_valid():
            try:
                resultados, totales = obtener_liquidacion_mensual(
                    form.cleaned_data["anio"], form.cleaned_data["mes"]
                )
            except Exception as exc:
                _mostrar_error(request, exc)
    return render(request, "turismo/liquidaciones.html", {
        "form": form, "liquidaciones": resultados, "totales": totales,
    })


REPORTES_MENU = [
    ("pivot", "Ocupación por municipio y mes (PIVOT)"),
    ("rollup", "Ingresos con subtotales (ROLLUP y GROUPING)"),
    ("top-alojamientos", "Top 3 alojamientos por municipio (RANK)"),
    ("variacion", "Variación mensual de ingresos (LAG)"),
    ("por-fechas", "Reservas por rango de fechas"),
    ("ocupacion-mensual", "Vista materializada de ocupación"),
    ("unpivot", "Ingresos por método de pago (UNPIVOT)"),
    ("top-clientes", "Top 5 clientes por gasto"),
]


@login_required
def reportes(request):
    return render(request, "turismo/reportes.html", {"reportes": REPORTES_MENU})


@login_required
def reporte(request, slug):
    titulos = dict(REPORTES_MENU)
    if slug not in titulos:
        raise Http404("No se encontró el reporte solicitado.")
    if slug == "ocupacion-mensual" and request.method == "POST":
        try:
            fecha = refrescar_vista_ocupacion()
        except Exception as exc:
            _mostrar_error(request, exc)
        else:
            fecha_texto = fecha.strftime("%d/%m/%Y %H:%M") if fecha else "no disponible"
            messages.success(request, f"Vista materializada actualizada. Último refresco: {fecha_texto}.")

    form = None
    datos = {
        "titulo": titulos[slug],
        "sql": REPORTES_SQL[slug][1].strip(),
        "columnas": [],
        "filas": [],
    }
    if slug == "ocupacion-mensual":
        datos["sql_auxiliar"] = (
            "BEGIN DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C'); END;\n"
            "SELECT LAST_REFRESH_DATE FROM USER_MVIEWS WHERE MVIEW_NAME = %s"
        )
    mostrar_tabla = False
    if slug == "por-fechas":
        form = ReporteFechasForm(request.GET or None)
        if form.is_bound and form.is_valid():
            try:
                datos = obtener_reporte(slug, form.cleaned_data["fecha_inicio"], form.cleaned_data["fecha_fin"])
                mostrar_tabla = True
            except Exception as exc:
                _mostrar_error(request, exc)
    else:
        try:
            datos = obtener_reporte(slug)
            mostrar_tabla = True
        except Exception as exc:
            _mostrar_error(request, exc)
    return render(request, "turismo/reporte_tabla.html", {
        "reporte": datos,
        "titulo": titulos[slug],
        "form": form,
        "slug": slug,
        "mostrar_tabla": mostrar_tabla,
        "menu_reportes": REPORTES_MENU,
    })
