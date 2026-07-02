#!/bin/bash
# rivendell-config — Rivendell Radio Automation System config TUI
# Requirements: bash 4+, gum (auto-installed if absent), root/sudo
# Install: sudo cp rivendell-config.sh /usr/local/bin/rivendell-config && chmod +x /usr/local/bin/rivendell-config

SCRIPT_VERSION="1.1.0"

RD_CONF="/etc/rd.conf"
RD_SERVICE="rivendell"
RD_DEFAULT_AUDIO_DIR="/var/snd"
RD_CONF_SAMPLE_URL="https://raw.githubusercontent.com/edgeradio993fm/rivendell/master/conf/rd.conf-sample"
DEB_MULTIMEDIA_KEYRING_URL="http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2024.9.1_all.deb"
RD_CONFIG_UPDATE_URL="https://raw.githubusercontent.com/alastairtech/rivendell-arm/refs/heads/main/rivendell-config.sh"

# Detect CPU architecture and select the matching Rivendell repo.
# edgeradio.org.au hosts separate repos for aarch64 (Raspberry Pi / ARM64)
# and amd64 (standard x86-64 Debian/Ubuntu).
_detect_rd_repo() {
    local dpkg_arch
    dpkg_arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$dpkg_arch" in
        arm64|aarch64)
            RD_REPO_SLUG="rivendell-aarch64"
            RD_REPO_APT_ARCH="arm64"
            ;;
        amd64|x86_64)
            RD_REPO_SLUG="rivendell-amd64"
            RD_REPO_APT_ARCH="amd64"
            ;;
        armhf|armv7*)
            RD_REPO_SLUG="rivendell-aarch64"   # closest available; may need adjustment
            RD_REPO_APT_ARCH="armhf"
            ;;
        *)
            echo "WARNING: unrecognised architecture '$dpkg_arch' — defaulting to aarch64 repo." >&2
            RD_REPO_SLUG="rivendell-aarch64"
            RD_REPO_APT_ARCH="any"
            ;;
    esac

    # Debian 13 (trixie) has its own combined repo, built directly for that release
    # and covering multiple architectures under one "any" entry, rather than the
    # older per-architecture repos above. Prefer it whenever running on trixie,
    # regardless of CPU architecture. (Inlined codename lookup rather than calling
    # _deb_suite() — that helper is defined further down the script, after this
    # function already runs at load time.)
    RD_REPO_ARCH_OPT=""
    if [ "$(grep ^VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2)" = "trixie" ]; then
        RD_REPO_SLUG="rivendell-trixie"
        RD_REPO_APT_ARCH="any"
        RD_REPO_ARCH_OPT="arch=any "
    fi

    RD_REPO_LIST="/etc/apt/sources.list.d/openrepo-${RD_REPO_SLUG}.list"
    RD_REPO_KEY_URL="https://repo.edgeradio.org.au/${RD_REPO_SLUG}/public.gpg"
    RD_REPO_KEY_FILE="/usr/share/keyrings/openrepo-${RD_REPO_SLUG}.gpg"
    RD_REPO_URL="https://repo.edgeradio.org.au/${RD_REPO_SLUG}/"
}
_detect_rd_repo

C_ACCENT="#7DCFFF"
C_SUCCESS="#50FA7B"
C_ERROR="#FF5555"
C_WARN="#F1FA8C"
C_MUTED="#888888"

# Set by check_os_compat(); empty when no issues found
OS_COMPAT_WARN=""

# ── Root check ───────────────────────────────────────────────────────────────

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: run this script with sudo or as root." >&2
        exit 1
    fi
}

# ── Gum bootstrap ────────────────────────────────────────────────────────────

_gum_install_via_apt() {
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || return 1
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        > /etc/apt/sources.list.d/charm.list
    apt-get update -qq 2>/dev/null
    apt-get install -y gum 2>/dev/null
    command -v gum &>/dev/null
}

_gum_install_binary() {
    local arch gum_arch gum_ver gum_file gum_url tmp_dir
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        amd64|x86_64)  gum_arch="x86_64" ;;
        arm64|aarch64) gum_arch="arm64"   ;;
        armhf|armv7*)  gum_arch="armv7"   ;;
        *) echo "Unsupported architecture: $arch" >&2; return 1 ;;
    esac
    gum_ver=$(curl -fsSL "https://api.github.com/repos/charmbracelet/gum/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -z "$gum_ver" ] && { echo "Could not determine latest gum version." >&2; return 1; }
    gum_file="gum_${gum_ver}_Linux_${gum_arch}.tar.gz"
    gum_url="https://github.com/charmbracelet/gum/releases/download/v${gum_ver}/${gum_file}"
    tmp_dir=$(mktemp -d)
    if curl -fsSL "$gum_url" -o "${tmp_dir}/gum.tar.gz"; then
        tar -xzf "${tmp_dir}/gum.tar.gz" -C "$tmp_dir" 2>/dev/null
        [ -f "${tmp_dir}/gum" ] && install -m 755 "${tmp_dir}/gum" /usr/local/bin/gum
    fi
    rm -rf "$tmp_dir"
    command -v gum &>/dev/null
}

ensure_gum() {
    command -v gum &>/dev/null && return 0

    printf '\n%s\n%s\n%s\n\n' \
        "┌────────────────────────────────────────────────────┐" \
        "│  'gum' is required for this tool's terminal UI.   │" \
        "└────────────────────────────────────────────────────┘"
    printf 'Install gum automatically? [y/N]: '
    read -r _ans
    case "$_ans" in
        [Yy]*) ;;
        *) echo "Cannot continue without gum."; exit 1 ;;
    esac

    echo "Trying Charm apt repository..."
    if ! _gum_install_via_apt; then
        echo "apt method failed. Trying direct binary download..."
        _gum_install_binary || true
    fi

    if ! command -v gum &>/dev/null; then
        echo "ERROR: could not install gum. Install manually:" >&2
        echo "  https://github.com/charmbracelet/gum#installation" >&2
        exit 1
    fi
    echo "gum installed successfully."
}

# ── UI helpers ───────────────────────────────────────────────────────────────

show_banner() {
    clear
    gum style \
        --border double --border-foreground "$C_ACCENT" \
        --foreground "$C_ACCENT" --bold \
        --padding "1 4" --margin "1 2" \
        "  Rivendell Config  " \
        "$(gum style --foreground "$C_MUTED" "  v${SCRIPT_VERSION}  ")"
}

header() {
    echo
    gum style \
        --border normal --border-foreground "$C_ACCENT" \
        --foreground "$C_ACCENT" --bold \
        --padding "0 2" \
        "$1"
    echo
}

msg_success() { gum style --foreground "$C_SUCCESS" --bold "✓  $1"; }
msg_error()   { gum style --foreground "$C_ERROR"   --bold "✗  $1" >&2; }
msg_warn()    { gum style --foreground "$C_WARN"          "⚠  $1"; }
msg_info()    { gum style --foreground "$C_MUTED"         "   $1"; }

press_enter() {
    echo
    gum style --foreground "$C_MUTED" "Press Enter to continue..."
    read -r _
}

# ── INI config helpers (rd.conf) ─────────────────────────────────────────────

