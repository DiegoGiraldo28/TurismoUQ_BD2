class TurismoRouter:
    """Dirige la app de negocio a Oracle y prohíbe migraciones allí."""

    app_label = "turismo"

    def db_for_read(self, model, **hints):
        if model._meta.app_label == self.app_label:
            return "turismo"
        return None

    def db_for_write(self, model, **hints):
        if model._meta.app_label == self.app_label:
            return "turismo"
        return None

    def allow_relation(self, obj1, obj2, **hints):
        if self.app_label in {obj1._meta.app_label, obj2._meta.app_label}:
            return obj1._state.db == obj2._state.db == "turismo"
        return None

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        if db == "turismo":
            return False
        if app_label == self.app_label:
            return False
        return None
