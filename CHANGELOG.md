# Changelog

## 1.0.50
- Update checks now use the renamed GitHub repository (`lumenworksco/-Tokn`) directly instead of relying on a redirect.
- Repository polish: screenshot, security policy, issue templates, CI.

## 1.0.49
- Weekly limit reached: the menu bar shows "☠ GAME OVER" until the window resets (dropdown unchanged).
- Updates now require a click by default; new Settings → Updates section with "Install updates automatically" and "check for updates".
- Updater hardening: SHA-256 check against GitHub's asset digest, bundle ID and code-signature check, atomic app swap, private temp directory, chunked download.
- A banner appears when a refresh fails and older numbers are still shown.
- Added unit tests; removed the obsolete icon generator script.
