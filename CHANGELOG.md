# Changelog

## 1.0.51
- Multiple Claude accounts: add, rename, re-key and remove accounts in Settings → Accounts. The popover lists every account's 5h/7d usage; the selected one drives the menu bar. History and notifications are tracked per account. An existing session key is migrated to the first account automatically.

## 1.0.50
- Update checks now use the renamed GitHub repository (`lumenworksco/-Tokn`) directly instead of relying on a redirect.
- Repository polish: screenshot, security policy, issue templates, CI.

## 1.0.49
- Weekly limit reached: the menu bar shows "☠ GAME OVER" until the window resets (dropdown unchanged).
- Updates now require a click by default; new Settings → Updates section with "Install updates automatically" and "check for updates".
- Updater hardening: SHA-256 check against GitHub's asset digest, bundle ID and code-signature check, atomic app swap, private temp directory, chunked download.
- A banner appears when a refresh fails and older numbers are still shown.
- Added unit tests; removed the obsolete icon generator script.
