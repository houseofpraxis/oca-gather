# Open-Chat-Archive format Gatherer

`oca-gather` is an experimental, fail-closed snapshot tool for local AI coding-agent
session logs. It discovers supported JSONL files, waits for stable complete bytes,
and copies those bytes into an immutable, content-addressed store for later review
or import.

For security engineers, the useful mental model is:

```text
bounded local discovery
        ↓
conservative format recognition
        ↓
exact-byte SHA-256 objects + per-origin receipts
        ↓
independent store verification with `status`
```

It is designed to preserve evidence without executing the source client, repairing
logs, following links, uploading content, or claiming that collection is a
successful semantic import.

> **Experimental:** this is not a forensic certification, an EDR sensor, an
> encryption product, or an authentication boundary. Review the trust model and
> non-goals below before using it for sensitive material.

## Why this may be useful

AI coding tools increasingly leave operationally relevant records in separate,
tool-specific local directories. Those records may matter during incident
response, internal investigations, provenance review, retention, or migration,
but handling them casually can destroy useful byte-level evidence or expose
credentials and private conversations.

`oca-gather` provides a narrow acquisition layer:

- inventories known local roots without crawling the whole home directory;
- recognizes Claude Code, Codex, Grok Build, and Pi session JSONL;
- snapshots the exact source bytes without trimming or repairing them;
- deduplicates identical bytes while retaining distinct origin receipts;
- refuses symlink, hardlink, device, FIFO, socket, changing, and unsafe inputs;
- emits privacy-safe aggregate JSON by default; and
- verifies stored objects and receipts later without reopening source paths.

## What it does not do

`oca-gather` does **not**:

- parse and validate the complete source format;
- normalize chats into the Open Chat Archive canonical schema;
- prove which person or account owns a session;
- infer equivalence between sessions, paths, accounts, or tools;
- decrypt, redact, classify, or sanitize collected content;
- search, index, render, or upload conversations;
- run a daemon, watcher, client, Python interpreter, or network request; or
- delete or modify source files.

Recognition means only that a bounded probe uniquely matched a supported
signature. Every receipt records `import_status: not_attempted`. Pi is
collectable, but this release has no Python importer for Pi.

## Supported platforms and sources

Release binaries are provided for:

- Linux amd64 and arm64
- macOS amd64 and arm64

Automatic discovery is limited to known roots:

| Adapter | Default location | Notes |
| --- | --- | --- |
| Claude Code | `~/.claude/projects` | Recursive `.jsonl`; does not descend `subagents` automatically |
| Codex | `~/.codex/sessions` and `~/.codex/archived_sessions` | Recursive `.jsonl` |
| Grok Build | `~/.grok/sessions/**/updates.jsonl` | `chat_history.jsonl` is not supported |
| Pi | `~/.pi/agent/sessions` | Pi header versions 1–3 |

Documented client environment overrides are honored. `--home` provides an
isolated home root and ignores ambient Claude, Codex, and Pi overrides.
Explicit `--path` inputs must be absolute.

## Install

GitHub `/releases/latest/download/` skips prereleases. Pin this experimental
release:

```sh
curl -fsSL -o install.sh \
  https://raw.githubusercontent.com/houseofpraxis/oca-gather/v0.1.0-experimental.1/install.sh
sh install.sh --version v0.1.0-experimental.1
```

The installer:

- selects Linux/macOS and amd64/arm64;
- downloads into a temporary directory;
- verifies the archive against `checksums.txt`;
- validates the flat archive member allowlist;
- refuses a symlink or non-regular destination;
- atomically replaces an existing regular binary; and
- never uses `sudo` or edits shell profiles.

Default installation is `$HOME/.local/bin/oca-gather`. If it is not in `PATH`:

```sh
$HOME/.local/bin/oca-gather --version
export PATH="$HOME/.local/bin:$PATH"
```

Checksums shipped with the same release detect download corruption or mismatch.
They are **not** an independent publisher signature or reproducible-build
attestation. This is a binary distribution repository; source development is
currently private. The reviewed source commit for this release is recorded in
[PROVENANCE.md](PROVENANCE.md).

## Review what you collected

After `collect`, a separate localhost binary serves the store without
importing it:

```sh
oca-inspect serve --store "$STORE"
```