rdconf_get() {
    local section="$1" key="$2"
    [ ! -f "$RD_CONF" ] && return
    awk -v s="[$section]" -v k="$key" '
        /^\[/ { in_s = ($0 == s) }
        in_s && $0 ~ "^"k"=" { sub(/^[^=]+=/, ""); print; exit }
    ' "$RD_CONF"
}

rdconf_set() {
    local section="$1" key="$2" value="$3"
    [ ! -f "$RD_CONF" ] && return 1
    awk -v s="[$section]" -v k="$key" -v v="$value" '
        /^\[/ {
            if (in_s && !found) { print k"="v; found=1 }
            in_s = ($0 == s)
            if (in_s) { seen_section=1 }
        }
        in_s && $0 ~ "^"k"=" { $0 = k"="v; found=1 }
        { print }
        END {
            if (in_s && !found) print k"="v
            if (!seen_section) { print ""; print s; print k"="v }
        }
    ' "$RD_CONF" > "${RD_CONF}.tmp" && mv "${RD_CONF}.tmp" "$RD_CONF"
}

# ── Rivendell DB helpers ─────────────────────────────────────────────────────
# Rivendell doesn't keep per-card audio settings in rd.conf — caed auto-detects
# ALSA/JACK/HPi hardware at startup and records it in the database. The bits an
# admin actually sets (whether caed should launch jackd, its server name and
# command line) live in STATIONS; auxiliary programs to run alongside jackd
# (our port-connection script) go in JACK_CLIENTS. These helpers read the DB
# connection details straight from rd.conf's [mySQL] section to reach it.

_sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

_rd_mysql() {
    local host user pass db
    host=$(rdconf_get "mySQL" "Hostname")
    user=$(rdconf_get "mySQL" "Loginname")
    pass=$(rdconf_get "mySQL" "Password")
    db=$(rdconf_get "mySQL" "Database")
    mysql -N -B -h "$host" -u "$user" -p"$pass" "$db" -e "$1" 2>/dev/null
}

# ── Detection helpers ────────────────────────────────────────────────────────

is_rivendell_installed() {
    dpkg --status rivendell 2>/dev/null | grep -q "^Status: install ok installed"
}

pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Returns the Debian release codename for use in apt sources (bookworm, trixie, …)
_deb_suite() {
    grep ^VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2
}

# Sets OS_COMPAT_WARN if the host OS has known issues with the Rivendell repo.
# Debian 13 dropped ImageMagick 6 entirely; the pre-built packages from the older,
# per-architecture repos (rivendell-aarch64/-amd64) depend on it, so apt will refuse
# to install them. The rivendell-trixie repo (see _detect_rd_repo) is built fresh
# against trixie's own libraries (ImageMagick 7) and doesn't have this problem, so
# only warn when we'd actually fall back to one of the older repos.
check_os_compat() {
    local ver
    ver=$(grep ^VERSION_ID /etc/os-release 2>/dev/null | tr -d '"' | cut -d= -f2)
    [ -z "$ver" ] && return 0
    if [ "$ver" -ge 13 ] 2>/dev/null && [ "$RD_REPO_SLUG" != "rivendell-trixie" ]; then
        OS_COMPAT_WARN="Debian ${ver}: ImageMagick 6 is absent — pre-built Rivendell packages require it and may fail to install."
    fi
}

# Prints a bordered warning box if OS_COMPAT_WARN is set.
show_os_compat_warning() {
    [ -z "${OS_COMPAT_WARN:-}" ] && return 0
    gum style \
        --border normal --border-foreground "$C_WARN" \
        --foreground "$C_WARN" \
        --padding "0 2" \
        "⚠  Compatibility Warning" \
        "" \
        "$OS_COMPAT_WARN" \
        "" \
        "Options:  (1) Use Debian 12 instead" \
        "          (2) Request a trixie build from the repo maintainers" \
        "          (3) Build from source with ImageMagick 7 patches"
    echo
}

# ── System summary (main menu) ────────────────────────────────────────────────

show_system_summary() {
    local os_name kernel arch host_name
    os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
    kernel=$(uname -r)
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    host_name=$(hostname)

    local rd_ver svc_status svc_icon
    rd_ver=$(dpkg -s rivendell 2>/dev/null | awk '/^Version:/{print $2}')
    svc_status=$(systemctl is-active "$RD_SERVICE" 2>/dev/null || echo "unknown")
    [ "$svc_status" = "active" ] && svc_icon="●" || svc_icon="○"

    local db_host db_user db_name
    db_host=$(rdconf_get "mySQL" "Hostname");  [ -z "$db_host" ] && db_host="not set"
    db_user=$(rdconf_get "mySQL" "Loginname"); [ -z "$db_user" ] && db_user="not set"
    db_name=$(rdconf_get "mySQL" "Database");  [ -z "$db_name" ] && db_name="not set"

    local audio_dir audio_info fs_type
    audio_dir="$RD_DEFAULT_AUDIO_DIR"
    if mountpoint -q "$audio_dir" 2>/dev/null; then
        fs_type=$(findmnt -n -o FSTYPE "$audio_dir" 2>/dev/null || echo "mounted")
        audio_info="$audio_dir  ($fs_type)"
    elif [ -d "$audio_dir" ]; then
        audio_info="$audio_dir  (local)"
    else
        audio_info="$audio_dir  (not found)"
    fi

    # Build optional compat warning line for the summary box
    local warn_line=""
    [ -n "${OS_COMPAT_WARN:-}" ] && warn_line="$(printf '\n⚠  %s' "$OS_COMPAT_WARN")"

    gum style \
        --border normal --border-foreground "$C_MUTED" \
        --padding "0 2" --margin "0 1" \
        "OS        $os_name" \
        "Host      $host_name  ·  $arch  ·  $kernel" \
        "" \
        "Rivendell ${rd_ver:-unknown}  ·  $svc_icon $svc_status" \
        "DB        ${db_user}@${db_host} / ${db_name}" \
        "Audio     $audio_info" \
        "Config    $RD_CONF${warn_line}"
}

# ── Audio storage ────────────────────────────────────────────────────────────

configure_audio_storage_interactive() {
    header "Audio Storage"

    local choice
    choice=$(gum choose \
        --header "Select audio storage type:" \
        "Local directory" \
        "NFS share" \
        "SMB/CIFS share") || return 0

    case "$choice" in

        "Local directory")
            # Rivendell's audio-store path is compiled in (RD_AUDIO_ROOT = /var/snd,
            # overridable only via rd.conf's [Cae]/AudioRoot). Rather than redirect
            # Rivendell to a custom path — which means every future config/reinstall
            # step has to remember to preserve that override — just always use the
            # folder Rivendell already expects, and bind-mount whatever storage the
            # user actually wants underneath it. Same pattern as the NFS/SMB cases
            # below, just with "bind" as the fstab mount type instead of nfs/cifs.
            local path
            path=$(gum input \
                --value "$RD_DEFAULT_AUDIO_DIR" \
                --header "Folder to use for audio storage:") || return 0
            [ -z "$path" ] && path="$RD_DEFAULT_AUDIO_DIR"

            gum confirm "Use '$path' as Rivendell's audio store ($RD_DEFAULT_AUDIO_DIR)?" || return 0

            mkdir -p "$path"
            if ! id rivendell &>/dev/null; then
                adduser --system --group --home="$RD_DEFAULT_AUDIO_DIR" rivendell
            fi
            local run_user="${SUDO_USER:-}"
            if [ -n "$run_user" ] && [ "$run_user" != "root" ]; then
                usermod -aG rivendell "$run_user" 2>/dev/null || true
            fi
            chown rivendell:rivendell "$path"
            chmod 2775 "$path"

            if [ "$path" = "$RD_DEFAULT_AUDIO_DIR" ]; then
                msg_success "Local audio storage configured at $RD_DEFAULT_AUDIO_DIR"
            else
                mkdir -p "$RD_DEFAULT_AUDIO_DIR"
                local fstab_entry="$path $RD_DEFAULT_AUDIO_DIR none bind 0 0"
                if ! grep -qF "$fstab_entry" /etc/fstab; then
                    echo "$fstab_entry" >> /etc/fstab
                    msg_info "Added bind-mount entry to /etc/fstab."
                fi
                if ! mountpoint -q "$RD_DEFAULT_AUDIO_DIR"; then
                    if ! gum spin --title "Bind-mounting $path at $RD_DEFAULT_AUDIO_DIR..." -- \
                            mount "$RD_DEFAULT_AUDIO_DIR"; then
                        msg_error "Bind mount failed."
                        return 1
                    fi
                fi
                chown rivendell:rivendell "$RD_DEFAULT_AUDIO_DIR"
                msg_success "'$path' bind-mounted at $RD_DEFAULT_AUDIO_DIR"
            fi
            ;;

        "NFS share")
            local srv exp mnt="$RD_DEFAULT_AUDIO_DIR"
            while true; do
                srv=$(gum input \
                    --placeholder "192.168.1.10" \
                    --header "NFS server hostname or IP:") || return 0
                [ -n "$srv" ] && break
                msg_error "Server cannot be empty."
            done

            # Ensure showmount is available before querying the server
            if ! pkg_installed nfs-common; then
                gum spin --title "Installing nfs-common..." -- \
                    apt-get install -y -q nfs-common
            fi

            # Try to discover exports from the server; fall back to manual entry
            local exports
            exports=$(gum spin --title "Querying exports from $srv..." -- \
                showmount -e --no-headers "$srv" 2>/dev/null \
                | awk '{print $1}')

            if [ -n "$exports" ]; then
                exp=$(printf '%s\n' "$exports" | gum choose \
                    --header "Available exports on $srv:") || return 0
            else
                msg_warn "Could not retrieve export list from $srv (server unreachable or showmount blocked)."
                while true; do
                    exp=$(gum input \
                        --placeholder "/exports/audio" \
                        --header "NFS export path:") || return 0
                    [ -n "$exp" ] && break
                    msg_error "Export path cannot be empty."
                done
            fi

            gum confirm "Mount ${srv}:${exp} at $mnt (Rivendell's audio store)?" || return 0

            mkdir -p "$mnt"

            local fstab_entry="${srv}:${exp} ${mnt} nfs defaults 0 0"
            if ! grep -qF "$fstab_entry" /etc/fstab; then
                echo "$fstab_entry" >> /etc/fstab
                msg_info "Added NFS entry to /etc/fstab."
            fi
            if ! mountpoint -q "$mnt"; then
                if ! gum spin --title "Mounting NFS share..." -- mount "$mnt"; then
                    msg_error "Mount failed — check server and export path."
                    return 1
                fi
            fi
            chown rivendell:rivendell "$mnt" 2>/dev/null || true
            msg_success "NFS share mounted at $mnt"
            ;;

        "SMB/CIFS share")
            local srv share mnt="$RD_DEFAULT_AUDIO_DIR" smb_user smb_pass
            while true; do
                srv=$(gum input \
                    --placeholder "192.168.1.10" \
                    --header "SMB server hostname or IP:") || return 0
                [ -n "$srv" ] && break
                msg_error "Server cannot be empty."
            done

            # Ensure smbclient is available for share discovery
            if ! command -v smbclient &>/dev/null; then
                gum spin --title "Installing smbclient..." -- \
                    apt-get install -y -q smbclient
            fi

            # Helper: query disk shares from server, filtering out hidden admin shares ($)
            _smb_list_shares() {
                local host="$1" user="$2" pass="$3"
                local tmp
                tmp=$(mktemp)
                if [ -n "$user" ]; then
                    gum spin --title "Querying shares on $host..." -- \
                        bash -c "smbclient -L '$host' -U '${user}%${pass}' > '$tmp' 2>/dev/null || true"
                else
                    gum spin --title "Querying shares on $host (anonymous)..." -- \
                        bash -c "smbclient -L '$host' -N > '$tmp' 2>/dev/null || true"
                fi
                awk '/Disk/{ if ($1 !~ /\$/) print $1 }' "$tmp"
                rm -f "$tmp"
            }

            # Try anonymous listing first; prompt for credentials only if it fails
            local shares
            shares=$(_smb_list_shares "$srv" "" "")

            if [ -z "$shares" ]; then
                msg_warn "Anonymous share listing failed — enter credentials to try again."
                smb_user=$(gum input \
                    --placeholder "rduser" \
                    --header "SMB username:") || return 0
                smb_pass=$(gum input \
                    --password --placeholder "password" \
                    --header "SMB password:") || return 0
                shares=$(_smb_list_shares "$srv" "$smb_user" "$smb_pass")
            fi

            if [ -n "$shares" ]; then
                share=$(printf '%s\n' "$shares" | gum choose \
                    --header "Available shares on $srv:") || return 0
            else
                msg_warn "Could not retrieve share list from $srv (server unreachable, browsing disabled, or bad credentials)."
                while true; do
                    share=$(gum input \
                        --placeholder "audio" \
                        --header "Share name:") || return 0
                    [ -n "$share" ] && break
                    msg_error "Share name cannot be empty."
                done
            fi

            # Collect credentials now if anonymous listing succeeded (they're still needed for mounting)
            if [ -z "${smb_user:-}" ]; then
                smb_user=$(gum input \
                    --placeholder "rduser" \
                    --header "SMB username (for mounting):") || return 0
                smb_pass=$(gum input \
                    --password --placeholder "password" \
                    --header "SMB password:") || return 0
            fi

            gum confirm "Mount //${srv}/${share} at $mnt (Rivendell's audio store)?" || return 0

            mkdir -p "$mnt"
            if ! pkg_installed cifs-utils; then
                gum spin --title "Installing cifs-utils..." -- \
                    apt-get install -y -q cifs-utils
            fi

            local creds="/etc/rivendell-smb-credentials"
            printf 'username=%s\npassword=%s\n' "$smb_user" "$smb_pass" > "$creds"
            chmod 600 "$creds"

            local rd_uid rd_gid
            rd_uid=$(id -u rivendell 2>/dev/null || echo "1000")
            rd_gid=$(id -g rivendell 2>/dev/null || echo "1000")

            local fstab_entry="//${srv}/${share} ${mnt} cifs credentials=${creds},uid=${rd_uid},gid=${rd_gid},file_mode=0664,dir_mode=2775 0 0"
            if ! grep -qF "//${srv}/${share}" /etc/fstab; then
                echo "$fstab_entry" >> /etc/fstab
                msg_info "Added SMB entry to /etc/fstab."
            fi
            if ! mountpoint -q "$mnt"; then
                if ! gum spin --title "Mounting SMB share..." -- mount "$mnt"; then
                    msg_error "Mount failed — check server, share name, and credentials."
                    return 1
                fi
            fi
            msg_success "SMB share mounted at $mnt"
            ;;
    esac
}

# ── Database configuration ───────────────────────────────────────────────────

