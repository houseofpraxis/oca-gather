# oca-gather

Experimental local session collector for Linux amd64/arm64 and macOS amd64/arm64.

## Install

GitHub `/releases/latest/download/` skips prereleases. This experimental line
is a prerelease; pin the tag:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/houseofpraxis/oca-gather/v0.1.0-experimental.1/install.sh
sh install.sh --version v0.1.0-experimental.1
```

Default install directory is `$HOME/.local/bin`. The installer does not use
sudo and does not edit shell profiles. Uninstall:

```sh
rm -f "$HOME/.local/bin/oca-gather"
```

Checksums from the same GitHub release detect download integrity or mismatch.
They are not independent publisher authentication.

This public distribution contains the installer, four platform archives,
LICENSE, and NOTICE only. It does not include chat data, session files,
source trees, tests, or workflow files. See PROVENANCE.md for the verified
source commit.

## Support

Open issues on this repository. Do not attach real chat exports, transcripts,
or account data.
