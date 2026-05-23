"""Hermes Cursor ACP Provider Plugin.

This package registers the Cursor ACP provider profile with Hermes Agent.

Usage:
    pip install hermes-cursor-provider

Then use in Hermes:
    hermes model
    # -> Select "Cursor ACP"

Note: This plugin provides the declarative provider profile only.
The ACP client shim must be merged into Hermes core via PR.
See: https://github.com/RobertoVillegas/hermes-cursor-provider
"""

from pathlib import Path


def register() -> None:
    """Register the Cursor ACP provider profile with Hermes.

    This entry point is called by the Hermes PluginManager when the package
    is installed and Hermes discovers entry-point plugins.
    """
    try:
        from providers import register_provider
        from providers.base import ProviderProfile

        cursor_acp = ProviderProfile(
            name="cursor-acp",
            aliases=("cursor", "cursor-agent"),
            api_mode="chat_completions",
            env_vars=(),
            base_url="acp://cursor",
            auth_type="external_process",
            display_name="Cursor ACP",
            description="Cursor Agent via Agent Client Protocol (ACP) subprocess",
            signup_url="https://cursor.com",
        )

        register_provider(cursor_acp)
    except ImportError:
        # If providers module is not available (Hermes not installed),
        # silently skip. The plugin will still work when dropped into
        # ~/.hermes/plugins/model-providers/ directly.
        pass


# Auto-register when imported (for drop-in plugin usage)
register()
