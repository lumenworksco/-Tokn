# Security Policy

## Supported versions

Only the latest release receives fixes. Please update before reporting.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
[private vulnerability reporting](https://github.com/lumenworksco/-Tokn/security/advisories/new)
instead. You can expect a reply within a few days.

## Scope

Tokn stores your claude.ai `sessionKey` in the macOS Keychain and only sends it to `claude.ai`.
Reports about key handling, the auto-updater (SHA-256 / code-signature verification), or anything
that could leak the key are especially welcome.
