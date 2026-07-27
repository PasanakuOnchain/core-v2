import inspect
from dataclasses import dataclass, field


@dataclass(frozen=True)
class ParityCase:
    test: object
    params: dict = field(default_factory=dict)

    @property
    def id(self):
        if not self.params:
            return self.test.__name__
        suffix = "-".join(f"{key}={value}" for key, value in self.params.items())
        return f"{self.test.__name__}[{suffix}]"


def run_parity_case(request, case):
    fixture_names = inspect.signature(case.test).parameters
    arguments = {
        name: request.getfixturevalue(name)
        for name in fixture_names
        if name not in case.params
    }
    arguments.update(case.params)
    case.test(**arguments)
