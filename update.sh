#!/bin/bash
set -u

INSTALL_DIR="/usr/local/bin"
HOST_SCRIPTS_DIR="${SENDER_HOST_SCRIPTS_DIR:-/opt/upri/host-scripts}"
BACKUP_ROOT="${INSTALL_DIR}/.upri-backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_INSTALL_PATH="${INSTALL_DIR}/sender-backend"
FRONTEND_INSTALL_PATH="${INSTALL_DIR}/sender-frontend"
BACKEND_HOST_SCRIPT="${HOST_SCRIPTS_DIR}/sender-backend"
FRONTEND_HOST_SCRIPT="${HOST_SCRIPTS_DIR}/sender-frontend"

BACKEND_SOURCE_SCRIPT="${SCRIPT_DIR}/sender-backend.sh"
FRONTEND_FALLBACK_URL="https://raw.githubusercontent.com/UPRI-earthquake/sender-frontend/rshake-alerts/sender-frontend.sh"

BOOTSTRAP_FAILED=0

ok() {
    echo -en "[  \e[32mOK\e[0m  ] "
    echo "$1"
}

warn() {
    echo -en "[\e[1;33mWARN\e[0m] "
    echo "$1"
}

fail() {
    echo -en "[\e[1;31mFAILED\e[0m] "
    echo "$1"
}

