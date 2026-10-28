from django.urls import path

from . import views

urlpatterns = [
    path("", views.tablero, name="tablero"),
    path("diagnostico/", views.diagnostico, name="diagnostico"),
    path("alojamientos/", views.alojamientos, name="alojamientos"),
    path("alojamientos/<int:id_alojamiento>/", views.alojamiento_detalle, name="alojamiento_detalle"),
    path("disponibilidad/", views.disponibilidad, name="disponibilidad"),
    path("reservas/nueva/<int:id_habitacion>/", views.crear_reserva, name="reserva_crear"),
    path("reservas/", views.reservas, name="reservas"),
    path("reservas/<int:id_reserva>/cancelar/", views.cancelar_reserva, name="reserva_cancelar"),
    path("reservas/<int:id_reserva>/estado/", views.cambiar_estado_reserva, name="reserva_cambiar_estado"),
    path(
        "reservas/<int:id_reserva>/habitaciones/<int:id_habitacion>/agregar/",
        views.reservar_otra_habitacion,
        name="reserva_agregar_habitacion",
    ),
    path("reservas/<int:id_reserva>/", views.reserva_confirmacion, name="reserva_confirmacion"),
    path("clientes/", views.clientes, name="clientes"),
    path("clientes/nuevo/", views.cliente_nuevo, name="cliente_nuevo"),
    path("clientes/<int:cedula>/editar/", views.cliente_editar, name="cliente_editar"),
    path("tarifas/", views.tarifas, name="tarifas"),
    path("tarifas/auditoria/", views.auditoria_tarifas, name="auditoria_tarifas"),
    path("tarifas/<int:id_tarifa>/editar/", views.tarifa_editar, name="tarifa_editar"),
    path("liquidaciones/", views.liquidaciones, name="liquidaciones"),
    path("reportes/", views.reportes, name="reportes"),
    path("reportes/<slug:slug>/", views.reporte, name="reporte"),
]
