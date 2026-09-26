#!/bin/sh
# oca-gather installer (POSIX). Downloads a release archive, verifies its
# checksum for integrity/mismatch detection (not independent publisher
# authentication), and installs into an owner-writable directory.
set -eu
# Never enable tracing.

INSTALLER_VERSION=0.1.0-experimental.2
DEFAULT_REPO=houseofpraxis/oca-gather
DEFAULT_BASE=https://github.com/${DEFAULT_REPO}/releases

unset ARGV0 || true
nl='
'

usage() {
	printf '%s\n' "oca-gather installer ${INSTALLER_VERSION}

Usage:
  sh install.sh [--version TAG] [--install-dir DIR] [--download-base URL] [--repo OWNER/NAME]
  sh install.sh --help

Default download uses GitHub /releases/latest/download/, which skips prereleases.
This experimental line is published as a prerelease; pin the binary tag.
Use the main installer so oca-gather-task is installed too:

  curl -fsSL -o install.sh https://raw.githubusercontent.com/${DEFAULT_REPO}/main/install.sh
  sh install.sh --version v0.1.0-experimental.1

A pipe cannot fail the shell when curl fails:
  curl -fsSL https://raw.githubusercontent.com/${DEFAULT_REPO}/main/install.sh | sh
Use the pinned download-and-inspect form above for higher assurance.

Options / environment:
  --version TAG            pin a release tag (OCA_GATHER_VERSION). Default: latest
  --install-dir DIR        absolute install directory (OCA_GATHER_INSTALL_DIR).
                           Default: \$HOME/.local/bin
  --download-base URL      documented fork/test override (OCA_GATHER_DOWNLOAD_BASE).
                           Default: ${DEFAULT_BASE}
  --repo OWNER/NAME        GitHub repo when using the default download base
                           (OCA_GATHER_REPO)
  --help                   print this help (no network)

Checksums from the same release detect download integrity/mismatch. They are
not independent publisher authentication. This script does not call gh.

No sudo. No shell profile edits. Also installs oca-gather-task beside the
binary. Uninstall:
  rm -f DIR/oca-gather DIR/oca-gather-task
An existing regular file named oca-gather or oca-gather-task in DIR is
replaced atomically. The task script is checked against a fixed SHA-256 in
this installer; that detects mismatch, not a publisher signature.
"
}

die() {
	printf '%s\n' "install.sh: $*" >&2
	exit 1
}

die_code() {
	code=$1
	shift
	printf '%s\n' "install.sh: $*" >&2
	exit "$code"
}

version=${OCA_GATHER_VERSION:-}
install_dir=${OCA_GATHER_INSTALL_DIR:-}
download_base=${OCA_GATHER_DOWNLOAD_BASE:-}
repo=${OCA_GATHER_REPO:-}

while [ $# -gt 0 ]; do
	case "$1" in
	--help | -h)
		usage
		exit 0
		;;
	--version)
		[ $# -ge 2 ] || die_code 2 "--version requires a tag"
		version=$2
		shift 2
		;;
	--install-dir)
		[ $# -ge 2 ] || die_code 2 "--install-dir requires a directory"
		install_dir=$2
		shift 2
		;;
	--download-base)
		[ $# -ge 2 ] || die_code 2 "--download-base requires a URL"
		download_base=$2
		shift 2
		;;
	--repo)
		[ $# -ge 2 ] || die_code 2 "--repo requires OWNER/NAME"
		repo=$2
		shift 2
		;;
	*)
		die_code 2 "unknown argument: $1"
		;;
	esac
done

os_raw=$(uname -s)
arch_raw=$(uname -m)
case "$os_raw" in
Linux) os=linux ;;
Darwin) os=darwin ;;
*) die_code 2 "unsupported os: $os_raw" ;;
esac
case "$arch_raw" in
x86_64 | amd64) arch=amd64 ;;
arm64 | aarch64) arch=arm64 ;;
*) die_code 2 "unsupported arch: $arch_raw" ;;
esac

if [ -z "$download_base" ]; then
	download_base=$DEFAULT_BASE
	if [ -n "$repo" ]; then
		case "$repo" in
		*/*)
			owner=${repo%/*}
			name=${repo#*/}
			case "$owner" in
			"" | */*) die_code 2 "invalid --repo: $repo" ;;
			esac
			case "$name" in
			"" | */*) die_code 2 "invalid --repo: $repo" ;;
			esac
			download_base="https://github.com/${repo}/releases"
			;;
		*)
			die_code 2 "invalid --repo: $repo"
			;;
		esac
	fi