install_file_with_sudo() {
    local src_file="$1"
    local dest_file="$2"
    local mode="${3:-0755}"

    if install -m "$mode" "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    if sudo install -m "$mode" "$src_file" "$dest_file" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

write_wrapper() {
    local target="$1"
    local delegate="$2"
    local tmp_file

    tmp_file="$(mktemp /tmp/upri-wrapper.XXXXXX)" || return 1
    cat <<WRAP > "$tmp_file"
#!/bin/sh
exec "$delegate" "\$@"
WRAP

    if ! install_file_with_sudo "$tmp_file" "$target" 0755; then
        rm -f "$tmp_file" >/dev/null 2>&1
        return 1
    fi

    rm -f "$tmp_file" >/dev/null 2>&1
    return 0
}

rollback_bootstrap() {
    warn "Rolling back bootstrap using backups from $BACKUP_DIR"

    if [[ -f "$BACKUP_DIR/sender-backend" ]]; then
        install_file_with_sudo "$BACKUP_DIR/sender-backend" "$BACKEND_INSTALL_PATH" 0755 || warn "Failed to restore sender-backend launcher"
    fi

    if [[ -f "$BACKUP_DIR/sender-frontend" ]]; then
        install_file_with_sudo "$BACKUP_DIR/sender-frontend" "$FRONTEND_INSTALL_PATH" 0755 || warn "Failed to restore sender-frontend launcher"
    fi

    sudo systemctl restart sender-backend.service >/dev/null 2>&1 || true
    sudo systemctl restart sender-frontend.service >/dev/null 2>&1 || true
}

run_or_fail() {
    local msg="$1"
    shift

    if "$@"; then
        ok "$msg"
        return 0
    fi

    fail "$msg"
    BOOTSTRAP_FAILED=1
    return 1
}

ensure_prerequisites() {
    [[ -x "$BACKEND_SOURCE_SCRIPT" ]] || {
        fail "Missing backend source script at $BACKEND_SOURCE_SCRIPT"
        exit 1
    }

    command -v docker >/dev/null 2>&1 || {
        fail "docker is required"
        exit 1
    }

    command -v sender-backend >/dev/null 2>&1 || {
        fail "sender-backend command is required before bootstrap"
        exit 1
    }

    command -v sender-frontend >/dev/null 2>&1 || {
        fail "sender-frontend command is required before bootstrap"
        exit 1
    }
}

backup_existing_launchers() {
    run_or_fail "Prepared backup directory $BACKUP_DIR" sudo mkdir -p "$BACKUP_DIR" || return 1

    if [[ -f "$BACKEND_INSTALL_PATH" ]]; then
        run_or_fail "Backed up $BACKEND_INSTALL_PATH" sudo cp "$BACKEND_INSTALL_PATH" "$BACKUP_DIR/sender-backend" || return 1
    else
        warn "No existing sender-backend launcher at $BACKEND_INSTALL_PATH"
    fi

    if [[ -f "$FRONTEND_INSTALL_PATH" ]]; then
        run_or_fail "Backed up $FRONTEND_INSTALL_PATH" sudo cp "$FRONTEND_INSTALL_PATH" "$BACKUP_DIR/sender-frontend" || return 1
    else
        warn "No existing sender-frontend launcher at $FRONTEND_INSTALL_PATH"
    fi
}

seed_host_scripts() {
    local tmp_frontend

    run_or_fail "Ensured host script directory $HOST_SCRIPTS_DIR" sudo mkdir -p "$HOST_SCRIPTS_DIR" || return 1

    run_or_fail "Seeded backend host script" install_file_with_sudo "$BACKEND_SOURCE_SCRIPT" "$BACKEND_HOST_SCRIPT" 0755 || return 1

    if [[ -f "$BACKUP_DIR/sender-frontend" ]]; then
        run_or_fail "Seeded frontend host script from launcher backup" install_file_with_sudo "$BACKUP_DIR/sender-frontend" "$FRONTEND_HOST_SCRIPT" 0755 || return 1
        return 0
    fi

    if [[ -f "$FRONTEND_INSTALL_PATH" ]]; then
        run_or_fail "Seeded frontend host script from current launcher" install_file_with_sudo "$FRONTEND_INSTALL_PATH" "$FRONTEND_HOST_SCRIPT" 0755 || return 1
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        tmp_frontend="$(mktemp /tmp/sender-frontend.XXXXXX)" || return 1
        if curl -fsSL "$FRONTEND_FALLBACK_URL" -o "$tmp_frontend"; then
            run_or_fail "Seeded frontend host script from fallback URL" install_file_with_sudo "$tmp_frontend" "$FRONTEND_HOST_SCRIPT" 0755 || {
                rm -f "$tmp_frontend" >/dev/null 2>&1
                return 1
            }
            rm -f "$tmp_frontend" >/dev/null 2>&1
            return 0
        fi
        rm -f "$tmp_frontend" >/dev/null 2>&1
    fi

    fail "Unable to seed frontend host script"
    BOOTSTRAP_FAILED=1
    return 1
}

install_wrappers() {
    write_wrapper "$BACKEND_INSTALL_PATH" "$BACKEND_HOST_SCRIPT" || {
        fail "Failed to install backend wrapper at $BACKEND_INSTALL_PATH"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "Installed backend wrapper at $BACKEND_INSTALL_PATH"

    write_wrapper "$FRONTEND_INSTALL_PATH" "$FRONTEND_HOST_SCRIPT" || {
        fail "Failed to install frontend wrapper at $FRONTEND_INSTALL_PATH"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "Installed frontend wrapper at $FRONTEND_INSTALL_PATH"

    return 0
}

run_bootstrap_update() {
    sender-backend UPDATE_STACK || {
        fail "sender-backend UPDATE_STACK failed"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "sender-backend UPDATE_STACK completed"

    sudo sender-backend INSTALL_SERVICE || {
        fail "Failed to install/refresh sender-backend service"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "sender-backend service installed/refreshed"

    sudo sender-frontend INSTALL_SERVICE || {
        fail "Failed to install/refresh sender-frontend service"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "sender-frontend service installed/refreshed"

    sudo systemctl restart sender-backend.service || {
        fail "Failed to restart sender-backend.service"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "sender-backend.service restarted"

    sudo systemctl restart sender-frontend.service || {
        fail "Failed to restart sender-frontend.service"
        BOOTSTRAP_FAILED=1
        return 1
    }
    ok "sender-frontend.service restarted"

    if [[ "$(docker inspect --format='{{.State.Running}}' sender-backend 2>/dev/null)" != "true" ]]; then
        fail "sender-backend container is not running after bootstrap"
        BOOTSTRAP_FAILED=1
        return 1
    fi

    if [[ "$(docker inspect --format='{{.State.Running}}' sender-frontend 2>/dev/null)" != "true" ]]; then
        fail "sender-frontend container is not running after bootstrap"
        BOOTSTRAP_FAILED=1
        return 1
    fi

    ok "Both sender containers are running"
    return 0
}

main() {
    ensure_prerequisites

    echo "Running sender bootstrap-v2 rollout..."
    backup_existing_launchers || {
        rollback_bootstrap
        exit 1
    }

    seed_host_scripts || {
        rollback_bootstrap
        exit 1
    }

    install_wrappers || {
        rollback_bootstrap
        exit 1
    }

    run_bootstrap_update || {
        rollback_bootstrap
        exit 1
    }

    ok "Bootstrap-v2 rollout completed successfully"
    echo "Host scripts are now managed under $HOST_SCRIPTS_DIR via stable wrappers in $INSTALL_DIR"
}

main
