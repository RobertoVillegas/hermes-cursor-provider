"""Cursor ACP provider profile.

cursor-acp uses an external ACP subprocess — NOT the standard
transport. The profile captures auth + endpoint metadata for registry migration.
"""

from providers import register_provider
from providers.base import ProviderProfile


class CursorACPProfile(ProviderProfile):
    """Cursor ACP — external process, no REST models endpoint."""

    def fetch_models(
        self,
        *,
        api_key: str | None = None,
        timeout: float = 8.0,
    ) -> list[str] | None:
        """Model listing is handled by the ACP subprocess."""
        return None


cursor_acp = CursorACPProfile(
    name="cursor-acp",
    aliases=("cursor", "cursor-agent"),
    api_mode="chat_completions",  # ACP subprocess uses chat_completions routing
    env_vars=(),  # Managed by ACP subprocess
    base_url="acp://cursor",  # ACP internal scheme
    auth_type="external_process",
    display_name="Cursor ACP",
    description="Cursor Agent via Agent Client Protocol (ACP) subprocess",
    signup_url="https://cursor.com",
)

register_provider(cursor_acp)