else
	if [ -n "$repo" ] && [ "$download_base" != "$DEFAULT_BASE" ]; then
		die_code 2 "--repo is only valid with the default download base"
	fi
	if [ -n "$repo" ] && [ "$download_base" = "$DEFAULT_BASE" ]; then
		download_base="https://github.com/${repo}/releases"
	fi
fi

case "$download_base" in
*/) download_base=${download_base%/} ;;
esac

asset="oca-gather_${os}_${arch}.tar.gz"
if [ -z "$version" ] || [ "$version" = "latest" ]; then
	archive_url="${download_base}/latest/download/${asset}"
	sums_url="${download_base}/latest/download/checksums.txt"
else
	case "$version" in
	*/* | *"$nl"*) die_code 2 "invalid --version" ;;
	esac
	archive_url="${download_base}/download/${version}/${asset}"
	sums_url="${download_base}/download/${version}/checksums.txt"
fi

if [ -z "${HOME:-}" ]; then
	die "HOME is empty"
fi
if [ -z "$install_dir" ]; then
	install_dir="${HOME}/.local/bin"
fi

case "$install_dir" in
*"$nl"*) die_code 2 "install dir must not contain a newline" ;;
esac
case "$install_dir" in
/*) ;;
*) die_code 2 "install dir must be absolute" ;;
esac
rest=$install_dir
while [ -n "$rest" ]; do
	rest=${rest#/}
	comp=${rest%%/*}
	if [ "$comp" = ".." ] || [ "$comp" = "." ]; then
		die_code 2 "install dir must not contain . or .. components"
	fi
	case "$rest" in
	*/*) rest=${rest#*/} ;;
	*) rest= ;;
	esac
done

command -v curl >/dev/null 2>&1 || die "need curl"
hash_cmd=
if command -v sha256sum >/dev/null 2>&1; then
	hash_cmd=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	hash_cmd=shasum
else
	die "need sha256sum or shasum -a 256"
fi
command -v tar >/dev/null 2>&1 || die "need tar"
command -v mktemp >/dev/null 2>&1 || die "need mktemp"

work=$(mktemp -d)
cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT HUP

fetch() {
	url=$1
	dest=$2
	what=$3
	if ! curl -fsSL -o "$dest" "$url"; then
		# Never print the URL: --download-base may contain userinfo.
		printf '%s\n' "install.sh: download failed ($what)" >&2
		if [ -z "$version" ] || [ "$version" = "latest" ]; then
			printf '%s\n' "install.sh: prerelease tags need --version TAG (GitHub latest skips prereleases)" >&2
		fi
		exit 1
	fi
}

fetch "$sums_url" "$work/checksums.txt" checksums.txt
fetch "$archive_url" "$work/$asset" "$asset"

printf '%s\n' "checksums detect download integrity/mismatch, not independent publisher authentication"

want_hash=
while IFS= read -r line || [ -n "$line" ]; do
	[ -n "$line" ] || continue
	case "$line" in
	\#*) continue ;;
	esac
	hash=${line%% *}
	rest=${line#"$hash"}
	while [ "${rest# }" != "$rest" ]; do
		rest=${rest# }
	done
	case "$rest" in
	\**) rest=${rest#?} ;;
	esac
	while [ "${rest# }" != "$rest" ]; do
		rest=${rest# }
	done
	if [ "$rest" = "$asset" ]; then
		want_hash=$hash
		break
	fi
done <"$work/checksums.txt"

[ -n "$want_hash" ] || die "no checksum line for $asset"
case "$want_hash" in
*[!0-9a-f]*) die "checksum for $asset is not lowercase hex" ;;
esac
if [ "${#want_hash}" -ne 64 ]; then
	die "checksum for $asset is not 64 hex characters"
fi

(
	cd "$work"
	if [ "$hash_cmd" = sha256sum ]; then
		printf '%s  %s\n' "$want_hash" "$asset" | sha256sum -c -
	else
		printf '%s  %s\n' "$want_hash" "$asset" | shasum -a 256 -c -
	fi
)

tar -tzf "$work/$asset" >"$work/members" || die "cannot list archive"
[ -s "$work/members" ] || die "empty archive"
while IFS= read -r n || [ -n "$n" ]; do
	[ -n "$n" ] || die "empty archive member name"
	case "$n" in
	. | .. | */ | *..* | //* | /* | *'*'* | *'?'* | *"$nl"*)
		die "refusing archive member: $n"
		;;
	esac
	case "$n" in
	oca-gather | LICENSE | NOTICE) ;;
	*) die "unexpected archive member: $n" ;;
	esac
done <"$work/members"

