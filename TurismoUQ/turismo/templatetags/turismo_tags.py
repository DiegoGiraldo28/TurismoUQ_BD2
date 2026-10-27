from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django import template

register = template.Library()


@register.filter
def pesos_colombianos(valor):
    try:
        entero = int(Decimal(valor).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    except (InvalidOperation, TypeError, ValueError):
        entero = 0
    signo = "-" if entero < 0 else ""
    return f"{signo}$ {abs(entero):,}".replace(",", ".")


@register.filter
def obtener_clave(diccionario, clave):
    if hasattr(diccionario, "get"):
        return diccionario.get(clave)
    return None
