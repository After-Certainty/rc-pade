terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "coder" {}

variable "project_id" {
  description = "Which Google Compute Project should your workspace live in?"
}

variable "pade_broker_endpoint" {
  description = "HTTPS endpoint of the PADE broker that authorizes this workspace's GCE service account."
  type        = string
}

# See https://registry.coder.com/modules/coder/gcp-region
module "gcp_region" {
  source = "registry.coder.com/coder/gcp-region/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  regions = ["us", "europe"]
  default = "us-central1-a"
}

provider "google" {
  zone    = module.gcp_region.value
  project = var.project_id
}

data "google_compute_default_service_account" "default" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "google_compute_disk" "root" {
  name  = "coder-${data.coder_workspace.me.id}-root"
  type  = "pd-ssd"
  zone  = module.gcp_region.value
  image = "debian-cloud/debian-12"
  lifecycle {
    ignore_changes = [name, image]
  }
}

resource "coder_agent" "main" {
  auth           = "google-instance-identity"
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}'
    EOT
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      free -m | awk 'NR==2{printf "%.2f%%\t", $3*100/$2 }'
    EOT
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = <<-EOT
      #!/bin/bash
      set -e
      df /home/coder | awk '$NF=="/"{printf "%s", $5}'
    EOT
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"
}

module "pade" {
  count  = data.coder_workspace.me.start_count
  source = "git::https://github.com/After-Certainty/pade-coder.git//modules/pade?ref=3e9184087665b2bc6ebe7d261d1fbbd88cf94b60"

  agent_id            = coder_agent.main.id
  pade_version        = "v0.4.1"
  broker_endpoint     = var.pade_broker_endpoint
  broker_identity     = "gce"
  broker_capabilities = [] # dynamic / trusted downstream
}

# Trusted RC → PADE bindings handoff (Experiment 013 durable inputs).
# Consumes module.pade outputs only for broker_binding / bindings_path / scripts.
# Operator-owned Profile/evidence/policy/allowlist are embedded under ./rc-inputs/
# at template push time. The Experiment 011 adapter is built at startup from a
# pinned public rc-pade commit using a pinned Go toolchain (Coder template
# archive limit is 1MiB, so the adapter binary is not embedded).
locals {
  rc_input_profile_b64 = base64encode(file("${path.module}/rc-inputs/profile.yaml"))
  rc_input_report_b64  = base64encode(file("${path.module}/rc-inputs/validation-report.yaml"))
  rc_input_policy_b64  = base64encode(file("${path.module}/rc-inputs/policy.yaml"))
  rc_input_allow_b64   = base64encode(file("${path.module}/rc-inputs/allow-capabilities.txt"))
  rc_input_source_b64  = base64encode(file("${path.module}/rc-inputs/SOURCE.txt"))

  rc_pade_adapter_commit = "fd592a4c826fb6b8f005c11625122138c797ae63"
  rc_go_version          = "1.26.10"
  rc_go_tarball          = "go1.26.10.linux-amd64.tar.gz"
  rc_go_sha256           = "ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5"
}