Download `oca-inspect` from
[houseofpraxis/open-chat-archive](https://github.com/houseofpraxis/open-chat-archive/releases/tag/inspect-v0.1.0-experimental.2).
It binds to `127.0.0.1` only. The page contains session text; do not publish
it. This collector binary remains offline and does not serve traffic.

## Five-minute quick start

### 1. Confirm capabilities

```sh
oca-gather --version
oca-gather adapters
```

`adapters` reports collector availability separately from Python importer
availability.

### 2. Scan without writing

```sh
oca-gather scan
```

This scans only the known roots above and emits one JSON result. It does not
create a store.

### 3. Preview collection

Choose a store whose parent directory already exists:

```sh
STORE="$HOME/oca-gather-store"
oca-gather collect --store "$STORE" --dry-run
```

Dry-run performs recognition and stability checks but creates no directory,
lock, object, or receipt.

### 4. Collect

```sh
oca-gather collect --store "$STORE"
```

A repeat collection of the same adapter, origin, optional scope, and bytes is
reported as unchanged rather than rewritten.

### 5. Verify the store

```sh
oca-gather status --store "$STORE"
```

`status` verifies store structure, canonical receipt bytes, object hashes,
ownership, modes, links, sizes, and bounded inventory. It does not reopen the
original session paths.

## Explicit acquisition

Use an absolute file or directory when automatic discovery is not appropriate:

```sh
oca-gather scan \
  --adapter codex \
  --path /absolute/path/to/session.jsonl

oca-gather collect \
  --adapter codex \
  --path /absolute/path/to/session.jsonl \
  --store "$STORE"
```

Use `--adapter auto` to classify among all supported signatures. Supplying the
wrong named adapter fails with `EXPLICIT_PATH_MISMATCH` rather than silently
relabeling the source.

To test a staged home layout without ambient overrides:

```sh
oca-gather scan --home /absolute/path/to/isolated-home
```

## Store model

```text
STORE/                         owner-only directory (0700)
  .oca-gather-store            format marker (0600)
  objects/sha256/<digest>      exact source bytes (0600)
  receipts/<receipt-id>.json   immutable origin/scope metadata (0600)
  tmp/                         bounded temporary publication area (0700)
```

Object names are SHA-256 digests of exact bytes. Byte-identical sources may
share an object, but each distinct origin and optional source scope retains its
own receipt. A digest does not establish chat, account, or user equivalence.

The store is sensitive plaintext. Owner-only permissions reduce accidental
local disclosure but provide neither encryption nor authentication. Apply your
normal endpoint, backup, retention, legal-hold, and access-control requirements
to the entire store.

## Security properties

### Bounded and offline

The collector runtime has no network or client-execution path. Discovery uses
known roots and explicit quotas for files, entries, depth, probe bytes, probe
lines, per-file bytes, and total bytes. A bound produces a partial result rather
than silently claiming complete coverage.

### Descriptor-relative traversal

Production source and store operations are descriptor-relative and fail closed:

- Linux requires `openat2` with beneath/no-symlink/no-magic-link resolution and
  `renameat2(RENAME_NOREPLACE)`.
- macOS walks validated components with `openat(..., O_NOFOLLOW)` and publishes
  with `renameatx_np(RENAME_EXCL)`.

There is no unsafe pathname-I/O fallback. On macOS, `/tmp`, `/var`, and `/etc`
are symlink prefixes; use their `/private/...` forms for explicit paths.

### Stable regular files only

Sources must be regular files with one hard link, stable identity/metadata, and
complete LF-terminated JSONL. Files that change during collection are deferred.
The collector never trims an incomplete tail or repairs a live log.

### Immutable publication

Objects and receipts are written to owner-only temporary files, synced, and
published with atomic no-replace operations. Concurrent access uses descriptor
locks. Existing data is verified before mutation; conflicting bytes fail as
store corruption rather than being overwritten.

On Darwin, files receive `fsync` plus `F_FULLFSYNC`. Some Darwin filesystems do
not support Linux-style directory `fsync`; that limitation is reported honestly
in the collector help and durability behavior.

### Privacy-safe output by default

Default stdout/stderr omits source text, paths, native IDs, digests, and raw OS
errors. `--details` is an explicit privacy opt-in and may reveal origin paths and
SHA-256 digests. Use it only in a trusted terminal or protected log sink.

## Reading results and exit codes

All command output is JSON except `--help`. Important exit codes:

| Exit | Meaning |
| ---: | --- |
| `0` | Complete within configured bounds |
| `2` | Invalid argument |
| `3` | Explicit path matched a different adapter |
| `4` | Store is untrusted or corrupt |
| `5` | Unsupported platform |
| `6` | Store is busy |
| `7` | Complete explicit named request found no match |
| `8` | Partial, deferred, limit-reached, overlap, incomplete JSONL, or durability-unconfirmed result |

Exit `8` is intentionally not success. Review aggregate counts before deciding
whether to retry with different limits or inspect `--details` in a protected
environment. Already published verified objects are not rolled back merely
because later durability confirmation was uncertain.

Run the built-in reference for every flag and hard limit:

```sh
oca-gather --help
```

## Operational guidance

- Place the store outside selected source directories. Sibling paths are valid;
  containment or equality is rejected.
- Do not send `--details` output, receipts, objects, or collection stores to an
  issue tracker.
- Treat unexpected `STORE_UNTRUSTED` or `STORE_OBJECT_CORRUPT` as an integrity
  event; preserve the store before investigation.
- Keep the source application stopped or quiescent when you need the most
  complete point-in-time capture.
- Record the collector version, command, exit code, aggregate counts, host time,
  and your external case/change identifier outside the store when acquisition
  documentation is required.
- Collection is only the acquisition step. Semantic import and archive
  validation are separate operations and are not included in this repository.

## Uninstall

```sh
rm -f "$HOME/.local/bin/oca-gather"
```

Uninstalling the executable does not remove collection stores. Delete a store
only after independently confirming its path, retention status, and backups.

## Release contents and provenance

This public repository contains installer and usage documentation, licensing,
provenance, and platform release archives. It does not contain chat data,
session files, private source history, test fixtures, or CI workflow files.

The release contains exactly:

- `oca-gather_linux_amd64.tar.gz`
- `oca-gather_linux_arm64.tar.gz`
- `oca-gather_darwin_amd64.tar.gz`
- `oca-gather_darwin_arm64.tar.gz`
- `checksums.txt`

Each archive contains only `oca-gather`, `LICENSE`, and `NOTICE`.

## Reporting security issues

Use this repository’s GitHub issue tracker for non-sensitive defects and fixed
error codes. Do **not** attach real exports, transcripts, paths, account data,
receipts, objects, stores, credentials, or `--details` output. If reproduction
requires sensitive material, first request a private disclosure channel using a
sanitized description.
