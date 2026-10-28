from django import forms


class FechasEstadiaMixin(forms.Form):
    fecha_entrada = forms.DateField(
        label="Fecha de entrada",
        input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )
    fecha_salida = forms.DateField(
        label="Fecha de salida",
        input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )

    def clean(self):
        datos = super().clean()
        entrada = datos.get("fecha_entrada")
        salida = datos.get("fecha_salida")
        if entrada and salida and salida <= entrada:
            self.add_error("fecha_salida", "La fecha de salida debe ser posterior a la entrada.")
        return datos


class DisponibilidadForm(FechasEstadiaMixin):
    municipio = forms.ChoiceField(
        label="Municipio (opcional)", required=False, choices=[("", "Todos los municipios")],
        widget=forms.Select(attrs={"class": "form-select"}),
    )
    huespedes = forms.IntegerField(
        label="Huéspedes", min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1, "value": 1}),
    )
    reserva = forms.IntegerField(required=False, min_value=1, widget=forms.HiddenInput())


class ReservaForm(FechasEstadiaMixin):
    cedula_cliente = forms.IntegerField(
        label="Cédula del cliente", min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1, "autocomplete": "off"}),
    )
    id_usuario = forms.ChoiceField(
        label="Usuario del sistema", choices=[],
        widget=forms.Select(attrs={"class": "form-select"}),
    )
    huespedes = forms.IntegerField(
        label="Huéspedes en esta habitación", min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1}),
    )

    def __init__(self, *args, usuarios=(), **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["id_usuario"].choices = [
            (str(usuario["id_usuario"]), f'{usuario["nombre_completo"]} · {usuario["rol"]}')
            for usuario in usuarios
        ]
        self.cliente_encontrado = None


class AgregarHabitacionForm(forms.Form):
    huespedes = forms.IntegerField(
        label="Huéspedes en esta habitación", min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1}),
    )


class AlojamientoFiltroForm(forms.Form):
    municipio = forms.ChoiceField(
        label="Municipio",
        required=False,
        choices=[("", "Todos los municipios")],
        widget=forms.Select(attrs={"class": "form-select"}),
    )
    tipo = forms.ChoiceField(
        label="Tipo de alojamiento",
        required=False,
        choices=[("", "Todos los tipos")],
        widget=forms.Select(attrs={"class": "form-select"}),
    )


class ReservaFiltroForm(forms.Form):
    estado = forms.ChoiceField(
        label="Estado", required=False,
        choices=[("", "Todos"), ("PENDIENTE", "Pendiente"), ("CONFIRMADA", "Confirmada"),
                 ("FINALIZADA", "Finalizada"), ("CANCELADA", "Cancelada")],
        widget=forms.Select(attrs={"class": "form-select"}),
    )
    fecha_desde = forms.DateField(
        label="Check-in desde", required=False, input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )
    fecha_hasta = forms.DateField(
        label="Check-in hasta", required=False, input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )
    cliente = forms.IntegerField(
        label="Cédula del cliente", required=False, min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1}),
    )

    def clean(self):
        datos = super().clean()
        if datos.get("fecha_desde") and datos.get("fecha_hasta") and datos["fecha_hasta"] < datos["fecha_desde"]:
            self.add_error("fecha_hasta", "La fecha final debe ser igual o posterior a la inicial.")
        return datos


class ClienteCrearForm(forms.Form):
    cedula = forms.IntegerField(label="Cédula", min_value=1, widget=forms.NumberInput(attrs={"class": "form-control", "min": 1}))
    nombres = forms.CharField(label="Nombres", max_length=60, widget=forms.TextInput(attrs={"class": "form-control"}))
    apellidos = forms.CharField(label="Apellidos", max_length=100, widget=forms.TextInput(attrs={"class": "form-control"}))
    telefono = forms.CharField(label="Teléfono", max_length=30, widget=forms.TextInput(attrs={"class": "form-control"}))
    email = forms.EmailField(label="Correo electrónico", max_length=150, widget=forms.EmailInput(attrs={"class": "form-control"}))


class ClienteEditarForm(forms.Form):
    nombres = forms.CharField(label="Nombres", max_length=60, widget=forms.TextInput(attrs={"class": "form-control"}))
    apellidos = forms.CharField(label="Apellidos", max_length=100, widget=forms.TextInput(attrs={"class": "form-control"}))
    telefono = forms.CharField(label="Teléfono", max_length=30, widget=forms.TextInput(attrs={"class": "form-control"}))
    email = forms.EmailField(label="Correo electrónico", max_length=150, widget=forms.EmailInput(attrs={"class": "form-control"}))


class TarifaEditarForm(forms.Form):
    precio_noche = forms.DecimalField(
        label="Precio por noche", min_value=0, max_digits=12, decimal_places=2,
        widget=forms.NumberInput(attrs={"class": "form-control form-control-sm", "min": 0, "step": "1000"}),
    )


class LiquidacionMensualForm(forms.Form):
    anio = forms.IntegerField(
        label="Año", min_value=1, max_value=9999,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "max": 9999, "step": 1}),
    )
    # Sin máximo deliberadamente: el paquete Oracle debe responder ORA-20010
    # para meses como 13 y la aplicación traduce ese error al usuario.
    mes = forms.IntegerField(
        label="Mes", min_value=1,
        widget=forms.NumberInput(attrs={"class": "form-control", "min": 1, "step": 1}),
    )


class ReporteFechasForm(forms.Form):
    fecha_inicio = forms.DateField(
        label="Checkin desde", input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )
    fecha_fin = forms.DateField(
        label="Checkin hasta", input_formats=["%Y-%m-%d"],
        widget=forms.DateInput(attrs={"type": "date", "class": "form-control"}),
    )

    def clean(self):
        datos = super().clean()
        if datos.get("fecha_inicio") and datos.get("fecha_fin") and datos["fecha_fin"] < datos["fecha_inicio"]:
            self.add_error("fecha_fin", "El checkin hasta debe ser igual o posterior al checkin desde.")
        return datos


ANIOS_REPORTE = (2024, 2025, 2026)


class ReporteAnioForm(forms.Form):
    anio = forms.TypedChoiceField(
        label="Año", coerce=int,
        choices=[(anio, str(anio)) for anio in ANIOS_REPORTE],
        widget=forms.Select(attrs={"class": "form-select"}),
    )
