"""Modelos de lectura para catálogos existentes de Oracle.

Se contrastaron los nombres y tipos con 01_DDL.sql. Son unmanaged: Django no
crea ni altera estas tablas.
"""
from django.db import models


class Municipio(models.Model):
    id_municipio = models.IntegerField(primary_key=True, db_column="id_municipio")
    nombre = models.CharField(max_length=100)
    descripcion = models.CharField(max_length=500)

    class Meta:
        managed = False
        db_table = "MUNICIPIO"


class TipoAlojamiento(models.Model):
    id_tipo_alojamiento = models.IntegerField(primary_key=True, db_column="id_tipo_alojamiento")
    nombre = models.CharField(max_length=100)
    descripcion = models.CharField(max_length=500)

    class Meta:
        managed = False
        db_table = "TIPO_ALOJAMIENTO"


class Temporada(models.Model):
    id_temporada = models.IntegerField(primary_key=True, db_column="id_temporada")
    nombre = models.CharField(max_length=20)
    descripcion = models.CharField(max_length=500)

    class Meta:
        managed = False
        db_table = "TEMPORADA"


class Alojamiento(models.Model):
    id_alojamiento = models.IntegerField(primary_key=True, db_column="id_alojamiento")
    municipio = models.ForeignKey(Municipio, models.DO_NOTHING, db_column="id_municipio", related_name="alojamientos", db_constraint=False)
    tipo_alojamiento = models.ForeignKey(TipoAlojamiento, models.DO_NOTHING, db_column="id_tipo_alojamiento", related_name="alojamientos", db_constraint=False)
    nombre = models.CharField(max_length=150)
    direccion = models.CharField(max_length=250)
    telefono = models.CharField(max_length=30)
    correo = models.CharField(max_length=150)
    capacidad_total = models.IntegerField()
    estado = models.CharField(max_length=30)

    class Meta:
        managed = False
        db_table = "ALOJAMIENTO"


class Habitacion(models.Model):
    id_habitacion = models.IntegerField(primary_key=True, db_column="id_habitacion")
    alojamiento = models.ForeignKey(Alojamiento, models.DO_NOTHING, db_column="id_alojamiento", related_name="habitaciones", db_constraint=False)
    numero = models.CharField(max_length=20)
    tipo_habitacion = models.CharField(max_length=60)
    capacidad = models.IntegerField()
    estado = models.CharField(max_length=30)
    descripcion = models.CharField(max_length=500)

    class Meta:
        managed = False
        db_table = "HABITACION"


class Servicio(models.Model):
    id_servicio = models.IntegerField(primary_key=True, db_column="id_servicio")
    alojamiento = models.ForeignKey(Alojamiento, models.DO_NOTHING, db_column="id_alojamiento", related_name="servicios", db_constraint=False)
    nombre = models.CharField(max_length=100)
    descripcion = models.CharField(max_length=500)
    precio = models.DecimalField(max_digits=12, decimal_places=2)
    estado = models.CharField(max_length=30)

    class Meta:
        managed = False
        db_table = "SERVICIO"


class Tarifa(models.Model):
    id_tarifa = models.IntegerField(primary_key=True, db_column="id_tarifa")
    habitacion = models.ForeignKey(Habitacion, models.DO_NOTHING, db_column="id_habitacion", related_name="tarifas", db_constraint=False)
    temporada = models.ForeignKey(Temporada, models.DO_NOTHING, db_column="id_temporada", related_name="tarifas", db_constraint=False)
    precio_noche = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        managed = False
        db_table = "TARIFA"


class Resena(models.Model):
    id_resena = models.IntegerField(primary_key=True, db_column="id_resena")
    cliente = models.ForeignKey("Cliente", models.DO_NOTHING, db_column="cedula_cliente", related_name="resenas", db_constraint=False)
    alojamiento = models.ForeignKey(Alojamiento, models.DO_NOTHING, db_column="id_alojamiento", related_name="resenas", db_constraint=False)
    calificacion = models.IntegerField()
    comentario = models.CharField(max_length=1000)
    fecha_resena = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "RESENA"


class Cliente(models.Model):
    cedula = models.IntegerField(primary_key=True)
    nombres = models.CharField(max_length=60)
    apellidos = models.CharField(max_length=100)
    telefono = models.CharField(max_length=30)
    email = models.CharField(max_length=150)

    class Meta:
        managed = False
        db_table = "CLIENTE"
