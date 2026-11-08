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

# Experiment 015 Checkpoint 2 — verify signed handoff, install pinned rc-pade,
# then bind through pade-coder/modules/rc-pade-bindings (no Experiment 011 adapter).
locals {
  # filebase64 for all embeds: evidence.sig and trusted.pub are raw binary.
  rc_input_handoff_profile_b64   = filebase64("${path.module}/rc-inputs/handoff/profile.yaml")
  rc_input_handoff_evidence_b64  = filebase64("${path.module}/rc-inputs/handoff/evidence.json")
  rc_input_handoff_signature_b64 = filebase64("${path.module}/rc-inputs/handoff/evidence.sig")
  rc_input_ext_common_b64        = filebase64("${path.module}/rc-inputs/handoff/extensions/6f74ec92447e1997fadac6862f6dfc886bc42ea8ec73d1c4e2979d48d49bd157.yaml")
  rc_input_ext_env_b64           = filebase64("${path.module}/rc-inputs/handoff/extensions/36d3fb00f63f88f003e499153258522d6f8ea63677fb409a2cf3ffd5beb787dc.yaml")
  rc_input_ext_ga_b64            = filebase64("${path.module}/rc-inputs/handoff/extensions/db303fb46325eea8db4196ed83ad8ea6d91f5d49af3e226fea7cfaf1f8b5248d.yaml")
  rc_input_ext_sc_b64            = filebase64("${path.module}/rc-inputs/handoff/extensions/e6ab6b30b00cee3d345174a4aede0504f72013e5639b1aa23fc5e683995f704f.yaml")
  rc_input_trusted_pub_b64       = filebase64("${path.module}/rc-inputs/trusted.pub")
  rc_input_policy_b64            = filebase64("${path.module}/rc-inputs/policy.yaml")
  rc_input_allow_b64             = filebase64("${path.module}/rc-inputs/allow-capabilities.txt")
  rc_input_source_b64            = filebase64("${path.module}/rc-inputs/SOURCE.txt")
  rc_input_verify_main_b64       = filebase64("${path.module}/rc-inputs/verify-handoff/main.go")

  rc_demos_commit          = "853eab3c2c04f9d1059b2dbd64ea91996828a3a9"
  rc_go_rc_profiler_commit = "5d2e860e48842b89ec83414123a7e59228f61d36"
  rc_pade_bind_commit      = "43226ef96ae09419b6253a6eb364fd44a0ac1305"
  rc_go_version            = "1.26.10"
  rc_go_tarball            = "go1.26.10.linux-amd64.tar.gz"
  rc_go_sha256             = "ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5"
}

