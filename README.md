# Open-Chat-Archive format Gatherer

Experimental local session collector for Linux amd64/arm64 and macOS amd64/arm64.
It discovers supported local JSONL session files and snapshots their exact bytes
into an owner-only store. It does **not** import or normalize chats, upload data,
run a daemon, or modify the source files.

## Install

GitHub `/releases/latest/download/` skips prereleases. This experimental line
is a prerelease; pin the tag:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/houseofpraxis/oca-gather/v0.1.0-experimental.1/install.sh
sh install.sh --version v0.1.0-experimental.1
```

Default install directory is `$HOME/.local/bin`. The installer does not use
sudo and does not edit shell profiles.

If `oca-gather` is not found after installation, invoke it by its full path or
add the directory to `PATH` for the current shell:

```sh
$HOME/.local/bin/oca-gather --version
export PATH="$HOME/.local/bin:$PATH"
```

## Quick start

List supported adapters and importer availability:

```sh
oca-gather adapters
```

Scan the standard local directories without writing anything:

```sh
oca-gather scan
```

Preview collection without creating a store:

```sh
STORE="$HOME/oca-gather-store"
oca-gather collect --store "$STORE" --dry-run
```

Collect exact source bytes and write immutable receipts:

```sh
oca-gather collect --store "$STORE"
```

Verify every receipt and stored object later:

```sh
oca-gather status --store "$STORE"
```

The commands print JSON. A normal complete operation exits `0`. Exit `8` means
some candidates were deferred, a safety limit was reached, or coverage was
partial; already verified results are retained. Run `oca-gather --help` for
all limits and exit codes.

## What automatic scan checks

Without `--path`, `scan` and `collect` look only in these known roots:

| Adapter | Default location |
| --- | --- |
| Claude Code | `~/.claude/projects` |
| Codex | `~/.codex/sessions` and `~/.codex/archived_sessions` |
| Grok Build | `~/.grok/sessions/**/updates.jsonl` |
| Pi | `~/.pi/agent/sessions` |

Documented client environment overrides are honored. Automatic discovery does
not crawl the whole home directory, inspect credentials, or execute a client.
Grok Build `chat_history.jsonl` is not a supported source.

## Scan or collect a specific path

`--path` must be an absolute file or directory and may be repeated. Use a named
adapter when you know the format:

```sh
oca-gather scan --adapter codex --path /absolute/path/to/session.jsonl
oca-gather collect --adapter codex \
  --path /absolute/path/to/session.jsonl \
  --store "$STORE"
```

Use `--adapter auto` to classify among all supported signatures. A mismatched
named adapter fails rather than silently relabeling the source.

For testing an isolated home layout without ambient client overrides:

```sh
oca-gather scan --home /absolute/path/to/isolated-home
```

## Privacy and safety

- The collection store contains sensitive **plaintext exact session bytes**. It
  is owner-only (`0700` directories and `0600` files), but it is not encrypted.
- Default output omits paths, digests, native IDs, and source text.
- `--details` is an explicit privacy opt-in that may print origin paths and
  SHA-256 digests. Use it only in a trusted terminal or log destination.
- The collector performs no network requests. Only the installer downloads
  release files.
- Collection is not canonical import. Receipts remain `not_attempted`; Pi is
  collectable but has no Python importer in this release.
- Inputs reached through symlinks, hardlinks, devices, FIFOs, or changing files
  are rejected or deferred rather than followed or repaired.

On macOS, fail-closed traversal does not follow the `/tmp`, `/var`, or `/etc`
symlink prefixes. Use their `/private/...` forms for explicit paths when needed.

## Command summary

```text
oca-gather adapters
oca-gather scan [options]
oca-gather collect [options] --store /absolute/store [--dry-run]
oca-gather status --store /absolute/store
oca-gather --help
oca-gather --version
```

## Uninstall

```sh
rm -f "$HOME/.local/bin/oca-gather"
```

Uninstalling the binary does not delete any collection store you created.
Remove a store only after reviewing its path and deciding its snapshots are no
longer needed.

## Release integrity and contents

Checksums from the same GitHub release detect download integrity or mismatch.
They are not independent publisher authentication.

This public distribution contains the installer, four platform archives,
LICENSE, NOTICE, README, and provenance documentation. It does not include chat
data, session files, source trees, tests, or workflow files. See
[PROVENANCE.md](PROVENANCE.md) for the verified source commit.

## Support

Open issues on this repository. Do not attach real chat exports, transcripts,
paths, account data, or collection stores. Include only the fixed error code and
aggregate counts unless more detail is explicitly requested.