configure_database_interactive() {
    local fresh_install="${1:-false}"
    header "Database Configuration"

    local db_type
    db_type=$(gum choose \
        --header "Database location:" \
        "Local MySQL/MariaDB" \
        "Remote MySQL server") || return 0

    local cur_host cur_user cur_db
    cur_host=$(rdconf_get "mySQL" "Hostname");  [ -z "$cur_host" ] && cur_host="localhost"
    cur_user=$(rdconf_get "mySQL" "Loginname"); [ -z "$cur_user" ] && cur_user="rduser"
    cur_db=$(rdconf_get "mySQL" "Database");    [ -z "$cur_db"   ] && cur_db="Rivendell"

    local db_host db_port db_name db_user db_pass

    if [ "$db_type" = "Local MySQL/MariaDB" ]; then
        db_host="localhost"
        db_port="3306"
        db_name=$(gum input --value "$cur_db"   --header "Database name:")   || return 0
        db_user=$(gum input --value "$cur_user"  --header "Database user:")   || return 0
        db_pass=$(gum input --password --placeholder "enter password" \
                             --header "Database password:")                    || return 0
        [ -z "$db_name" ] && db_name="Rivendell"
        [ -z "$db_user" ] && db_user="rduser"
        [ -z "$db_pass" ] && db_pass="hackme"
    else
        while true; do
            db_host=$(gum input --value "$cur_host" --header "Database hostname or IP:") || return 0
            [ -n "$db_host" ] && break
            msg_error "Hostname cannot be empty."
        done
        db_port=$(gum input --value "3306" --header "Database port:") || return 0
        [ -z "$db_port" ] && db_port="3306"
        db_name=$(gum input --value "$cur_db"  --header "Database name:")  || return 0
        db_user=$(gum input --value "$cur_user" --header "Database user:")  || return 0
        db_pass=$(gum input --password --placeholder "enter password" \
                             --header "Database password:")                   || return 0
        [ -z "$db_name" ] && db_name="Rivendell"
        [ -z "$db_user" ] && db_user="rduser"
    fi

    gum confirm "Apply: ${db_user}@${db_host}:${db_port}/${db_name}?" || return 0

    # Update rd.conf
    if [ -f "$RD_CONF" ]; then
        rdconf_set "mySQL" "Hostname"  "$db_host"
        rdconf_set "mySQL" "Loginname" "$db_user"
        rdconf_set "mySQL" "Password"  "$db_pass"
        rdconf_set "mySQL" "Database"  "$db_name"
        msg_success "Updated $RD_CONF"
    fi

    if [ "$db_type" = "Local MySQL/MariaDB" ]; then
        gum spin --title "Starting MariaDB..." -- systemctl start mariadb
        systemctl enable mariadb >/dev/null 2>&1

        if ! gum spin --title "Creating database and user..." -- \
                mysql -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
                          GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,REFERENCES,
                            INDEX,ALTER,CREATE TEMPORARY TABLES,LOCK TABLES
                            ON \`${db_name}\`.* TO '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
                          FLUSH PRIVILEGES;"; then
            msg_error "Database setup failed — is MariaDB running and accessible as root?"
            return 1
        fi

        if [ "$fresh_install" = "false" ]; then
            gum spin --title "Checking schema for updates..." --show-output -- \
                rddbmgr --update 2>/dev/null || true
        fi
    fi

    # Offer to create a blank Rivendell schema whenever the target DB is on this
    # host (localhost/127.0.0.1) on a fresh install — regardless of whether "Local
    # MySQL/MariaDB" or "Remote MySQL server" was picked above, since "Remote" can
    # legitimately point at a loopback address too. Ask rather than create silently,
    # since an existing database at that name/host shouldn't be touched unprompted.
    #
    # Check for actual tables rather than the /var/lib/mysql/<db> directory: the
    # CREATE DATABASE IF NOT EXISTS above already creates that directory even for
    # a completely empty database, so a directory-existence check here is always
    # false right after a fresh install and would silently skip this entirely.
    local _rd_table_count
    _rd_table_count=$(mysql -N -B -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db_name}';" \
        2>/dev/null)
    if [ "$fresh_install" = "true" ] \
            && { [ "$db_host" = "localhost" ] || [ "$db_host" = "127.0.0.1" ]; } \
            && [ "${_rd_table_count:-0}" -eq 0 ] 2>/dev/null; then
        if gum confirm "Create a blank Rivendell database now? (rddbmgr --create --generate-audio)"; then
            if ! gum spin --title "Creating Rivendell schema..." --show-output -- \
                    rddbmgr --create --generate-audio; then
                msg_error "Schema creation failed."
                return 1
            fi
        fi
    fi

    msg_success "Database configuration complete."
    SUMMARY_DB="${db_user}@${db_host}:${db_port}/${db_name}"
}

# ── Audio card setup (JACK) ───────────────────────────────────────────────────
# Configures caed to launch jackd itself (STATIONS.START_JACK/JACK_SERVER_NAME/
# JACK_COMMAND_LINE) and registers a port-connection script as a JACK_CLIENTS
# entry, so caed launches it alongside jackd on every start. Requires a working
# Rivendell database connection — this can't be set via rd.conf.

setup_audio_cards_interactive() {
    header "Audio Card Setup (JACK)"

    if ! command -v mysql &>/dev/null; then
        msg_error "The 'mysql' client is required to configure audio via the database."
        press_enter
        return 1
    fi

    # Normally already installed alongside Rivendell (see _ensure_jackd_installed);
    # this is a fallback for hosts set up before that was added.
    if ! command -v jackd &>/dev/null; then
        if ! _ensure_jackd_installed || ! command -v jackd &>/dev/null; then
            msg_error "Failed to install jackd2 (the JACK server)."
            press_enter
            return 1
        fi
    fi

    if ! _rd_mysql "SELECT 1;" >/dev/null; then
        msg_error "Could not connect to the Rivendell database — set it up first (Database Setup)."
        press_enter
        return 1
    fi

    # Match this machine to its Rivendell STATIONS row.
    local host_name station_name stations
    host_name=$(hostname)
    stations=$(_rd_mysql "SELECT NAME FROM STATIONS;")
    if [ -z "$stations" ]; then
        msg_error "No hosts found in the STATIONS table — add this host in RDAdmin first."
        press_enter
        return 1
    fi
    if printf '%s\n' "$stations" | grep -qx "$host_name"; then
        station_name="$host_name"
    else
        msg_warn "No STATIONS row named '$host_name' — pick this host's entry:"
        station_name=$(printf '%s\n' "$stations" | gum choose --header "Rivendell host:") || return 0
    fi
    [ -z "$station_name" ] && return 0

    # Parse aplay -l into "hw:CARD,DEV  (Name)" lines
    local devices
    devices=$(aplay -l 2>/dev/null | grep "^card " | while IFS= read -r line; do
        card=$(echo "$line" | grep -o 'card [0-9]*' | awk '{print $2}')
        device=$(echo "$line" | grep -o 'device [0-9]*' | awk '{print $2}')
        name=$(echo "$line" | grep -oP '(?<=\[)[^\]]+' | head -1)
        printf "hw:%s,%s  (%s)\n" "$card" "$device" "${name:-unknown}"
    done)

    if [ -z "$devices" ]; then
        msg_warn "No ALSA audio devices detected."
        msg_info "Ensure audio hardware is connected and kernel drivers are loaded."
        press_enter
        return 0
    fi

    echo
    gum style --foreground "$C_MUTED" "Detected audio devices:"
    echo "$devices" | while IFS= read -r d; do msg_info "$d"; done
    echo

    local device hw
    device=$(printf '%s\n' "$devices" | gum choose \
        --header "Select the ALSA device for jackd to drive:") || return 0
    hw=$(echo "$device" | awk '{print $1}')

    local jack_name rate period nperiods
    jack_name=$(gum input --value "default" --header "JACK server name:") || return 0
    [ -z "$jack_name" ] && jack_name="default"
    rate=$(gum input --value "48000" --header "Sample rate:") || return 0
    [ -z "$rate" ] && rate="48000"
    period=$(gum input --value "1024" --header "Period size (-p):") || return 0
    [ -z "$period" ] && period="1024"
    nperiods=$(gum input --value "2" --header "Number of periods (-n):") || return 0
    [ -z "$nperiods" ] && nperiods="2"

    local jack_cmd="/usr/bin/jackd --name ${jack_name} -d alsa -P ${hw} -r ${rate} -p ${period} -n ${nperiods}"

    echo
    gum style --foreground "$C_ACCENT" --bold "Will apply to host '$station_name':"
    msg_info "$jack_cmd"
    echo

    gum confirm "Apply this JACK configuration?" || return 0

    local esc_name esc_cmd esc_station
    esc_name=$(_sql_escape "$jack_name")
    esc_cmd=$(_sql_escape "$jack_cmd")
    esc_station=$(_sql_escape "$station_name")

    if _rd_mysql "UPDATE STATIONS SET START_JACK='Y', JACK_SERVER_NAME='${esc_name}', JACK_COMMAND_LINE='${esc_cmd}' WHERE NAME='${esc_station}';"; then
        msg_success "JACK settings saved to the Rivendell database."
    else
        msg_error "Failed to update the STATIONS table."
        press_enter
        return 1
    fi

    if gum confirm "Install a JACK auto-connect script for Rivendell's I/O ports?"; then
        _setup_jack_connect_script "$station_name"
    fi

    if gum confirm "Restart Rivendell to apply?"; then
        if gum spin --title "Restarting $RD_SERVICE..." -- \
                systemctl restart "$RD_SERVICE"; then
            msg_success "Rivendell restarted."
        else
            msg_error "Restart failed — check: journalctl -u $RD_SERVICE"
        fi
    fi
}

# Writes /usr/local/bin/rivendell-jack-connect.sh, wiring Rivendell's JACK
# ports (rivendell_<N>:record_*/playout_*) to the system capture/playback
# ports, then registers it in JACK_CLIENTS so caed launches it whenever it
# starts jackd — no separate systemd unit or cron entry needed.
_setup_jack_connect_script() {
    local station_name="$1" card_num
    card_num=$(gum input --value "0" --header "Rivendell card number (rivendell_N JACK client):") || card_num="0"
    [ -z "$card_num" ] && card_num="0"

    local script_path="/usr/local/bin/rivendell-jack-connect.sh"
    cat > "$script_path" <<EOF
#!/bin/bash
# Connects Rivendell's JACK ports to the system's hardware ports.
# Installed/updated by rivendell-config.sh — edit or replace as needed.

# Give JACK and Rivendell a few seconds to initialize if running this at startup
sleep 7

# --- 1. Connect System Inputs to Rivendell Record ---
jack_connect system:capture_1 rivendell_${card_num}:record_0L
jack_connect system:capture_2 rivendell_${card_num}:record_0R

# --- 2. Connect Rivendell Playout to System Outputs ---
jack_connect rivendell_${card_num}:playout_0L system:playback_1
jack_connect rivendell_${card_num}:playout_1L system:playback_1
jack_connect rivendell_${card_num}:playout_0R system:playback_2
jack_connect rivendell_${card_num}:playout_1R system:playback_2

echo "Rivendell JACK connections established."
EOF
    chmod +x "$script_path"
    msg_success "Wrote $script_path"

    local esc_station esc_path
    esc_station=$(_sql_escape "$station_name")
    esc_path=$(_sql_escape "$script_path")
    _rd_mysql "DELETE FROM JACK_CLIENTS WHERE STATION_NAME='${esc_station}' AND COMMAND_LINE='${esc_path}';"
    if _rd_mysql "INSERT INTO JACK_CLIENTS (STATION_NAME, DESCRIPTION, COMMAND_LINE) VALUES ('${esc_station}', 'Auto-connect script', '${esc_path}');"; then
        msg_success "Registered as a JACK client for '$station_name' — caed will launch it whenever JACK starts."
    else
        msg_error "Failed to register the script in JACK_CLIENTS."
    fi
}

# ── JACK server ──────────────────────────────────────────────────────────────
# The rivendell package only depends on libjack-jackd2-0 (the client library,
# needed to link against libjack) — jackd2, which provides the actual
# /usr/bin/jackd server binary the JACK driver needs at runtime, is a separate
# package apt never pulls in on its own. Install it alongside Rivendell so
# JACK works out of the box instead of failing silently later at "caed:
# failed to start JACK server".
_ensure_jackd_installed() {
    command -v jackd &>/dev/null && return 0
    _cmd_with_progress "Installing JACK server (jackd2)" 30 \
        env DEBIAN_FRONTEND=noninteractive apt-get install -y jackd2
}

# ── Rivendell repo helpers ───────────────────────────────────────────────────
# The edgeradio.org.au repo uses binary-any/ (non-standard). Modern APT maps
# Architectures:any to binary-<native-arch>/ and never fetches binary-any/, so
# apt-cache policy returns nothing even when the repo is reachable. These helpers
# parse the Packages index directly instead of relying on the APT cache.

# Print available rivendell versions, newest first.
_rd_repo_versions() {
    curl -fsSL "${RD_REPO_URL}dists/stable/main/binary-any/Packages" 2>/dev/null \
        | awk '/^Package: rivendell$/{f=1} f && /^Version:/{print $2; f=0}' \
        | sort -rV
}

# Download all rivendell* packages at VERSION and install them with dpkg.
_rd_repo_install() {
    local version="$1"
    msg_info "Fetching package index from repository..."
    local pkg_data
    pkg_data=$(curl -fsSL "${RD_REPO_URL}dists/stable/main/binary-any/Packages" 2>/dev/null)
    if [ -z "$pkg_data" ]; then
        msg_error "Could not fetch package index from ${RD_REPO_URL}"
        return 1
    fi

    # Extract filenames for every package at the requested version
    # (excludes -dev and -dbgsym; includes rivendell, -select, -importers, etc.)
    local filenames
    filenames=$(printf '%s\n' "$pkg_data" | python3 -c "
import sys
stanzas = sys.stdin.read().strip().split('\n\n')
for s in stanzas:
    fields = {}
    for line in s.split('\n'):
        if ': ' in line:
            k, v = line.split(': ', 1)
            fields[k] = v
    pkg = fields.get('Package', '')
    if (fields.get('Version') == '${version}'
            and 'Filename' in fields
            and not pkg.endswith('-dev')
            and not pkg.endswith('-dbgsym')):
        print(fields['Filename'])
")

    if [ -z "$filenames" ]; then
        msg_error "No packages found for version ${version} in the repository."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    local deb_files=()
    while IFS= read -r fname; do
        local bname
        bname=$(basename "$fname")
        if gum spin --title "Downloading ${bname}..." -- \
                curl -fsSL "${RD_REPO_URL}${fname}" -o "${tmpdir}/${bname}"; then
            deb_files+=("${tmpdir}/${bname}")
        else
            msg_warn "Failed to download ${bname} — skipping."
        fi
    done <<< "$filenames"

    if [ ${#deb_files[@]} -eq 0 ]; then
        msg_error "No packages downloaded."
        rm -rf "$tmpdir"
        return 1
    fi

    if _cmd_with_progress "Installing Rivendell ${version}" 20 \
            dpkg -i "${deb_files[@]}"; then
        gum spin --title "Resolving dependencies..." -- \
            apt-get install -f -y 2>/dev/null || true
        msg_success "Rivendell ${version} installed."
    else
        msg_warn "dpkg reported errors — attempting dependency resolution..."
        apt-get install -f -y 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
}

# ── Package installation helper ──────────────────────────────────────────────
# Offers local built .deb files and/or repo versions; user chooses which to use.

_install_rivendell_packages() {
    # Optional: version currently installed (e.g. "4.4.1-1"), so callers doing a
    # reinstall can offer it as an explicit pick alongside "Latest" and the rest
    # of the repo's version list, instead of forcing a re-run through the full list.
    local _cur_ver="${1:-}"

    # Collect locally built packages (debuild writes them to /opt)
    local local_debs local_ver local_label
    local_debs=$(find /opt -maxdepth 1 -name "rivendell*.deb" 2>/dev/null \
                    | grep -v -- '-dbgsym' | sort)

    if [ -n "$local_debs" ]; then
        # Extract version from the main rivendell package (not -dev / -doc etc)
        local main_deb
        main_deb=$(printf '%s\n' "$local_debs" \
                    | grep -v -- '-dev\|-doc\|-data\|-bin\|-utils' | head -1)
        local_ver=$(dpkg-deb --field "$main_deb" Version 2>/dev/null || true)
        local_label="Local packages${local_ver:+ — v${local_ver}} ($(printf '%s\n' "$local_debs" | wc -l) files)"
    fi

    # Collect repo versions directly from the repo index (apt-cache is unreliable
    # for this repo due to its non-standard binary-any/ layout).
    local repo_versions
    repo_versions=$(_rd_repo_versions)

    # Build the menu
    local choices=()
    [ -n "$local_debs" ]    && choices+=("$local_label")
    [ -n "$repo_versions" ] && choices+=("Repository")

    if [ ${#choices[@]} -eq 0 ]; then
        msg_error "No local packages found and no repository version available."
        msg_info "Run 'Build Packages' first, or add the Rivendell repository."
        return 1
    fi

    local install_choice
    if [ ${#choices[@]} -eq 1 ]; then
        install_choice="${choices[0]}"
        msg_info "Install method: $install_choice"
    else
        install_choice=$(printf '%s\n' "${choices[@]}" | gum choose \
            --header "How would you like to install Rivendell?") || return 1
    fi

    case "$install_choice" in
        Local*)
            echo
            msg_info "Packages to install:"
            printf '%s\n' "$local_debs" | while IFS= read -r f; do msg_info "  $f"; done
            echo
            local -a _deb_files
            mapfile -t _deb_files <<< "$local_debs"
            if _cmd_with_progress "Installing local packages" 20 \
                    dpkg -i "${_deb_files[@]}"; then
                gum spin --title "Fixing any missing dependencies..." -- \
                    apt-get install -f -y 2>/dev/null || true
                msg_success "Local packages installed."
            else
                msg_warn "dpkg reported errors — attempting dependency fix..."
                apt-get install -f -y 2>/dev/null || true
            fi
            ;;
        Repository*)
            local latest_ver version_choice pick
            latest_ver=$(printf '%s\n' "$repo_versions" | head -1)
            local -a _menu_lines=("Latest  ($latest_ver)")
            if [ -n "$_cur_ver" ] && [ "$_cur_ver" != "$latest_ver" ]; then
                _menu_lines+=("Currently installed  ($_cur_ver)")
            fi
            local _rest
            _rest=$(printf '%s\n' "$repo_versions" | grep -vx -e "$latest_ver" -e "$_cur_ver")
            pick=$(printf '%s\n' "${_menu_lines[@]}" "$_rest" \
                    | gum choose --header "Select a Rivendell version to install:") || return 1
            case "$pick" in
                Latest*)                version_choice="$latest_ver" ;;
                "Currently installed"*) version_choice="$_cur_ver" ;;
                *)                      version_choice="$pick" ;;
            esac
            _rd_repo_install "$version_choice" || return 1
            ;;
    esac

    _ensure_jackd_installed

    # Restart (not just "start") so a reinstall/upgrade actually picks up the new
    # binaries instead of leaving whatever was already running in place.
    gum spin --title "Starting Rivendell service..." -- \
        systemctl restart "$RD_SERVICE"
    systemctl enable "$RD_SERVICE" >/dev/null 2>&1
}

# ── Installer flow ───────────────────────────────────────────────────────────

run_installer() {
    show_banner

    local os_name kernel_ver
    os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
    kernel_ver=$(uname -r)

    header "Rivendell is not installed — Initial Setup"

    gum style --foreground "$C_MUTED" --padding "0 2" \
        "This wizard will install and configure Rivendell v4." \
        "" \
        "System:  $os_name" \
        "Kernel:  $kernel_ver" \
        "Host:    $(hostname)" \
        "User:    ${SUDO_USER:-$USER}" \
        "" \
        "Steps:" \
        "  1. Add package repositories" \
        "  2. Install dependencies and Rivendell" \
        "  3. Configure the database" \
        "  4. Configure audio storage"
    echo

    show_os_compat_warning

    local installer_choice
    installer_choice=$(gum choose \
        --header "Rivendell is not installed. What would you like to do?" \
        "Install Rivendell" \
        "Skip to admin menu" \
        "Exit") || installer_choice="Exit"

    case "$installer_choice" in
        "Skip to admin menu") run_main_menu; return ;;
        "Exit")               msg_info "Exiting."; exit 0 ;;
    esac

    export DEBIAN_FRONTEND=noninteractive
    export PATH="/sbin:$PATH"

    # ── Step 1: Repositories ─────────────────────────────────────────────────
    header "Step 1 of 4 — Package Repositories"

    if grep -rq "deb http://deb-multimedia.org" /etc/apt/sources.list \
            /etc/apt/sources.list.d/ 2>/dev/null; then
        msg_info "Debian Multimedia repository already configured."
    else
        local _suite
        _suite=$(_deb_suite)
        _cmd_with_progress "Adding Debian Multimedia repository (${_suite})" 30 \
            bash -c "
                cd /tmp
                wget -q '${DEB_MULTIMEDIA_KEYRING_URL}' -O deb-multimedia-keyring.deb
                dpkg -i deb-multimedia-keyring.deb
                rm -f deb-multimedia-keyring.deb
                echo 'deb http://deb-multimedia.org ${_suite} main non-free' >> /etc/apt/sources.list
            "
    fi

    # The older per-architecture repos (rivendell-aarch64/-amd64) publish under
    # binary-any/ (non-standard): omitting arch= lets APT discover binary-any/ from
    # the Release file, while specifying arch=arm64 makes it look for binary-arm64/
    # which doesn't exist there. The newer combined per-release repo (rivendell-trixie)
    # is laid out differently and does want an explicit arch=any — RD_REPO_ARCH_OPT
    # (set in _detect_rd_repo) carries that difference through to the entry below.
    local _rd_entry="deb [${RD_REPO_ARCH_OPT}signed-by=${RD_REPO_KEY_FILE}] ${RD_REPO_URL} stable main"
    if [ -f "$RD_REPO_LIST" ]; then
        # Fix existing files left over from a different repo layout/arch scheme.
        if [ "$(cat "$RD_REPO_LIST" 2>/dev/null)" != "$_rd_entry" ]; then
            msg_info "Updating Rivendell repo entry ($RD_REPO_SLUG)..."
            echo "$_rd_entry" > "$RD_REPO_LIST"
        else
            msg_info "Rivendell repository already configured ($RD_REPO_SLUG)."
        fi
    else
        _cmd_with_progress "Adding Rivendell ${RD_REPO_SLUG} repository" 20 \
            bash -c "
                apt-get install -y -q curl gnupg
                curl -fsSL '${RD_REPO_KEY_URL}' \
                    | gpg --yes --dearmor -o '${RD_REPO_KEY_FILE}'
                echo '${_rd_entry}' > '${RD_REPO_LIST}'
            "
    fi

    _cmd_with_progress "Updating package lists" 20 apt-get update -q
    msg_success "Repositories configured."

    # ── Step 2: Install packages ──────────────────────────────────────────────
    header "Step 2 of 4 — Install Rivendell"

    # Ask the user how/what to install before any long-running work begins.
    # _install_rivendell_packages normally handles this, but we need the user's
    # choice up-front so they can back out without waiting for deps to install.

    # Resolve available options now (repo is freshly updated above).
    local _local_debs _local_ver _local_label _repo_versions
    _local_debs=$(find /opt -maxdepth 1 -name "rivendell*.deb" 2>/dev/null \
                    | grep -v -- '-dbgsym' | sort)
    if [ -n "$_local_debs" ]; then
        local _main_deb
        _main_deb=$(printf '%s\n' "$_local_debs" \
                    | grep -v -- '-dev\|-doc\|-data\|-bin\|-utils' | head -1)
        _local_ver=$(dpkg-deb --field "$_main_deb" Version 2>/dev/null || true)
        _local_label="Local packages${_local_ver:+ — v${_local_ver}} ($(printf '%s\n' "$_local_debs" | wc -l) files)"
    fi
    _repo_versions=$(_rd_repo_versions)

    local _install_method _install_version
    if [ -z "$_local_debs" ] && [ -z "$_repo_versions" ]; then
        msg_error "No local packages found and no repository version available."
        msg_info "Run 'Build Packages' first, or check that the Rivendell repository is reachable."
        exit 1
    fi

    # Build source menu
    local _src_choices=()
    [ -n "$_local_debs" ]    && _src_choices+=("$_local_label")
    [ -n "$_repo_versions" ] && _src_choices+=("Repository")

    if [ ${#_src_choices[@]} -eq 1 ]; then
        _install_method="${_src_choices[0]}"
        msg_info "Install source: $_install_method"
    else
        _install_method=$(printf '%s\n' "${_src_choices[@]}" | gum choose \
            --header "How would you like to install Rivendell?") || exit 0
    fi

    # If repo, pick version now before anything else is installed.
    if [[ "$_install_method" == Repository* ]]; then
        local _latest _pick
        _latest=$(printf '%s\n' "$_repo_versions" | head -1)
        _pick=$(printf 'Latest  (%s)\n%s\n' "$_latest" "$_repo_versions" \
                | gum choose --header "Select a Rivendell version to install:") || exit 0
        if [[ "$_pick" == Latest* ]]; then
            _install_version="$_latest"
        else
            _install_version="$_pick"
        fi
        msg_info "Will install Rivendell ${_install_version} from repository."
    fi
    echo

    _cmd_with_progress "Installing build tools and dependencies" 150 \
        apt-get install -y \
            libtool m4 automake pkg-config make gcc g++ autofs rsync \
            libexpat1-dev libexpat1 libid3-3.8.3-dev libcurl4-gnutls-dev \
            libcoverart-dev libdiscid-dev libmusicbrainz5-dev libcdparanoia-dev \
            libsndfile1-dev libpam0g-dev libvorbis-dev \
            python3 python3-pycurl python3-pymysql python3-serial python3-requests \
            libsamplerate0-dev qtbase5-dev libqt5sql5-mysql libsoundtouch-dev \
            libsystemd-dev libjack-jackd2-dev libasound2-dev \
            libflac-dev libflac++-dev libmp3lame-dev libmad0-dev libtwolame-dev \
            docbook5-xml libxml2-utils docbook-xsl-ns xsltproc fop \
            libltdl-dev autoconf libssl-dev libtag1-dev \
            qttools5-dev-tools debhelper openssh-server autoconf-archive \
            gnupg pbuilder ubuntu-dev-tools apt-file

    if pkg_installed apache2; then
        msg_info "Apache2 already installed."
    else
        _cmd_with_progress "Installing Apache2" 45 apt-get install -y apache2
    fi
    gum spin --title "Configuring Apache2..." -- bash -c "
        a2enmod cgid >/dev/null 2>&1 || true
        ln -sf ../mods-available/cgid.conf /etc/apache2/mods-enabled/cgid.conf 2>/dev/null || true
        ln -sf ../mods-available/cgid.load /etc/apache2/mods-enabled/cgid.load 2>/dev/null || true
        systemctl restart apache2
        systemctl enable apache2 >/dev/null 2>&1
    "

    if pkg_installed mariadb-server; then
        msg_info "MariaDB already installed."
    else
        _cmd_with_progress "Installing MariaDB" 60 apt-get install -y mariadb-server
    fi
    gum spin --title "Starting MariaDB..." -- bash -c "
        systemctl start mariadb
        systemctl enable mariadb >/dev/null 2>&1
    "

    # Install Rivendell using the choice made at the start of this step.
    case "$_install_method" in
        Local*)
            msg_info "Packages to install:"
            printf '%s\n' "$_local_debs" | while IFS= read -r f; do msg_info "  $f"; done
            echo
            local -a _deb_files
            mapfile -t _deb_files <<< "$_local_debs"
            if _cmd_with_progress "Installing local packages" 20 \
                    dpkg -i "${_deb_files[@]}"; then
                gum spin --title "Fixing any missing dependencies..." -- \
                    apt-get install -f -y 2>/dev/null || true
            else
                msg_warn "dpkg reported errors — attempting dependency fix..."
                apt-get install -f -y 2>/dev/null || true
            fi
            ;;
        Repository*)
            _rd_repo_install "$_install_version" || exit 1
            ;;
    esac

    _ensure_jackd_installed

    gum spin --title "Refreshing shared libraries..." -- ldconfig

    if [ ! -f "$RD_CONF" ]; then
        gum spin --title "Downloading default configuration..." -- \
            wget -q -O "$RD_CONF" "$RD_CONF_SAMPLE_URL"
        msg_info "Default rd.conf downloaded."
    else
        msg_info "Existing rd.conf preserved."
    fi
    msg_success "Rivendell installed."

    # ── Step 3: Database ──────────────────────────────────────────────────────
    header "Step 3 of 4 — Database"
    SUMMARY_DB=""
    configure_database_interactive "true"

    # ── Step 4: Audio storage ─────────────────────────────────────────────────
    header "Step 4 of 4 — Audio Storage"
    configure_audio_storage_interactive

    # Start and enable service
    gum spin --title "Starting Rivendell service..." -- \
        systemctl start "$RD_SERVICE"
    systemctl enable "$RD_SERVICE" >/dev/null 2>&1

    # Summary
    echo
    gum style \
        --border double --border-foreground "$C_SUCCESS" \
        --foreground "$C_SUCCESS" --bold \
        --padding "1 4" --margin "1 2" \
        "  Installation Complete!  " \
        "" \
        "$(gum style --foreground "$C_MUTED" "  Database: ${SUMMARY_DB:-see /etc/rd.conf}")" \
        "$(gum style --foreground "$C_MUTED" "  Config:   $RD_CONF")" \
        "$(gum style --foreground "$C_MUTED" "  Service:  systemctl status $RD_SERVICE")"
    echo

    if gum confirm "Reboot now to finalise setup?"; then
        gum spin --title "Rebooting in 3 seconds..." -- sleep 3
        reboot
    else
        run_main_menu
    fi
}

# ── Main menu actions ────────────────────────────────────────────────────────

action_reinstall() {
    header "Reinstall Rivendell"
    local cur_ver
    cur_ver=$(dpkg -s rivendell 2>/dev/null | awk '/^Version:/{print $2}')
    msg_info "Installed version: ${cur_ver:-unknown}"
    echo

    _install_rivendell_packages "$cur_ver"
}

action_uninstall() {
    header "Uninstall Rivendell"

    local cur_ver
    cur_ver=$(dpkg -s rivendell 2>/dev/null | awk '/^Version:/{print $2}')
    if [ -z "$cur_ver" ]; then
        msg_warn "Rivendell does not appear to be installed."
        return 0
    fi
    msg_info "Installed version: $cur_ver"
    echo

    # Capture DB details now, before anything is removed — needed below if the
    # user opts to also drop the database, and rd.conf may get deleted first.
    local db_host db_name
    db_host=$(rdconf_get "mySQL" "Hostname"); [ -z "$db_host" ] && db_host="localhost"
    db_name=$(rdconf_get "mySQL" "Database"); [ -z "$db_name" ] && db_name="Rivendell"

    gum style --foreground "$C_WARN" --bold \
        "This removes the Rivendell packages from this system." \
        "The database and audio store are left in place unless you opt in below."
    echo

    gum confirm "Remove Rivendell packages?" || { msg_info "Cancelled."; return 0; }

    local pkgs
    pkgs=$(dpkg -l 'rivendell*' 2>/dev/null | awk '/^[hi]i/{print $2}')
    if [ -z "$pkgs" ]; then
        msg_warn "No Rivendell packages appear to be installed."
        return 0
    fi

    gum style --foreground "$C_ACCENT" --bold "Packages to remove:"
    printf '%s\n' "$pkgs" | while IFS= read -r p; do msg_info "  $p"; done
    echo

    local purge_choice
    purge_choice=$(gum choose \
        --header "Remove packages, or also purge $RD_CONF?" \
        "Remove packages (keep $RD_CONF)" \
        "Remove packages and $RD_CONF") || return 0

    gum spin --title "Stopping $RD_SERVICE..." -- \
        systemctl stop "$RD_SERVICE" 2>/dev/null || true
    systemctl disable "$RD_SERVICE" >/dev/null 2>&1 || true

    local -a _pkg_arr
    mapfile -t _pkg_arr <<< "$pkgs"

    local apt_action="remove"
    [[ "$purge_choice" == *"$RD_CONF"* ]] && apt_action="purge"

    if ! _cmd_with_progress "Removing Rivendell packages" 30 \
            apt-get "$apt_action" -y "${_pkg_arr[@]}"; then
        msg_error "Package removal reported errors — check output above."
        return 1
    fi
    msg_success "Rivendell packages removed."

    if [ "$apt_action" = "purge" ] && [ -f "$RD_CONF" ]; then
        rm -f "$RD_CONF"
        msg_info "Removed $RD_CONF"
    fi

    echo
    if [ "$db_host" = "localhost" ] || [ "$db_host" = "127.0.0.1" ]; then
        if gum confirm --default=false \
                "Also drop the local '${db_name}' database? This permanently deletes all carts, logs and audio metadata."; then
            if gum spin --title "Dropping database ${db_name}..." -- \
                    mysql -e "DROP DATABASE IF EXISTS \`${db_name}\`;"; then
                msg_success "Database '${db_name}' dropped."
            else
                msg_error "Failed to drop database — is MariaDB running and accessible as root?"
            fi
        else
            msg_info "Database '${db_name}' left in place."
        fi
    else
        msg_info "Database is remote (${db_host}) — not touched. Drop it manually on that server if desired."
    fi

    echo
    msg_warn "Audio store ($RD_DEFAULT_AUDIO_DIR) was left untouched — remove or unmount it manually if desired."
}

action_upgrade() {
    header "Upgrade Rivendell"
    local cur_ver
    cur_ver=$(dpkg -s rivendell 2>/dev/null | awk '/^Version:/{print $2}')
    msg_info "Installed version: ${cur_ver:-unknown}"
    echo

    gum confirm "Run apt-get update and upgrade Rivendell?" || return 0

    export DEBIAN_FRONTEND=noninteractive
    _cmd_with_progress "Updating package lists" 20 apt-get update
    _cmd_with_progress "Upgrading Rivendell" 60 apt-get install --only-upgrade -y rivendell
    _ensure_jackd_installed

    local new_ver
    new_ver=$(dpkg -s rivendell 2>/dev/null | awk '/^Version:/{print $2}')
    if [ "$new_ver" = "$cur_ver" ]; then
        msg_info "Already at latest version ($new_ver)."
    else
        msg_success "Upgraded: $cur_ver → $new_ver"
    fi
}

action_restart_service() {
    header "Restart Rivendell Service"
    local status
    status=$(systemctl is-active "$RD_SERVICE" 2>/dev/null || echo "unknown")
    msg_info "Current status: $status"
    echo

    gum confirm "Restart the '$RD_SERVICE' service?" || return 0

    if gum spin --title "Restarting $RD_SERVICE..." -- \
            systemctl restart "$RD_SERVICE"; then
        msg_success "Rivendell restarted successfully."
    else
        msg_error "Restart failed."
        echo
        gum style --foreground "$C_WARN" "Recent journal entries:"
        journalctl -u "$RD_SERVICE" -n 20 --no-pager 2>/dev/null || true
    fi
}

action_hold_packages() {
    header "Hold / Unhold Rivendell Packages"

    # Find all installed rivendell-* packages
    local pkgs
    pkgs=$(dpkg -l 'rivendell*' 2>/dev/null | awk '/^ii/{print $2}')

    if [ -z "$pkgs" ]; then
        msg_warn "No Rivendell packages found."
        return 0
    fi

    # Show current hold state for each package
    local held
    held=$(apt-mark showhold 2>/dev/null)

    gum style --foreground "$C_ACCENT" --bold "Installed Rivendell packages:"
    echo "$pkgs" | while IFS= read -r pkg; do
        if echo "$held" | grep -qx "$pkg"; then
            gum style --foreground "$C_WARN" "  ⊘  $pkg  (held)"
        else
            gum style --foreground "$C_MUTED" "  ○  $pkg"
        fi
    done
    echo

    local action
    action=$(gum choose \
        --header "What would you like to do?" \
        "Hold packages (prevent upgrades)" \
        "Unhold packages (allow upgrades)") || return 0

    case "$action" in
        "Hold packages (prevent upgrades)")
            gum confirm "Hold all Rivendell packages? apt will not upgrade them automatically." || return 0
            # shellcheck disable=SC2086
            if apt-mark hold $pkgs; then
                msg_success "Packages held: $pkgs"
            else
                msg_error "apt-mark hold failed."
            fi
            ;;
        "Unhold packages (allow upgrades)")
            gum confirm "Unhold all Rivendell packages? They will be included in future upgrades." || return 0
            # shellcheck disable=SC2086
            if apt-mark unhold $pkgs; then
                msg_success "Packages unheld: $pkgs"
            else
                msg_error "apt-mark unhold failed."
            fi
            ;;
    esac
}

# Runs any command in the background and draws a timed fake progress bar.
# Args: label estimate_seconds command [args...]
# Caps at 90% until the command exits, then snaps to 100% (or shows failure).
_cmd_with_progress() {
    local label="${1:-Working}" estimate="${2:-60}"
    shift 2
    local logfile width=40 start elapsed pct filled empty
    local bar_filled bar_empty elapsed_fmt
    logfile=$(mktemp /tmp/rd-prog-XXXXXX.log)

    "$@" >"$logfile" 2>&1 &
    local pid=$!
    start=$(date +%s)

    command -v tput >/dev/null 2>&1 && tput civis
    printf '\n'

    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start ))
        pct=$(( elapsed * 90 / estimate ))
        [ "$pct" -gt 90 ] && pct=90
        filled=$(( pct * width / 100 ))
        empty=$(( width - filled ))

        bar_filled="" bar_empty=""
        local i
        for ((i=0; i<filled; i++)); do bar_filled+="█"; done
        for ((i=0; i<empty; i++)); do bar_empty+="░"; done

        elapsed_fmt=$(printf '%02d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))
        printf '\r  \033[38;2;125;207;255m[\033[38;2;80;250;123m%s\033[38;2;136;136;136m%s\033[38;2;125;207;255m]\033[0m %3d%%  %s  \033[38;2;136;136;136m%s\033[0m   ' \
            "$bar_filled" "$bar_empty" "$pct" "$label" "$elapsed_fmt"
        sleep 2
    done

    wait "$pid"; local rc=$?
    command -v tput >/dev/null 2>&1 && tput cnorm

    elapsed=$(( $(date +%s) - start ))
    elapsed_fmt=$(printf '%02d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))

    local full_bar=""
    for ((i=0; i<width; i++)); do full_bar+="█"; done

    if [ "$rc" -eq 0 ]; then
        printf '\r\033[2K  \033[38;2;125;207;255m[\033[38;2;80;250;123m%s\033[38;2;125;207;255m]\033[0m 100%%  %s  \033[38;2;136;136;136m%s\033[0m\n\n' \
            "$full_bar" "$label" "$elapsed_fmt"
        rm -f "$logfile"
    else
        printf '\r\033[2K  \033[38;2;255;85;85m✗  %s\033[0m  \033[38;2;136;136;136m%s\033[0m\n\n' \
            "$label" "$elapsed_fmt"
        msg_error "Last 20 lines of output:"
        tail -20 "$logfile"
        echo
        rm -f "$logfile"
    fi

    return "$rc"
}

# Runs `make` in the background and draws a timed fake progress bar.
# Caps at 90% until make exits, then snaps to 100% (or shows failure).
# Estimate defaults to 2700 s (45 min) — adjust for faster hardware.
_make_with_progress() {
    local jobs="${1:-1}" release="${2:-Rivendell}" estimate="${3:-2700}"
    local logfile width=40 start elapsed pct filled empty
    local bar_filled bar_empty elapsed_fmt
    logfile=$(mktemp /tmp/rd-make-XXXXXX.log)

    make -j"$jobs" >"$logfile" 2>&1 &
    local pid=$!
    start=$(date +%s)

    command -v tput >/dev/null 2>&1 && tput civis  # hide cursor
    printf '\n'

    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start ))
        pct=$(( elapsed * 90 / estimate ))
        [ "$pct" -gt 90 ] && pct=90
        filled=$(( pct * width / 100 ))
        empty=$(( width - filled ))

        bar_filled="" bar_empty=""
        local i
        for ((i=0; i<filled; i++)); do bar_filled+="█"; done
        for ((i=0; i<empty; i++)); do bar_empty+="░"; done

        elapsed_fmt=$(printf '%02d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))
        printf '\r  \033[38;2;125;207;255m[\033[38;2;80;250;123m%s\033[38;2;136;136;136m%s\033[38;2;125;207;255m]\033[0m %3d%%  Compiling %s  \033[38;2;136;136;136m%s\033[0m   ' \
            "$bar_filled" "$bar_empty" "$pct" "$release" "$elapsed_fmt"
        sleep 4
    done

    wait "$pid"; local rc=$?
    command -v tput >/dev/null 2>&1 && tput cnorm  # restore cursor

    elapsed=$(( $(date +%s) - start ))
    elapsed_fmt=$(printf '%02d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))

    local full_bar=""
    for ((i=0; i<width; i++)); do full_bar+="█"; done

    if [ "$rc" -eq 0 ]; then
        printf '\r\033[2K  \033[38;2;125;207;255m[\033[38;2;80;250;123m%s\033[38;2;125;207;255m]\033[0m 100%%  Compiling %s  \033[38;2;136;136;136m%s\033[0m\n\n' \
            "$full_bar" "$release" "$elapsed_fmt"
        rm -f "$logfile"
    else
        printf '\r\033[2K  \033[38;2;255;85;85m✗ Build failed\033[0m  %s  \033[38;2;136;136;136m%s\033[0m\n\n' \
            "$release" "$elapsed_fmt"
        msg_error "Compile errors:"
        grep -E "error:" "$logfile" | grep -v "^In file\|^  " | head -20
        echo
        msg_error "Last 20 lines of make output:"
        tail -20 "$logfile"
        rm -f "$logfile"
    fi

    return "$rc"
}

action_build_packages() {
    header "Build Rivendell Packages"

    export DEBIAN_FRONTEND=noninteractive
    export PATH="/sbin:$PATH"
    export DOCBOOK_STYLESHEETS=/usr/share/xml/docbook/stylesheet/docbook-xsl-ns

    local debian_ver is_deb13=false
    debian_ver=$(grep ^VERSION_ID /etc/os-release 2>/dev/null | tr -d '"' | cut -d= -f2)
    [ "${debian_ver:-0}" -ge 13 ] 2>/dev/null && is_deb13=true

    if $is_deb13; then
        msg_warn "Debian ${debian_ver} detected — ImageMagick 7 build fixes will be applied."
        echo
    fi

    # ── Step 1: Select release & build method ─────────────────────────────────

    gum style --foreground "$C_ACCENT" --bold "Step 1 — Select Release"
    echo

    msg_info "Fetching release list from GitHub..."
    local tags_json
    tags_json=$(curl -fsSL "https://api.github.com/repos/ElvishArtisan/rivendell/tags" 2>/dev/null)
    if [ -z "$tags_json" ]; then
        msg_error "Could not fetch release list — check network connection."
        return 1
    fi

    local release_choice
    release_choice=$(gum choose \
        --header "Which release would you like to build?" \
        "Latest (auto-detect)" \
        "Choose from list") || return 0

    local release_name
    if [ "$release_choice" = "Latest (auto-detect)" ]; then
        release_name=$(printf '%s' "$tags_json" | jq -r '.[0].name')
        msg_info "Latest release: $release_name"
    else
        local tag_list
        tag_list=$(printf '%s' "$tags_json" | jq -r '.[].name')
        release_name=$(printf '%s\n' "$tag_list" | gum choose \
            --header "Select a Rivendell release:") || return 0
    fi

    [ -z "$release_name" ] && { msg_error "No release selected."; return 1; }
    echo

    local build_method
    build_method=$(gum choose \
        --header "Build method:" \
        "debuild  — compile here, package instantly (local use / testing)" \
        "pdebuild — clean chroot, full rebuild (use when uploading to repo)") || return 0
    echo

    local use_pdebuild=false
    [[ "$build_method" == pdebuild* ]] && use_pdebuild=true

    if $use_pdebuild; then
        gum style \
            --border normal --border-foreground "$C_WARN" \
            --foreground "$C_WARN" \
            --padding "0 2" \
            "⚠  Building Rivendell $release_name (pdebuild)" \
            "" \
            "pdebuild builds a clean reproducible package inside a pbuilder chroot." \
            "It does not use any locally compiled objects — everything is rebuilt" \
            "from scratch inside the chroot. On a Raspberry Pi this takes 3–4 hours." \
            "Do not close this terminal or power off the system during the build."
    else
        gum style \
            --border normal --border-foreground "$C_WARN" \
            --foreground "$C_WARN" \
            --padding "0 2" \
            "⚠  Building Rivendell $release_name (debuild)" \
            "" \
            "This will compile Rivendell on this machine and package it with debuild." \
            "Packaging reuses the compiled objects, so it finishes in seconds after" \
            "the initial compile. On a Raspberry Pi the compile takes ~45–60 minutes."
    fi
    echo

    gum confirm "Start build?" || return 0

    # ── Step 2: Build dependencies ────────────────────────────────────────────

    gum style --foreground "$C_ACCENT" --bold "Step 2 — Build Dependencies"
    echo

    local _suite
    _suite=$(_deb_suite)

    if grep -rq "deb http://deb-multimedia.org" /etc/apt/sources.list \
            /etc/apt/sources.list.d/ 2>/dev/null; then
        if ! grep -rq "deb http://deb-multimedia.org ${_suite}" /etc/apt/sources.list \
                /etc/apt/sources.list.d/ 2>/dev/null; then
            msg_warn "deb-multimedia repo is configured for a different suite — updating to ${_suite}."
            sed -i "s|deb http://deb-multimedia.org [a-z]* main|deb http://deb-multimedia.org ${_suite} main|g" \
                /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
        else
            msg_info "Debian Multimedia repository (${_suite}) already configured."
        fi
    else
        _cmd_with_progress "Adding Debian Multimedia repository (${_suite})" 30 \
            bash -c "
                cd /tmp
                wget -q '${DEB_MULTIMEDIA_KEYRING_URL}' -O deb-multimedia-keyring.deb
                dpkg -i deb-multimedia-keyring.deb
                rm -f deb-multimedia-keyring.deb
                echo 'deb http://deb-multimedia.org ${_suite} main non-free' >> /etc/apt/sources.list
            "
    fi

    _cmd_with_progress "Updating package lists" 20 apt-get update -q

    local qt5webkit_available=false
    if apt-cache show libqt5webkit5-dev >/dev/null 2>&1; then
        qt5webkit_available=true
        msg_info "libqt5webkit5-dev available — will install."
    else
        msg_info "libqt5webkit5-dev not available — QWebView include will be patched out."
    fi

    local build_pkgs="rsync apache2 build-essential \
        libexpat1-dev libexpat1 libid3-3.8.3-dev libcurl4-gnutls-dev \
        libcoverart-dev libdiscid-dev libmusicbrainz5-dev libcdparanoia-dev \
        libsndfile1-dev libpam0g-dev libvorbis-dev \
        python3 python3-pycurl python3-pymysql python3-serial python3-requests \
        libsamplerate0-dev qtbase5-dev libqt5sql5-mysql libsoundtouch-dev \
        libsystemd-dev libjack-jackd2-dev libasound2-dev \
        libflac-dev libflac++-dev libmp3lame-dev libmad0-dev libtwolame-dev \
        docbook5-xml libxml2-utils docbook-xsl-ns xsltproc fop \
        make g++ libltdl-dev autoconf automake libssl-dev libtag1-dev \
        qttools5-dev-tools debhelper openssh-server autoconf-archive \
        gnupg pbuilder ubuntu-dev-tools apt-file jq \
        libmp4v2-dev libfaad-dev"

    if $qt5webkit_available; then
        build_pkgs="$build_pkgs libqt5webkit5-dev"
    fi

    if $is_deb13; then
        build_pkgs="$build_pkgs libmagickwand-7.q16-dev libmagick++-7.q16-dev"
    else
        build_pkgs="$build_pkgs libmagick++-dev"
    fi

    # shellcheck disable=SC2086
    if ! _cmd_with_progress "Installing build dependencies" 240 \
            bash -c "apt-get install -y $build_pkgs"; then
        msg_error "Dependency installation failed."
        return 1
    fi
    msg_success "Build dependencies ready."
    echo

    # ── Step 3: Download & extract ────────────────────────────────────────────

    gum style --foreground "$C_ACCENT" --bold "Step 3 — Source"
    echo

    local src_dir="/opt/rivendell-${release_name}"
    local tarball="/opt/${release_name}.tar.gz"

    if [ -d "$src_dir" ]; then
        if $use_pdebuild; then
            # pdebuild requires a clean source tree — reused trees may contain
            # Makefile.in files or other autogen artifacts from a prior debuild
            # run that confuse dpkg-source. Always re-extract (tarball is kept).
            msg_info "Re-extracting source for a clean pdebuild run..."
            rm -rf "$src_dir"
        elif gum confirm "Source directory $src_dir already exists — re-use it (skip download)?"; then
            msg_info "Re-using existing source tree."
        else
            rm -rf "$src_dir" "$tarball"
        fi
    fi

    if [ ! -f "$tarball" ]; then
        if ! gum spin --title "Downloading Rivendell ${release_name}..." --show-output -- \
                curl -fL \
                    "https://github.com/ElvishArtisan/rivendell/archive/${release_name}.tar.gz" \
                    -o "$tarball"; then
            msg_error "Download failed."
            return 1
        fi
    fi

    if [ ! -d "$src_dir" ]; then
        mkdir -p "$src_dir"
        gum spin --title "Extracting source..." -- \
            tar -xf "$tarball" -C "$src_dir" --strip-components=1
        msg_success "Source ready at $src_dir"
    fi
    echo

    # ── Step 4: Prepare source ────────────────────────────────────────────────
    # Applies patches and runs autogen.sh. For debuild, also runs configure.
    # For pdebuild, configure runs inside the chroot — skipped here.

    gum style --foreground "$C_ACCENT" --bold "Step 4 — Prepare Source"
    echo

    local orig_dir
    orig_dir=$(pwd)
    cd "$src_dir"

    # Qt5WebKitWidgets was removed from Debian 11+ and is not used by Rivendell v4.
    if grep -q "Qt5WebKitWidgets" configure.ac 2>/dev/null; then
        msg_info "Patching configure.ac: removing obsolete Qt5WebKitWidgets dependency..."
        sed -i 's/ Qt5WebKitWidgets//g; s/Qt5WebKitWidgets //g; s/Qt5WebKitWidgets//g' \
            configure.ac
    fi

    # Apply upstream PR #1019: nested IM7→IM6 fallback in configure.ac.
    if grep -qF "PKG_CHECK_MODULES(IMAGEMAGICK,Magick++-6.Q16" configure.ac 2>/dev/null && \
       ! grep -qF "Magick++-7.Q16" configure.ac 2>/dev/null; then
        msg_info "Patching configure.ac: dual ImageMagick 6/7 support (upstream PR #1019)..."
        local _impatch
        _impatch=$(mktemp)
        cat > "$_impatch" << 'PYEOF'
import sys
with open('configure.ac') as f:
    txt = f.read()
OLD = ("PKG_CHECK_MODULES(IMAGEMAGICK,Magick++-6.Q16,"
       "[],[AC_MSG_ERROR([*** ImageMagick 6 Magick++ binding not found ***])])")
NEW = ("PKG_CHECK_MODULES(IMAGEMAGICK,Magick++-7.Q16,[],[\n"
       "  PKG_CHECK_MODULES(IMAGEMAGICK,Magick++-6.Q16,"
       "[],[AC_MSG_ERROR([*** ImageMagick 6/7 Magick++ binding not found ***])])\n"
       "])")
if OLD in txt:
    with open('configure.ac', 'w') as f:
        f.write(txt.replace(OLD, NEW))
else:
    print("configure.ac: ImageMagick check line not found — patch skipped", file=sys.stderr)
    sys.exit(1)
PYEOF
        python3 "$_impatch" || msg_warn "ImageMagick PR #1019 patch not applied — build may fail on Trixie."
        rm -f "$_impatch"
    fi

    if ! $qt5webkit_available; then
        if grep -q "QWebView" rdairplay/topstrip.h 2>/dev/null; then
            msg_info "Patching rdairplay/topstrip.h: removing dead QWebView include..."
            sed -i '/#include <QWebView>/d' rdairplay/topstrip.h
        fi

        if grep -q "QWebView" rdairplay/messagewidget.h 2>/dev/null; then
            msg_info "Patching rdairplay/messagewidget: replacing QWebView with QTextBrowser..."
            local _mwpatch
            _mwpatch=$(mktemp)
            cat > "$_mwpatch" << 'PYEOF'
import re, sys

# messagewidget.h
with open('rdairplay/messagewidget.h') as f:
    h = f.read()
h = h.replace('#include <QWebView>', '#include <QTextBrowser>')
h = h.replace('QWebView *d_view;', 'QTextBrowser *d_view;')
with open('rdairplay/messagewidget.h', 'w') as f:
    f.write(h)

# messagewidget.cpp
with open('rdairplay/messagewidget.cpp') as f:
    c = f.read()
c = c.replace('#include <QWebFrame>\n', '')
c = re.sub(
    r'd_view\s*=\s*new\s+QWebView\(this\);\s*'
    r'connect\(d_view,\s*SIGNAL\(loadFinished\(bool\)\),\s*'
    r'this,\s*SLOT\(webLoadFinishedData\(bool\)\)\);\s*'
    r'd_view->hide\(\);',
    ('d_view=new QTextBrowser(this);\n'
     '  d_view->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);\n'
     '  d_view->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);\n'
     '  d_view->setOpenLinks(false);\n'
     '  d_view->hide();'),
    c
)
c = c.replace('d_view->load(url);', 'd_view->setSource(url);')
c = c.replace('d_view->load(d_url);', 'd_view->setSource(QUrl(d_url));')
c = re.sub(
    r'void\s+MessageWidget::webLoadFinishedData\(bool\s+state\)\s*\{[^}]*\}',
    ('void MessageWidget::webLoadFinishedData(bool state)\n'
     '{\n'
     '  // scroll bar policies set in constructor (QTextBrowser).\n'
     '}'),
    c, flags=re.DOTALL
)
with open('rdairplay/messagewidget.cpp', 'w') as f:
    f.write(c)
PYEOF
            python3 "$_mwpatch" || msg_warn "messagewidget patch failed — build may fail."
            rm -f "$_mwpatch"
        fi
    fi

    # Upstream debian/control.src has no Rules-Requires-Root. Modern dpkg-buildpackage
    # defaults that to "no" (rootless build) and, for rootless builds, skips invoking a
    # separate "debian/rules build" step — it assumes dh folds configure+build into the
    # same invocation as binary. This package's debian/rules is old-style (independent
    # build: and binary: targets, binary: doesn't depend on build), so nothing ever gets
    # compiled and packaging fails with "librivwebcapi.so.* not found" (or similar, for
    # whichever file binary: happens to mv first). Restoring the legacy root-build
    # behavior makes dpkg-buildpackage call "debian/rules build" before "binary" again.
    if ! grep -q "^Rules-Requires-Root:" debian/control.src 2>/dev/null; then
        msg_info "Patching debian/control.src: adding Rules-Requires-Root (fixes 'librivwebcapi.so.* not found')..."
        sed -i '/^Standards-Version:/a Rules-Requires-Root: binary-targets' debian/control.src
    fi

    # Upstream debian/control.src's Build-Depends only lists debhelper-compat and
    # autotools-dev — none of the actual dev libraries configure.ac probes for via
    # PKG_CHECK_MODULES/AC_CHECK_HEADER (Qt5, sndfile, samplerate, taglib, curl, PAM,
    # ImageMagick, JACK, ALSA, the docbook toolchain, etc — see $build_pkgs above).
    # debuild never noticed because Step 2 already installed all of those on the host.
    # pdebuild's pbuilder chroot only installs what Build-Depends declares, so autoreconf
    # can't even find pkg-config, and configure fails outright once it does. Filling in
    # the real Build-Depends list is also what makes the package genuinely reproducible
    # from a clean chroot, which is the whole point of using pdebuild for the repo.
    if ! grep -q "pkg-config" debian/control.src 2>/dev/null; then
        msg_info "Patching debian/control.src: filling in Build-Depends (pdebuild's clean chroot needs these declared, not just installed on the host)..."
        python3 - debian/control.src << 'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    txt = f.read()
OLD = "Build-Depends: debhelper-compat (= 12), autotools-dev @HPKLINUX_DEP@\n"
NEW = """Build-Depends: debhelper-compat (= 12),
 autotools-dev,
 pkg-config,
 rsync,
 autoconf-archive,
 libltdl-dev,
 qtbase5-dev,
 qttools5-dev-tools,
 libqt5sql5-mysql,
 libexpat1-dev,
 libssl-dev,
 libsamplerate0-dev,
 libsndfile1-dev,
 libvorbis-dev,
 libcdparanoia-dev,
 libdiscid-dev,
 libmusicbrainz5-dev,
 libcoverart-dev,
 libid3-3.8.3-dev,
 libtag1-dev,
 libcurl4-gnutls-dev,
 libpam0g-dev,
 libsoundtouch-dev,
 libmagick++-dev | libmagick++-6.q16-dev | libmagick++-7.q16-dev,
 libflac-dev,
 libflac++-dev,
 libmad0-dev,
 libtwolame-dev,
 libmp3lame-dev,
 libmp4v2-dev,
 libfaad-dev,
 libjack-jackd2-dev,
 libasound2-dev,
 libsystemd-dev,
 docbook5-xml,
 docbook-xsl-ns,
 xsltproc,
 fop,
 libxml2-utils @HPKLINUX_DEP@
"""
if OLD not in txt:
    print("debian/control.src: Build-Depends line not in the expected form — skipping", file=sys.stderr)
    sys.exit(1)
with open(path, 'w') as f:
    f.write(txt.replace(OLD, NEW))
PYEOF
        if [ $? -ne 0 ]; then
            msg_warn "Build-Depends patch not applied — pdebuild may fail with missing dev packages."
        fi
    fi

    # debian/rules.src's ./configure call never sets DOCBOOK_STYLESHEETS. configure.ac
    # only creates the helpers/docbook symlink that docs/opsguide (and docs/rivwebcapi,
    # manpages, dtds, apis) depend on for xsltproc/fop when that var is non-empty, so
    # without it the opsguide.pdf/HTML/man page build fails outright. The debuild path
    # gets away with it because Step 1 exports DOCBOOK_STYLESHEETS in this same shell —
    # but pdebuild's ./configure runs inside a fresh dpkg-buildpackage process in the
    # chroot, which doesn't inherit this script's exported host environment at all.
    if ! grep -q "DOCBOOK_STYLESHEETS" debian/rules.src 2>/dev/null; then
        msg_info "Patching debian/rules.src: passing DOCBOOK_STYLESHEETS to configure (fixes opsguide.pdf/docs build failing under pdebuild)..."
        sed -i 's|\(MUSICBRAINZ_LIBS="-ldiscid -lmusicbrainz5cc -lcoverartcc"\)|\1 DOCBOOK_STYLESHEETS=/usr/share/xml/docbook/stylesheet/docbook-xsl-ns|' \
            debian/rules.src
    fi

    # autogen.sh must run for both paths: it processes debian/changelog.src,
    # debian/control.src, and debian/rules.src into the real packaging files.
    # The autotools symlinks it also creates (config.guess etc.) are excluded
    # from the source package via extend-diff-ignore; dh_autoreconf regenerates
    # them inside the chroot anyway.
    if ! gum spin --title "Running autogen.sh..." --show-output -- ./autogen.sh; then
        msg_error "autogen.sh failed."
        cd "$orig_dir"; return 1
    fi
    # autogen.sh generates debian/rules from rules.src without the execute bit.
    chmod +x debian/rules 2>/dev/null || true

    if $use_pdebuild; then
        msg_success "Source prepared. pdebuild will configure and compile inside the chroot."
        echo
    else
        # ── debuild path: configure then compile on this machine ──────────────

        local rdxport_debug_flag=""
        if gum confirm --default=false "Enable rdxport debug mode? (adds verbose runtime logging — not recommended for production)"; then
            rdxport_debug_flag="--enable-rdxport-debug"
            msg_info "rdxport debug mode enabled."
        else
            msg_info "rdxport debug mode off."
        fi
        echo

        local configure_cmd="./configure \
            --prefix=/usr \
            --libdir=/usr/lib \
            --libexecdir=/var/www/rd-bin \
            --sysconfdir=/etc/apache2/conf-enabled \
            ${rdxport_debug_flag} \
            MUSICBRAINZ_LIBS='-ldiscid -lmusicbrainz5cc -lcoverartcc'"

        if $is_deb13; then
            local im_cflags im_libs
            im_cflags=$(pkg-config --cflags MagickWand-7.Q16 2>/dev/null || true)
            im_libs=$(pkg-config --libs   MagickWand-7.Q16 2>/dev/null || true)
            if [ -n "$im_cflags" ]; then
                configure_cmd="$configure_cmd \
                    MAGICKWAND_CFLAGS='${im_cflags}' \
                    MAGICKWAND_LIBS='${im_libs}'"
                msg_info "ImageMagick 7 flags: $im_cflags"
            else
                msg_warn "pkg-config MagickWand-7.Q16 not found — configure may fail."
            fi
        fi

        if ! gum spin --title "Running configure..." --show-output -- bash -c "$configure_cmd"; then
            msg_error "Configure failed — check output above."
            cd "$orig_dir"; return 1
        fi
        msg_success "Configure complete."
        echo

        # ── Step 5: Compile ───────────────────────────────────────────────────

        gum style --foreground "$C_ACCENT" --bold "Step 5 — Compile"
        echo

        local jobs
        jobs=$(nproc)
        msg_info "Compiling with $jobs parallel jobs..."

        if ! _make_with_progress "$jobs" "$release_name" 2700; then
            msg_error "Compilation failed — see output above."
            cd "$orig_dir"; return 1
        fi
        msg_success "Compilation complete."
    fi

    # ── Step 5 (pdebuild) / Step 6 (debuild): Package ─────────────────────────

    local pkg_step; $use_pdebuild && pkg_step="Step 5" || pkg_step="Step 6"
    gum style --foreground "$C_ACCENT" --bold "${pkg_step} — Package"
    echo

    if $use_pdebuild; then
        # pbuilder defaults to bootstrapping "sid" (unstable) when DISTRIBUTION is
        # unset. That's a bad match for a package meant to go into a stable repo —
        # sid's contents shift daily, so a "reproducible" build against it isn't
        # reproducible at all, and Rivendell's Build-Depends aren't guaranteed to
        # be installable there anyway. Pin the chroot to the same suite as this
        # host instead (the one debuild/apt already build+test against).
        #
        # libmp4v2-dev has never shipped in official Debian (patent concerns around
        # AAC) — it only exists via deb-multimedia.org, same as the host-side install
        # in Step 2. That repo isn't in pbuilder's chroot by default, so add it via
        # OTHERMIRROR. [trusted=yes] skips GPG verification for just this one repo,
        # since importing the deb-multimedia keyring into an ephemeral chroot before
        # apt can trust it is a bootstrapping headache; it's only relied on for one
        # narrowly-scoped runtime library here. Swap this for a proper keyring import
        # if that trust tradeoff is a problem for your repo's build environment.
        local _pb_suite
        _pb_suite=$(_deb_suite)
        [ -z "$_pb_suite" ] && _pb_suite="trixie"

        cat <<PBEOF | tee /etc/pbuilderrc /root/.pbuilderrc >/dev/null
MIRRORSITE="http://deb.debian.org/debian"
DISTRIBUTION="${_pb_suite}"
COMPONENTS="main contrib non-free non-free-firmware"
OTHERMIRROR="deb [trusted=yes] http://www.deb-multimedia.org ${_pb_suite} main non-free"
BUILDRESULT="/opt"
PBEOF

        if [ -f /var/cache/pbuilder/base.tgz ] \
                && ! tar -xOzf /var/cache/pbuilder/base.tgz ./etc/apt/sources.list 2>/dev/null \
                    | grep -q "deb-multimedia.org ${_pb_suite}"; then
            msg_info "Existing pbuilder base targets the wrong suite or is missing deb-multimedia (needed for libmp4v2-dev) — rebuilding it."
            rm -f /var/cache/pbuilder/base.tgz
        fi

        local pkg_ver="${release_name#v}"
        local orig_tarball="/opt/rivendell_${pkg_ver}.orig.tar.gz"
        if [ ! -f "$orig_tarball" ] && [ -f "/opt/${release_name}.tar.gz" ]; then
            msg_info "Creating orig tarball for Debian packaging..."
            cp "/opt/${release_name}.tar.gz" "$orig_tarball"
        fi

        # Tell dpkg-source to ignore files that cannot be represented as quilt patches:
        #   docs/      — HTML/PDF regenerated by xsltproc/fop (binary or no-final-newline)
        #   autogen files — symlinks to host automake paths created by autogen.sh;
        #                   present when the tree is dirty from a prior debuild run.
        # All of these are regenerated inside the chroot by debian/rules anyway.
        mkdir -p debian/source
        cat > debian/source/options << 'DPKGOPTS'
extend-diff-ignore = "^(docs/|m4/|config\.(guess|sub)|depcomp|compile|missing|install-sh|py-compile|ltmain\.sh|aclocal\.m4|configure$|Makefile\.in$)"
auto-commit
DPKGOPTS

        if [ ! -f /var/cache/pbuilder/base.tgz ]; then
            msg_info "No pbuilder base environment found — creating one now."
            msg_info "This downloads a minimal Debian ${_pb_suite} system + deb-multimedia and normally only needs to happen once (it's rebuilt automatically if the suite/mirror config above ever changes)."
            echo
            if ! _cmd_with_progress "Creating pbuilder base environment" 600 \
                    pbuilder create; then
                msg_error "pbuilder create failed — check output above."
                cd "$orig_dir"; return 1
            fi
            msg_success "pbuilder base environment ready."
            echo
        fi

        if ! gum spin --title "Running pdebuild (this will take several hours)..." --show-output -- \
                pdebuild --debbuildopts "-us -uc"; then
            msg_error "pdebuild failed — check output above."
            cd "$orig_dir"; return 1
        fi
    else
        if ! gum spin --title "Running debuild..." --show-output -- \
                debuild -us -uc -nc -b; then
            msg_error "debuild failed — check output above."
            cd "$orig_dir"; return 1
        fi
    fi

    cd "$orig_dir"

    local debs
    debs=$(find /opt -maxdepth 1 -name "rivendell*.deb" 2>/dev/null | grep -v -- '-dbgsym' | sort)
    echo
    if [ -n "$debs" ]; then
        msg_success "Packages built:"
        printf '%s\n' "$debs" | while IFS= read -r deb; do msg_info "  $deb"; done
        echo
        if gum confirm "Install packages now?"; then
            _install_rivendell_packages
        fi
    else
        msg_warn "No rivendell*.deb files found in /opt — check build output."
    fi
}

action_db_repair() {
    header "Database Repair / Check"
    gum style --foreground "$C_MUTED" \
        "Runs rddbmgr to apply any pending schema updates." \
        "For deeper checks use RdAdmin → Database → Check & Repair."
    echo

    gum confirm "Run rddbmgr --update?" || return 0

    echo
    gum style --foreground "$C_ACCENT" --bold "Schema update:"
    if gum spin --title "Running rddbmgr --update..." --show-output -- \
            rddbmgr --update; then
        msg_success "Schema update complete."
    else
        msg_error "rddbmgr reported errors (see output above)."
    fi
}

# ── Main menu loop ───────────────────────────────────────────────────────────

run_main_menu() {
    while true; do
        show_banner
        show_system_summary
        echo

        local choice
        choice=$(gum choose \
            --header "Select an action:" \
            "Reinstall Rivendell" \
            "Upgrade Rivendell" \
            "Configure database" \
            "Configure audio store" \
            "Restart Rivendell service" \
            "Run database repair / check" \
            "Setup audio cards" \
            "Hold / Unhold packages" \
            "Build packages" \
            "Uninstall Rivendell" \
            "Exit") || choice="Exit"

        case "$choice" in
            "Reinstall Rivendell")            action_reinstall ;;
            "Upgrade Rivendell")              action_upgrade ;;
            "Configure database")              configure_database_interactive ;;
            "Configure audio store")           configure_audio_storage_interactive ;;
            "Restart Rivendell service")       action_restart_service ;;
            "Run database repair / check")     action_db_repair ;;
            "Setup audio cards")                setup_audio_cards_interactive ;;
            "Hold / Unhold packages")          action_hold_packages ;;
            "Build packages")                  action_build_packages ;;
            "Uninstall Rivendell")             action_uninstall ;;
            "Exit")
                echo
                msg_info "Goodbye."
                echo
                exit 0
                ;;
        esac

        press_enter
    done
}

# ── Self-update ──────────────────────────────────────────────────────────────
# Echoes "0" (true) if $1 is a strictly greater dotted-numeric version than $2.
_version_gt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

check_for_update() {
    local remote_file
    remote_file=$(mktemp)
    gum spin --title "Checking for updates..." -- \
        curl -fsSL --max-time 5 "$RD_CONFIG_UPDATE_URL" -o "$remote_file"

    if [ ! -s "$remote_file" ]; then
        rm -f "$remote_file"
        return 0
    fi

    local remote_version
    remote_version=$(grep -m1 '^SCRIPT_VERSION=' "$remote_file" | cut -d'"' -f2)
    if [ -z "$remote_version" ] || ! _version_gt "$remote_version" "$SCRIPT_VERSION"; then
        rm -f "$remote_file"
        return 0
    fi

    echo
    gum style --foreground "$C_ACCENT" --bold \
        "A newer version is available: v${SCRIPT_VERSION} → v${remote_version}"
    if gum confirm "Update now?"; then
        local self_path
        self_path=$(readlink -f "$0")
        if cp "$remote_file" "${self_path}.new" \
                && chmod --reference="$self_path" "${self_path}.new" \
                && mv "${self_path}.new" "$self_path"; then
            rm -f "$remote_file"
            msg_success "Updated to v${remote_version}. Restarting..."
            exec "$self_path" "$@"
        else
            msg_error "Failed to write update to $self_path"
            press_enter
        fi
    fi
    rm -f "$remote_file"
}

# ── Entry point ──────────────────────────────────────────────────────────────

main() {
    check_root
    ensure_gum
    check_for_update "$@"
    check_os_compat

    if is_rivendell_installed; then
        run_main_menu
    else
        run_installer
    fi
}

main "$@"