resource "coder_script" "rc_handoff_verify" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "RC Signed Handoff Verify (015)"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    SELF="after-certainty-rc-trusted-bindings"
    LOG_DIR="$HOME/.coder-modules/after-certainty/rc-trusted-bindings/logs"
    INPUT_DIR="$HOME/.config/pade/rc-downstream"
    HANDOFF_DIR="$INPUT_DIR/handoff"
    EXT_DIR="$HANDOFF_DIR/extensions"
    CACHE_DIR="$HOME/.coder-modules/after-certainty/rc-trusted-bindings/cache"
    mkdir -p "$LOG_DIR" "$CACHE_DIR"
    LOG="$LOG_DIR/run.log"
    exec > >(tee -a "$LOG") 2>&1

    say() { printf 'rc-trusted-bindings: %s\n' "$*"; }

    SUCCESS_FLAG="$LOG_DIR/handoff.ok"
    rm -f "$SUCCESS_FLAG" "$LOG_DIR/packaging.ok" "$LOG_DIR/verify.ok"
    cleanup_src() { :; }
    trap 'cleanup_src 2>/dev/null || true; if [ -f "$SUCCESS_FLAG" ]; then coder exp sync complete '"$SELF"'; else say "sync_complete_skipped_after_failure"; fi' EXIT

    coder exp sync want "$SELF" ${join(" ", module.pade[0].scripts)}
    coder exp sync start "$SELF"

    BINDINGS_PATH_RAW='${module.pade[0].bindings_path}'
    BINDINGS_PATH="$(python3 -c 'import os,sys; print(os.path.expanduser(sys.argv[1]))' "$BINDINGS_PATH_RAW")"

    fail_closed_bindings() {
      local reason="$1"
      local tmp
      tmp="$(mktemp "$BINDINGS_PATH.XXXXXX")"
      printf '%s\n' 'version: "0.1"' 'capabilities: {}' > "$tmp"
      chmod 0600 "$tmp"
      mv "$tmp" "$BINDINGS_PATH"
      say "fail_closed_bindings reason=$reason path=$BINDINGS_PATH mode=$(stat -c '%a' "$BINDINGS_PATH") sha256=$(sha256sum "$BINDINGS_PATH" | awk '{print $1}')"
    }

    say "checkpoint=015-2-verify-signed-handoff"
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
      say "bindings_before_verify_mode=$(stat -c '%a' "$BINDINGS_PATH")"
      say "bindings_before_verify_sha256=$(sha256sum "$BINDINGS_PATH" | awk '{print $1}')"
    else
      say "bindings_before_verify=missing"
    fi

    mkdir -p "$INPUT_DIR" "$EXT_DIR"

    write_b64() {
      local dest="$1" mode="$2" b64="$3"
      local tmp
      tmp="$(mktemp "$dest.XXXXXX")"
      printf '%s' "$b64" | base64 -d > "$tmp"
      chmod "$mode" "$tmp"
      mv "$tmp" "$dest"
      say "materialized dest=$dest mode=$(stat -c '%a' "$dest") sha256=$(sha256sum "$dest" | awk '{print $1}')"
    }

    # RC producer/CI ownership: signed handoff bundle (Verify() root).
    write_b64 "$HANDOFF_DIR/profile.yaml" 0600 '${local.rc_input_handoff_profile_b64}'
    write_b64 "$HANDOFF_DIR/evidence.json" 0600 '${local.rc_input_handoff_evidence_b64}'
    write_b64 "$HANDOFF_DIR/evidence.sig" 0600 '${local.rc_input_handoff_signature_b64}'
    write_b64 "$EXT_DIR/6f74ec92447e1997fadac6862f6dfc886bc42ea8ec73d1c4e2979d48d49bd157.yaml" 0600 '${local.rc_input_ext_common_b64}'
    write_b64 "$EXT_DIR/36d3fb00f63f88f003e499153258522d6f8ea63677fb409a2cf3ffd5beb787dc.yaml" 0600 '${local.rc_input_ext_env_b64}'
    write_b64 "$EXT_DIR/db303fb46325eea8db4196ed83ad8ea6d91f5d49af3e226fea7cfaf1f8b5248d.yaml" 0600 '${local.rc_input_ext_ga_b64}'
    write_b64 "$EXT_DIR/e6ab6b30b00cee3d345174a4aede0504f72013e5639b1aa23fc5e683995f704f.yaml" 0600 '${local.rc_input_ext_sc_b64}'

    # Platform operator ownership: verification trust + projection inputs.
    # No validation-report.yaml: Experiment 015 binds through rc-pade bind only.
    write_b64 "$INPUT_DIR/trusted.pub" 0644 '${local.rc_input_trusted_pub_b64}'
    write_b64 "$INPUT_DIR/policy.yaml" 0600 '${local.rc_input_policy_b64}'
    write_b64 "$INPUT_DIR/allow-capabilities.txt" 0600 '${local.rc_input_allow_b64}'
    write_b64 "$INPUT_DIR/SOURCE.txt" 0600 '${local.rc_input_source_b64}'
    mkdir -p "$INPUT_DIR/verify-handoff"
    write_b64 "$INPUT_DIR/verify-handoff/main.go" 0644 '${local.rc_input_verify_main_b64}'

    missing=0
    for f in \
      "$HANDOFF_DIR/profile.yaml" \
      "$HANDOFF_DIR/evidence.json" \
      "$HANDOFF_DIR/evidence.sig" \
      "$EXT_DIR/6f74ec92447e1997fadac6862f6dfc886bc42ea8ec73d1c4e2979d48d49bd157.yaml" \
      "$EXT_DIR/36d3fb00f63f88f003e499153258522d6f8ea63677fb409a2cf3ffd5beb787dc.yaml" \
      "$EXT_DIR/db303fb46325eea8db4196ed83ad8ea6d91f5d49af3e226fea7cfaf1f8b5248d.yaml" \
      "$EXT_DIR/e6ab6b30b00cee3d345174a4aede0504f72013e5639b1aa23fc5e683995f704f.yaml" \
      "$INPUT_DIR/trusted.pub" \
      "$INPUT_DIR/policy.yaml" \
      "$INPUT_DIR/allow-capabilities.txt" \
      "$INPUT_DIR/verify-handoff/main.go"
    do
      if [ ! -f "$f" ]; then
        say "missing=$f"
        missing=1
      fi
    done
    if [ "$missing" -ne 0 ]; then
      fail_closed_bindings "packaging_incomplete"
      say "STOP: durable signed-handoff packaging incomplete"
      exit 1
    fi
    if [ -e "$INPUT_DIR/signer.key" ]; then
      fail_closed_bindings "private_signing_key_present"
      say "STOP: private signing key must not be present in workspace inputs"
      exit 1
    fi
    if [ -e "$INPUT_DIR/validation-report.yaml" ]; then
      say "removing_stale_validation_report path=$INPUT_DIR/validation-report.yaml"
      rm -f "$INPUT_DIR/validation-report.yaml"
    fi
    say "packaging_complete"

    RC_DEMOS_COMMIT='${local.rc_demos_commit}'
    GO_PROFILER_COMMIT='${local.rc_go_rc_profiler_commit}'
    GO_VERSION='${local.rc_go_version}'
    GO_TARBALL='${local.rc_go_tarball}'
    GO_SHA256='${local.rc_go_sha256}'
    say "verifier_rc_demos_commit=$RC_DEMOS_COMMIT"
    say "verifier_go_rc_profiler_commit=$GO_PROFILER_COMMIT"
    say "verifier_go_version=$GO_VERSION"

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

    say "fetching_rc_demos url=https://github.com/runtimeconditions/rc-demos/archive/$RC_DEMOS_COMMIT.tar.gz"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 \
      -o "$SRC_TMP/rc-demos.tar.gz" "https://github.com/runtimeconditions/rc-demos/archive/$RC_DEMOS_COMMIT.tar.gz"
    tar -C "$SRC_TMP" -xzf "$SRC_TMP/rc-demos.tar.gz"
    RC_DEMOS_DIR="$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d -name 'rc-demos-*' | head -n1 || true)"
    if [ -z "$RC_DEMOS_DIR" ] || [ ! -d "$RC_DEMOS_DIR/validated-profile-handoff/handoff" ]; then
      fail_closed_bindings "rc_demos_archive_missing_handoff"
      say "STOP: pinned rc-demos archive missing validated-profile-handoff"
      exit 1
    fi

    say "fetching_go_rc_profiler url=https://github.com/runtimeconditions/go-rc-profiler/archive/$GO_PROFILER_COMMIT.tar.gz"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 \
      -o "$SRC_TMP/go-rc-profiler.tar.gz" "https://github.com/runtimeconditions/go-rc-profiler/archive/$GO_PROFILER_COMMIT.tar.gz"
    tar -C "$SRC_TMP" -xzf "$SRC_TMP/go-rc-profiler.tar.gz"
    GO_PROFILER_DIR="$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d -name 'go-rc-profiler-*' | head -n1 || true)"
    if [ -z "$GO_PROFILER_DIR" ]; then
      fail_closed_bindings "go_rc_profiler_archive_missing"
      say "STOP: pinned go-rc-profiler archive missing"
      exit 1
    fi
    # validated-profile-handoff go.mod replace: ../../go-rc-profiler
    ln -sfn "$GO_PROFILER_DIR" "$SRC_TMP/go-rc-profiler"

    VERIFY_CMD_DIR="$RC_DEMOS_DIR/validated-profile-handoff/cmd/exp014-verify"
    mkdir -p "$VERIFY_CMD_DIR"
    # Live template source has no //go:build ignore; strip if a repo-hygiene copy is reused.
    sed '/^\/\/go:build ignore$/d' "$INPUT_DIR/verify-handoff/main.go" > "$VERIFY_CMD_DIR/main.go"
    VERIFY_BIN="$INPUT_DIR/verify-handoff/verify-handoff"
    say "building_verifier src=$VERIFY_CMD_DIR"
    (
      cd "$RC_DEMOS_DIR/validated-profile-handoff"
      CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$VERIFY_BIN" ./cmd/exp014-verify
    )
    chmod 0700 "$VERIFY_BIN"
    say "materialized dest=$VERIFY_BIN mode=$(stat -c '%a' "$VERIFY_BIN") sha256=$(sha256sum "$VERIFY_BIN" | awk '{print $1}')"

    VERIFIED_PROFILE="$INPUT_DIR/verified-profile.yaml"
    rm -f "$VERIFIED_PROFILE"
    say "verifying_handoff bundle=$HANDOFF_DIR trusted_key=$INPUT_DIR/trusted.pub"
    set +e
    VERIFY_OUT="$(VERIFIED_PROFILE_OUT="$VERIFIED_PROFILE" "$VERIFY_BIN" "$HANDOFF_DIR" "$INPUT_DIR/trusted.pub" 2>&1)"
    VERIFY_RC=$?
    set -e
    printf '%s\n' "$VERIFY_OUT" | while IFS= read -r line; do say "verifier: $line"; done
    if [ "$VERIFY_RC" -ne 0 ]; then
      fail_closed_bindings "untrusted_handoff"
      say "STOP: untrusted_handoff verification_failed rc=$VERIFY_RC"
      exit 1
    fi
    if [ ! -f "$VERIFIED_PROFILE" ]; then
      fail_closed_bindings "verified_profile_missing"
      say "STOP: verifier reported success but verified-profile.yaml missing"
      exit 1
    fi
    say "handoff_verified=true verified_profile=$VERIFIED_PROFILE sha256=$(sha256sum "$VERIFIED_PROFILE" | awk '{print $1}') bytes=$(wc -c < "$VERIFIED_PROFILE")"
    : > "$LOG_DIR/verify.ok"
    say "complete_verify_only next=modules/rc-pade-bindings"
    : > "$SUCCESS_FLAG"
  EOT
}

