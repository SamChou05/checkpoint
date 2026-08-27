"""Stable exception types shared across backend modules."""


class BadRequestError(ValueError):
    pass


class ProviderError(RuntimeError):
    pass


class RateLimitExceededError(RuntimeError):
    pass


class ServiceConfigurationError(RuntimeError):
    pass


class ProviderCallBudgetExceededError(ProviderError):
    pass


class SafetyInterventionError(RuntimeError):
    pass
