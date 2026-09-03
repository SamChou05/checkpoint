"""Stable exception types shared across backend modules."""


class BadRequestError(ValueError):
    pass


class ProviderError(RuntimeError):
    pass


class InvalidProviderResponseError(ProviderError):
    """The provider answered, but every bounded validation attempt was unusable."""


class RateLimitExceededError(RuntimeError):
    pass


class ServiceConfigurationError(RuntimeError):
    pass


class ProviderCallBudgetExceededError(ProviderError):
    pass


class DurableProviderCallBudgetExceededError(ProviderCallBudgetExceededError):
    """A durable asynchronous provider-call reservation was refused."""


class ProviderAttemptLimitError(DurableProviderCallBudgetExceededError):
    """The logical question-bank job exhausted its provider-call allowance."""


class ProviderQuotaLimitError(DurableProviderCallBudgetExceededError):
    """The asynchronous install exhausted its daily provider-call quota."""


class SafetyInterventionError(RuntimeError):
    pass
