# Packaging snapshot — Experiment 015 template v2

Directory `template-exp015_rc_pade_bind_v2` is the retained source for the
live Coder template version **`exp015_rc_pade_bind_v2`**.

## Fix vs v1

`after-certainty-rc-pade-install` no longer calls `coder exp sync want` with
zero dependencies (`want` requires ≥1 depends-on). It starts its sync unit
directly, then completes after `~/.local/bin/rc-pade` is installed.

## Capture method

```text
coder templates push gcp-pade --directory <this-dir> --name exp015_rc_pade_bind_v2 --activate=true --yes
```

| Field | Value |
|---|---|
| template | `gcp-pade` |
| version | `exp015_rc_pade_bind_v2` |
| live active | true |
| exact unmodified pull `main.tf` SHA-256 | `0fbe9e9c1d30429ca4a91333aa13284825e681301da31081849af8217bc65060` |
| exact unmodified pull file-manifest SHA-256 | `6c2c1f2ff75ceb445486a97c466f618956660573c1d1bbf293eeb65076d2e336` |
| baseline | `exp015_rc_pade_bind_v1` |

## Behavior

Same as v1 happy path after the install-sync fix.