got=$(LC_ALL=C sort "$work/members")
want=$(printf '%s\n' LICENSE NOTICE oca-gather)
[ "$got" = "$want" ] || die "archive members must be exactly oca-gather, LICENSE, NOTICE"

tar -tvzf "$work/$asset" >"$work/listing" || die "cannot verbose-list archive"
while IFS= read -r listing || [ -n "$listing" ]; do
	[ -n "$listing" ] || continue
	first=${listing%"${listing#?}"}
	[ "$first" = "-" ] || die "archive member is not a regular file"
done <"$work/listing"

extract=$work/extract
mkdir -m 0755 "$extract"
tar -xf "$work/$asset" -C "$extract"
for n in oca-gather LICENSE NOTICE; do
	p=$extract/$n
	[ -f "$p" ] || die "missing extracted $n"
	[ ! -L "$p" ] || die "extracted $n is a symlink"
done
[ -x "$extract/oca-gather" ] || die "extracted oca-gather is not executable"
extra=0
for p in "$extract"/*; do
	base=${p##*/}
	case "$base" in
	oca-gather | LICENSE | NOTICE) ;;
	*) extra=1 ;;
	esac
done
[ "$extra" -eq 0 ] || die "archive extracted extra files"

ver_out=$("$extract/oca-gather" --version) || die "oca-gather --version failed"
case "$ver_out" in
*collector_version*) ;;
*) die "oca-gather --version did not print collector_version" ;;
esac

mkdir -p "$install_dir" || die "cannot create install dir $install_dir (no sudo)"
chmod 0755 "$install_dir" || die "cannot chmod install dir $install_dir (no sudo)"

dest=$install_dir/oca-gather
if [ -L "$dest" ]; then
	die "refusing to replace symlink $dest"
fi
if [ -d "$dest" ]; then
	die "refusing to replace directory $dest"
fi
if [ -e "$dest" ] && [ ! -f "$dest" ]; then
	die "refusing to replace non-regular $dest"
fi

tmp=$install_dir/.oca-gather.tmp.$$
if ! cp "$extract/oca-gather" "$tmp"; then
	rm -f "$tmp"
	die "cannot write $tmp (no sudo)"
fi
if ! chmod 0755 "$tmp"; then
	rm -f "$tmp"
	die "cannot chmod $tmp"
fi
if ! mv -f "$tmp" "$dest"; then
	rm -f "$tmp"
	printf '%s\n' "install.sh: atomic replace failed; previous binary left in place" >&2
	exit 1
fi

task_repo=${repo:-$DEFAULT_REPO}
task_url=${OCA_GATHER_TASK_URL:-https://raw.githubusercontent.com/${task_repo}/main/oca-gather-task}
if ! curl -fsSL -o "$work/oca-gather-task" "$task_url"; then
	printf '%s\n' "install.sh: download failed (oca-gather-task)" >&2
	exit 1
fi
task_hash=ccb89309b5b127b8b1dd94bb5080dc76236d77044abc919517447e8d772a6989
if [ "$hash_cmd" = sha256sum ]; then
	got_task=$(sha256sum "$work/oca-gather-task" | awk '{print $1}')
else
	got_task=$(shasum -a 256 "$work/oca-gather-task" | awk '{print $1}')
fi
[ "$got_task" = "$task_hash" ] || die "oca-gather-task checksum mismatch"
[ -f "$work/oca-gather-task" ] || die "missing oca-gather-task"
[ ! -L "$work/oca-gather-task" ] || die "oca-gather-task is a symlink"
task_dest=$install_dir/oca-gather-task
if [ -L "$task_dest" ]; then
	die "refusing to replace symlink $task_dest"
fi
if [ -d "$task_dest" ] || { [ -e "$task_dest" ] && [ ! -f "$task_dest" ]; }; then
	die "refusing to replace non-regular $task_dest"
fi
task_tmp=$install_dir/.oca-gather-task.tmp.$$
if ! cp "$work/oca-gather-task" "$task_tmp"; then
	rm -f "$task_tmp"
	die "cannot write $task_tmp (no sudo)"
fi
if ! chmod 0755 "$task_tmp"; then
	rm -f "$task_tmp"
	die "cannot chmod $task_tmp"
fi
if ! mv -f "$task_tmp" "$task_dest"; then
	rm -f "$task_tmp"
	printf '%s\n' "install.sh: atomic replace failed; previous task script left in place" >&2
	exit 1
fi

printf '%s\n' "installed $dest"
printf '%s\n' "installed $task_dest"
case ":${PATH-}:" in
*":${install_dir}:"*) ;;
*)
	printf '%s\n' "note: $install_dir is not in PATH"
	;;
esac
printf '%s\n' "uninstall: rm -f $dest $task_dest"