resource "coder_script" "rc_trusted_bindings" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "RC Trusted PADE Bindings"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    SELF="after-certainty-rc-trusted-bindings"
    LOG_DIR="$HOME/.coder-modules/after-certainty/rc-trusted-bindings/logs"
    INPUT_DIR="$HOME/.config/pade/rc-downstream"
    CACHE_DIR="$HOME/.coder-modules/after-certainty/rc-trusted-bindings/cache"
    mkdir -p "$LOG_DIR" "$CACHE_DIR"
    LOG="$LOG_DIR/run.log"
    exec > >(tee -a "$LOG") 2>&1

    say() { printf 'rc-trusted-bindings: %s\n' "$*"; }

    SUCCESS_FLAG="$LOG_DIR/handoff.ok"
    rm -f "$SUCCESS_FLAG"
    trap 'cleanup_src 2>/dev/null || true; if [ -f "$SUCCESS_FLAG" ]; then coder exp sync complete '"$SELF"'; else say "sync_complete_skipped_after_failure"; fi' EXIT
    cleanup_src() { :; }

    coder exp sync want "$SELF" ${join(" ", module.pade[0].scripts)}
    coder exp sync start "$SELF"

    BINDINGS_PATH_RAW='${module.pade[0].bindings_path}'
    BINDINGS_PATH="$(python3 -c 'import os,sys; print(os.path.expanduser(sys.argv[1]))' "$BINDINGS_PATH_RAW")"

    say "sync_dependencies_satisfied=$SELF <- ${join(" ", module.pade[0].scripts)}"
    say "bindings_path_raw=$BINDINGS_PATH_RAW"
    say "bindings_path_expanded=$BINDINGS_PATH"
    case "$BINDINGS_PATH" in
      "$HOME"/*) ;;
      *)
        say "STOP: expanded bindings path is not under HOME: $BINDINGS_PATH"
        exit 1
        ;;
    esac
    if [ -f "$BINDINGS_PATH" ]; then
      say "bindings_before_adapter_mode=$(stat -c '%a' "$BINDINGS_PATH")"
      say "bindings_before_adapter_sha256=$(sha256sum "$BINDINGS_PATH" | awk '{print $1}')"
    else
      say "bindings_before_adapter=missing"
    fi

    mkdir -p "$INPUT_DIR"

    write_b64() {
      local dest="$1" mode="$2" b64="$3"
      local tmp
      tmp="$(mktemp "$dest.XXXXXX")"
      printf '%s' "$b64" | base64 -d > "$tmp"
      chmod "$mode" "$tmp"
      mv "$tmp" "$dest"
      say "materialized dest=$dest mode=$(stat -c '%a' "$dest") sha256=$(sha256sum "$dest" | awk '{print $1}')"
    }

    BROKER_JSON="$INPUT_DIR/broker_binding.json"
    write_b64 "$BROKER_JSON" 0600 '${base64encode(jsonencode(module.pade[0].broker_binding))}'
    say "broker_binding_source=module.pade.broker_binding"

    ADAPTER="$INPUT_DIR/experiment-011-coder-rc-bindings"
    PROFILE="$INPUT_DIR/profile.yaml"
    REPORT="$INPUT_DIR/validation-report.yaml"
    POLICY="$INPUT_DIR/policy.yaml"
    ALLOW_FILE="$INPUT_DIR/allow-capabilities.txt"
    SOURCE_TXT="$INPUT_DIR/SOURCE.txt"
    SESSION_OUT="$INPUT_DIR/development-session.yaml"

    write_b64 "$PROFILE" 0600 '${local.rc_input_profile_b64}'
    write_b64 "$REPORT" 0600 '${local.rc_input_report_b64}'
    write_b64 "$POLICY" 0600 '${local.rc_input_policy_b64}'
    write_b64 "$ALLOW_FILE" 0600 '${local.rc_input_allow_b64}'
    write_b64 "$SOURCE_TXT" 0600 '${local.rc_input_source_b64}'

    RC_PADE_COMMIT='${local.rc_pade_adapter_commit}'
    GO_VERSION='${local.rc_go_version}'
    GO_TARBALL='${local.rc_go_tarball}'
    GO_SHA256='${local.rc_go_sha256}'
    say "adapter_source_commit=$RC_PADE_COMMIT"
    say "adapter_go_version=$GO_VERSION"

    GO_ROOT="$CACHE_DIR/go$GO_VERSION"
    if [ ! -x "$GO_ROOT/bin/go" ]; then
      say "fetching_pinned_go tarball=$GO_TARBALL"
      go_tmp="$(mktemp -d "$CACHE_DIR/go-fetch.XXXXXX")"
      curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 \
        -o "$go_tmp/$GO_TARBALL" "https://go.dev/dl/$GO_TARBALL"
      echo "$GO_SHA256  $go_tmp/$GO_TARBALL" | sha256sum -c -
      mkdir -p "$go_tmp/extract"
      tar -C "$go_tmp/extract" -xzf "$go_tmp/$GO_TARBALL"
      rm -rf "$GO_ROOT"
      mv "$go_tmp/extract/go" "$GO_ROOT"
      rm -rf "$go_tmp"
    else
      say "reusing_cached_go path=$GO_ROOT"
    fi
    export PATH="$GO_ROOT/bin:$PATH"
    export GOTOOLCHAIN=local
    say "go_version_output=$(go version)"

    SRC_TMP="$(mktemp -d "$CACHE_DIR/src.XXXXXX")"
    cleanup_src() { rm -rf "$SRC_TMP"; }

    ARCHIVE_URL="https://github.com/After-Certainty/rc-pade/archive/$RC_PADE_COMMIT.tar.gz"
    say "fetching_adapter_source url=$ARCHIVE_URL"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 \
      -o "$SRC_TMP/src.tar.gz" "$ARCHIVE_URL"
    tar -C "$SRC_TMP" -xzf "$SRC_TMP/src.tar.gz"
    SRC_DIR="$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d -name 'rc-pade-*' | head -n1 || true)"
    if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR/experiments/011-coder-rc-bindings" ]; then
      say "STOP: pinned rc-pade archive missing experiments/011-coder-rc-bindings"
      exit 1
    fi
    say "building_adapter src=$SRC_DIR/experiments/011-coder-rc-bindings"
    (
      cd "$SRC_DIR/experiments/011-coder-rc-bindings"
      CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$ADAPTER" .
    )
    chmod 0700 "$ADAPTER"
    say "materialized dest=$ADAPTER mode=$(stat -c '%a' "$ADAPTER") sha256=$(sha256sum "$ADAPTER" | awk '{print $1}')"

    if [ ! -x "$ADAPTER" ] || [ ! -f "$PROFILE" ] || [ ! -f "$REPORT" ] || [ ! -f "$POLICY" ] || [ ! -f "$ALLOW_FILE" ]; then
      say "STOP: operator-owned rc-downstream inputs/adapter missing after durable delivery; leaving module bindings untouched beyond PADE empty map"
      say "missing_check adapter=$([ -x "$ADAPTER" ] && echo ok || echo missing) profile=$([ -f "$PROFILE" ] && echo ok || echo missing) report=$([ -f "$REPORT" ] && echo ok || echo missing) policy=$([ -f "$POLICY" ] && echo ok || echo missing) allow=$([ -f "$ALLOW_FILE" ] && echo ok || echo missing)"
      exit 1
    fi

    ALLOW="$(tr -d ' \n\r\t' < "$ALLOW_FILE")"
    say "invoking_adapter allow_capabilities=$ALLOW"
    "$ADAPTER" \
      --profile "$PROFILE" \
      --validation-report "$REPORT" \
      --policy "$POLICY" \
      --broker-binding "$BROKER_JSON" \
      --allow-capabilities "$ALLOW" \
      --output "$BINDINGS_PATH" \
      --session-out "$SESSION_OUT"

    say "bindings_after_adapter_mode=$(stat -c '%a' "$BINDINGS_PATH")"
    say "bindings_after_adapter_sha256=$(sha256sum "$BINDINGS_PATH" | awk '{print $1}')"
    say "complete"
    : > "$SUCCESS_FLAG"
  EOT
}

resource "google_compute_instance" "dev" {
  zone         = module.gcp_region.value
  count        = data.coder_workspace.me.start_count
  name         = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-root"
  machine_type = "e2-medium"
  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }
  boot_disk {
    auto_delete = false
    source      = google_compute_disk.root.name
  }
  service_account {
    email  = "pade-coder-workspace@after-certainty.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }
  # The startup script runs as root with no $HOME environment set up, so instead of directly
  # running the agent init script, create a user (with a homedir, default shell and sudo
  # permissions) and execute the init script as that user.
  metadata_startup_script = <<EOMETA
#!/usr/bin/env sh
set -eux

# Don't use coder CLI in startup scripts; use the agent token instead.
# Also don't print secrets into logs.
if ! id -u "${local.linux_user}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${local.linux_user}"
  echo "${local.linux_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder-user
fi

exec sudo -u "${local.linux_user}" sh -c '${coder_agent.main.init_script}'
EOMETA
}

locals {
  # Ensure Coder username is a valid Linux username
  linux_user = lower(substr(data.coder_workspace_owner.me.name, 0, 32))
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.dev[0].id

  item {
    key   = "type"
    value = google_compute_instance.dev[0].machine_type
  }
}

resource "coder_metadata" "home_info" {
  resource_id = google_compute_disk.root.id

  item {
    key   = "size"
    value = "${google_compute_disk.root.size} GiB"
  }
}