resource "coder_script" "rc_pade_install" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Install pinned rc-pade (015)"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    SELF="after-certainty-rc-pade-install"
    LOG_DIR="$HOME/.coder-modules/after-certainty/rc-pade-install/logs"
    CACHE_DIR="$HOME/.coder-modules/after-certainty/rc-pade-install/cache"
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$LOG_DIR" "$CACHE_DIR" "$BIN_DIR"
    LOG="$LOG_DIR/run.log"
    exec > >(tee -a "$LOG") 2>&1

    say() { printf 'rc-pade-install: %s\n' "$*"; }

    SUCCESS_FLAG="$LOG_DIR/install.ok"
    rm -f "$SUCCESS_FLAG"
    cleanup_src() { :; }
    trap 'cleanup_src 2>/dev/null || true; if [ -f "$SUCCESS_FLAG" ]; then coder exp sync complete '"$SELF"'; else say "sync_complete_skipped_after_failure"; fi' EXIT

    # coder exp sync want requires ≥1 depends-on; this installer has none.
    coder exp sync start "$SELF"

    RC_PADE_COMMIT='${local.rc_pade_bind_commit}'
    GO_VERSION='${local.rc_go_version}'
    GO_TARBALL='${local.rc_go_tarball}'
    GO_SHA256='${local.rc_go_sha256}'
    RC_PADE_BIN="$BIN_DIR/rc-pade"

    say "checkpoint=015-2-install-pinned-rc-pade"
    say "rc_pade_bind_commit=$RC_PADE_COMMIT"
    say "rc_pade_bin=$RC_PADE_BIN"
    say "go_version=$GO_VERSION"

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

    say "fetching_rc_pade url=https://github.com/After-Certainty/rc-pade/archive/$RC_PADE_COMMIT.tar.gz"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 \
      -o "$SRC_TMP/rc-pade.tar.gz" "https://github.com/After-Certainty/rc-pade/archive/$RC_PADE_COMMIT.tar.gz"
    tar -C "$SRC_TMP" -xzf "$SRC_TMP/rc-pade.tar.gz"
    RC_PADE_DIR="$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d -name 'rc-pade-*' | head -n1 || true)"
    if [ -z "$RC_PADE_DIR" ] || [ ! -f "$RC_PADE_DIR/cmd/rc-pade/bind.go" ]; then
      say "STOP: pinned rc-pade archive missing cmd/rc-pade/bind.go"
      exit 1
    fi

    say "building_rc_pade src=$RC_PADE_DIR/cmd/rc-pade out=$RC_PADE_BIN"
    (
      cd "$RC_PADE_DIR"
      CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$RC_PADE_BIN" ./cmd/rc-pade
    )
    chmod 0700 "$RC_PADE_BIN"
    say "materialized dest=$RC_PADE_BIN mode=$(stat -c '%a' "$RC_PADE_BIN") sha256=$(sha256sum "$RC_PADE_BIN" | awk '{print $1}')"
    say "rc_pade_help_bind=$("$RC_PADE_BIN" bind --help 2>&1 | head -n 5 | tr '\n' '|' || true)"
    say "complete"
    : > "$SUCCESS_FLAG"
  EOT
}

module "rc_pade_bindings" {
  count  = data.coder_workspace.me.start_count
  source = "git::https://github.com/After-Certainty/pade-coder.git//modules/rc-pade-bindings?ref=c40ba8c49c987f7b2ea9c1e42eb40fd6c36630a5"

  agent_id = coder_agent.main.id

  verified_profile_path = "~/.config/pade/rc-downstream/verified-profile.yaml"
  policy_path           = "~/.config/pade/rc-downstream/policy.yaml"
  allow_capabilities    = ["github.repo.read", "github.repo.write"]

  broker_binding = module.pade[count.index].broker_binding
  bindings_path  = module.pade[count.index].bindings_path
  pade_scripts   = module.pade[count.index].scripts

  prerequisite_scripts = [
    "after-certainty-rc-trusted-bindings",
    "after-certainty-rc-pade-install",
  ]

  rc_pade_command = "~/.local/bin/rc-pade"
  session_out     = "~/.config/pade/rc-downstream/development-session.yaml"
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
