"""Shared runtime configuration loaded from the repo-root Config.toml."""

from __future__ import annotations

import os
import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "Config.toml"

ENV_TO_TOML = {
    "AGENT_SERVER_PORT": "agentServerPort",
    "CODE_SERVER_PORT": "codeServerPort",
    "DOCS_INTEGRATOR_BASE_BRANCH": "docsIntegratorBaseBranch",
    "DOCS_INTEGRATOR_FORK": "docsIntegratorFork",
    "DOCS_INTEGRATOR_REPO": "docsIntegratorRepo",
    "DOCS_INTEGRATOR_UPSTREAM": "docsIntegratorUpstream",
    "INTEGRATION_SAMPLES_BASE_BRANCH": "integrationSamplesBaseBranch",
    "INTEGRATION_SAMPLES_REPO": "integrationSamplesRepo",
    "INTEGRATION_SAMPLES_UPSTREAM": "integrationSamplesUpstream",
}

TOML_ENV_ALIASES: dict[str, tuple[str, ...]] = {}
for env_key, toml_key in ENV_TO_TOML.items():
    TOML_ENV_ALIASES[toml_key] = (*TOML_ENV_ALIASES.get(toml_key, ()), env_key)


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        return {}
    return tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))


CONFIG = load_config()


def get_str(key: str, default: str = "") -> str:
    for env_key in TOML_ENV_ALIASES.get(key, ()):
        if os.environ.get(env_key):
            return os.environ[env_key]
    value = CONFIG.get(key)
    return default if value is None else str(value)


def get_int(key: str, default: int) -> int:
    raw = get_str(key, "")
    if raw == "":
        return default
    return int(raw)


def get_path(key: str, default: Path) -> Path:
    raw = get_str(key, "")
    return Path(raw).expanduser() if raw else default
