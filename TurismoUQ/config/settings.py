"""Configuración Django para TurismoUQ.

SQLite guarda únicamente las tablas internas de Django. El esquema existente
de TurismoUQ se consulta en Oracle y no recibe migraciones de la aplicación.
"""
import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-insegura-cambiar-antes-de-publicar")
DEBUG = os.getenv("DJANGO_DEBUG", "true").lower() in {"1", "true", "yes", "si"}
ALLOWED_HOSTS = [host.strip() for host in os.getenv("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if host.strip()]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "turismo",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [BASE_DIR / "templates"],
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
        "django.contrib.messages.context_processors.messages",
    ]},
}]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    },
    "turismo": {
        "ENGINE": "django.db.backends.oracle",
        "NAME": os.getenv("ORACLE_NAME", "localhost:1521/XEPDB1"),
        "USER": os.getenv("ORACLE_USER", "turismouq"),
        "PASSWORD": os.getenv("ORACLE_PASSWORD", ""),
        "HOST": os.getenv("ORACLE_HOST", ""),
        "PORT": os.getenv("ORACLE_PORT", ""),
        "CONN_MAX_AGE": 0,
    },
}
DATABASE_ROUTERS = ["turismo.db_router.TurismoRouter"]

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "es-co"
TIME_ZONE = "America/Bogota"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATICFILES_DIRS = [BASE_DIR / "static"]
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
LOGIN_URL = "login"
LOGIN_REDIRECT_URL = "tablero"
LOGOUT_REDIRECT_URL = "login"
MESSAGE_TAGS = {40: "danger"}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "turismo_console": {
            "format": "{asctime} {levelname} {name}: {message}",
            "style": "{",
        },
    },
    "handlers": {
        "turismo_console": {
            "class": "logging.StreamHandler",
            "formatter": "turismo_console",
        },
    },
    "loggers": {
        "turismo": {
            "handlers": ["turismo_console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}
