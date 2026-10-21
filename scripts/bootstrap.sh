#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly CONFIG_DIR="${HOME}/.config/nix"
readonly ENV_FILE="${CONFIG_DIR}/termux-env.bash"
readonly NIX_CONF="${CONFIG_DIR}/nix.conf"
readonly STARTUP_BEGIN="# >>> yuko-nix-env >>>"
readonly STARTUP_END="# <<< yuko-nix-env <<<"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
CHROOT_BIN="${PREFIX}/bin/termux-chroot"

HOST_NIX_DIR=""
BACKUP_DIR="${HOME}/.local/state/yuko-nix-bootstrap"
CHROOT_BACKUP="${BACKUP_DIR}/termux-chroot.original"
TEMP_FILES=()

log() {
    printf '\n==> [%s] %s\n' "$(date +%T)" "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup_temp() {
    local file
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

on_error() {
    local exit_code=$?
    printf '\nERROR: Command failed at line %s (exit %s).\n' \
        "${BASH_LINENO[0]:-unknown}" "$exit_code" >&2
    cleanup_temp
    printf 'Inspect the preceding output before retrying.\n' >&2
    exit "$exit_code"
}

trap on_error ERR
trap cleanup_temp EXIT

require_termux() {
    [[ -d /data/data/com.termux ]] || die "This script must run inside Termux."
    [[ -n "${PREFIX:-}" && -d "$PREFIX" ]] || die "Termux PREFIX is invalid: ${PREFIX:-unset}"
    command -v pkg >/dev/null 2>&1 || die "Termux package manager is unavailable."
}

install_dependencies() {
    log "[1/5] Detecting and installing host dependencies"
    local pkgs=(proot curl tar xz-utils ca-certificates)
    local missing=()

    for pkg_item in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg_item" &>/dev/null; then
            missing+=("$pkg_item")
        fi
    done

    pkg update -y || warn "pkg update encountered issues, proceeding..."
    if (( ${#missing[@]} > 0 )); then
        pkg install -y "${missing[@]}" || die "Failed to install required packages: ${missing[*]}"
    else
        log "All host dependencies are satisfied."
    fi
}

choose_nix_directory() {
    log "[2/5] Preparing Nix bind-mount source directory"
    if mkdir -p /nix 2>/dev/null && [[ -d /nix && -w /nix ]]; then
        HOST_NIX_DIR="/nix"
    else
        HOST_NIX_DIR="${PREFIX}/nix"
        mkdir -p "$HOST_NIX_DIR" || die "Cannot create Nix directory at $HOST_NIX_DIR"
    fi
    printf 'Nix host directory resolved: %s\n' "$HOST_NIX_DIR"
}

patch_termux_chroot() {
    log "[3/5] Validating and patching termux-chroot"
    [[ -f "$CHROOT_BIN" ]] || die "Missing $CHROOT_BIN. Install or repair proot in Termux."

    mkdir -p "$BACKUP_DIR"
    if [[ ! -f "$CHROOT_BACKUP" ]]; then
        cp -p "$CHROOT_BIN" "$CHROOT_BACKUP"
        log "Saved original termux-chroot backup to $CHROOT_BACKUP"
    fi

    if grep -Fq -- "-b ${HOST_NIX_DIR}:/nix" "$CHROOT_BIN"; then
        log "Nix bind mount is already configured in termux-chroot."
        return
    fi

    cp -p "$CHROOT_BACKUP" "$CHROOT_BIN"
    grep -q 'proot' "$CHROOT_BIN" || die "Unexpected termux-chroot implementation."

    sed -i "s|proot |proot -b ${HOST_NIX_DIR}:/nix |g" "$CHROOT_BIN"
    grep -Fq -- "-b ${HOST_NIX_DIR}:/nix" "$CHROOT_BIN" || die "Failed to patch bind mount into termux-chroot."
    bash -n "$CHROOT_BIN" || die "Patched termux-chroot failed syntax check."

    log "Successfully patched termux-chroot with bind mount: ${HOST_NIX_DIR} -> /nix"
}

write_nix_environment_loader() {
    log "[4/5] Writing Lix environment loader script"
    mkdir -p "$CONFIG_DIR"

    cat > "$ENV_FILE" <<'LOADER'
# Managed by Yuko's Termux Lix bootstrap.
yuko_load_lix() {
    local candidate

    if [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
        . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
    elif [[ -f "/root/.nix-profile/etc/profile.d/nix.sh" ]]; then
        . "/root/.nix-profile/etc/profile.d/nix.sh"
    fi

    [[ -f /etc/profile.d/nix.sh ]] && . /etc/profile.d/nix.sh
    export PATH="${HOME}/.nix-profile/bin:${PATH}"

    if [[ -f /data/data/com.termux/files/usr/etc/tls/cert.pem ]]; then
        export NIX_SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
        export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
    fi

    if command -v nix >/dev/null 2>&1 && nix --version >/dev/null 2>&1; then
        return 0
    fi

    for candidate in /nix/store/*lix*/bin/nix /nix/store/*-nix-*/bin/nix; do
        [[ -x "$candidate" ]] || continue
        if "$candidate" --version >/dev/null 2>&1; then
            export PATH="${candidate%/bin/nix}/bin:${PATH}"
            return 0
        fi
    done

    return 1
}

yuko_load_lix || true
unset -f yuko_load_lix
LOADER

    chmod 600 "$ENV_FILE"
}

install_startup_hook() {
    local file="$1"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    if [[ -w "$(dirname "$file")" ]]; then
        touch "$file" 2>/dev/null || true
        if [[ -f "$file" ]]; then
            if grep -q "$STARTUP_BEGIN" "$file" 2>/dev/null; then
                sed -i "/${STARTUP_BEGIN}/,/${STARTUP_END}/d" "$file"
            fi
            cat >> "$file" <<'HOOK'

# >>> yuko-nix-env >>>
if [[ -d /nix/store && -f "$HOME/.config/nix/termux-env.bash" ]]; then
    . "$HOME/.config/nix/termux-env.bash"
fi
# <<< yuko-nix-env <<<
HOOK
        fi
    fi
}

configure_nix() {
    log "[5/5] Configuring Lix configuration and shell profile hooks"
    mkdir -p "$CONFIG_DIR"
    touch "$NIX_CONF"

    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/yuko-nix-conf.XXXXXX")"
    TEMP_FILES+=("$tmp")

    awk '
        /^[[:space:]]*experimental-features[[:space:]]*=/ { next }
        /^[[:space:]]*sandbox[[:space:]]*=/ { next }
        { print }
    ' "$NIX_CONF" > "$tmp"

    cat >> "$tmp" <<'CONF'
# Managed by Yuko's Termux Lix bootstrap.
experimental-features = nix-command flakes
sandbox = false
CONF

    cat "$tmp" > "$NIX_CONF"
    chmod 600 "$NIX_CONF"

    install_startup_hook "${HOME}/.bashrc"
    install_startup_hook "${HOME}/.bash_profile"
    install_startup_hook "${HOME}/.profile"
}

bootstrap_lix() {
    log "Bootstrapping Lix engine inside PRoot (bypassing upstream channel locks)"

    termux-chroot bash -s -- "$ENV_FILE" <<'PRROOT'
set -Eeuo pipefail

CONFIG_DIR="${HOME}/.config/nix"
ENV_FILE="${1:-${CONFIG_DIR}/termux-env.bash}"
mkdir -p /nix "$CONFIG_DIR"

[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"

if command -v nix >/dev/null 2>&1 && nix --version >/dev/null 2>&1; then
    echo "==> Existing Lix/Nix installation is healthy."
else
    if ! command -v nix >/dev/null 2>&1; then
        echo "==> Fetching official Lix installer..."
        installer_tmp="/tmp/lix-install.sh"

        curl --connect-timeout 30 --max-time 300 -fSLv https://install.lix.systems/lix | sh -s -- --no-daemon || {
            echo "ERROR: Lix installation failed." >&2
            exit 1
        }
    fi

    # Load profile paths
    [[ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]] && . "${HOME}/.nix-profile/etc/profile.d/nix.sh"

    for candidate in /nix/store/*lix*/bin/nix /nix/store/*-nix-*/bin/nix; do
        [[ -x "$candidate" ]] && export PATH="${candidate%/bin/nix}/bin:$PATH"
    done

    command -v nix >/dev/null 2>&1 || {
        echo "ERROR: Lix executable not found after installation." >&2
        exit 1
    }
    nix --version
fi

echo "==> Verifying Flakes capability..."
nix flake --help >/dev/null && echo "==> Lix and Flakes support verified successfully!"
PRROOT
}

main() {
    require_termux
    install_dependencies
    choose_nix_directory
    patch_termux_chroot
    write_nix_environment_loader
    configure_nix
    bootstrap_lix

    log "Lix bootstrap completed successfully!"
    cat <<'SUMMARY'

To enter your environment and use flakes:

  termux-chroot
  nix --version
  nix flake --help

SUMMARY
}

main "$@"

