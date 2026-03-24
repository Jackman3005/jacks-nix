#!/usr/bin/env bash
#
# Shared functions for jacks-nix scripts.
# Source this file, do not execute it directly.

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
# Read from config/defaults.json — single source of truth shared with Nix.
# Uses simple bash string ops to avoid requiring jq.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEFAULTS_JSON="$_LIB_DIR/../config/defaults.json"

# Extract a string value from the flat defaults.json.
_json_str() {
  local key="$1"
  grep "\"$key\"" "$_DEFAULTS_JSON" | sed 's/.*: *"\(.*\)".*/\1/' | head -1
}

# Extract a boolean value from the flat defaults.json.
_json_bool() {
  local key="$1"
  local line
  line=$(grep "\"$key\"" "$_DEFAULTS_JSON" | head -1)
  if [[ "$line" == *"true"* ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# ---------------------------------------------------------------------------
# Config schema
# ---------------------------------------------------------------------------
# Each entry: "ENV_VAR|type|default|prompt"
#   type: string or bool
#   default: value, "eval:cmd" for runtime evaluation, or "json:key" to read
#            from defaults.json
#
# The order here is the order the user is prompted during install/reconfigure.
# ---------------------------------------------------------------------------
CONFIG_SCHEMA=(
  'JACKS_NIX_USERNAME|string|eval:whoami|System username'
  'JACKS_NIX_GIT_NAME|string|json:gitName|Your full name (for Git commits)'
  'JACKS_NIX_GIT_EMAIL|string|json:gitEmail|Your email (for Git commits)'
  'JACKS_NIX_GIT_SIGNING_KEY|string|json:gitSigningKey|SSH signing key (leave empty to disable)'
  'JACKS_NIX_ENABLE_GIT|bool|json:enableGit|Enable Git configuration'
  'JACKS_NIX_ENABLE_ZSH|bool|json:enableZsh|Enable Zsh + Starship prompt'
  'JACKS_NIX_ENABLE_NVIM|bool|json:enableNvim|Enable Neovim'
  'JACKS_NIX_ENABLE_NODE|bool|json:enableNode|Enable Node.js (nvm)'
  'JACKS_NIX_ENABLE_JAVA|bool|json:enableJava|Enable Java (SDKMAN)'
  'JACKS_NIX_ENABLE_RUBY|bool|json:enableRuby|Enable Ruby'
  'JACKS_NIX_ENABLE_BUN|bool|json:enableBun|Enable Bun runtime'
  'JACKS_NIX_ENABLE_ASDF|bool|json:enableAsdf|Enable ASDF version manager'
)

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

# Resolve default value (handles "eval:", "json:" prefixes).
_resolve_default() {
  local default="$1" type="$2"
  if [[ "$default" == eval:* ]]; then
    eval "${default#eval:}"
  elif [[ "$default" == json:* ]]; then
    local json_key="${default#json:}"
    if [[ "$type" == "bool" ]]; then
      _json_bool "$json_key"
    else
      _json_str "$json_key"
    fi
  else
    echo "$default"
  fi
}

# Parse a schema entry into its components.
# Usage: _parse_schema_entry "$entry" => sets _key, _type, _default, _prompt
_parse_schema_entry() {
  IFS='|' read -r _key _type _default _prompt <<< "$1"
  _default="$(_resolve_default "$_default" "$_type")"
}

# Prompt the user for a single config value.
# For bools: shows (Y/n) or (y/N) based on default.
# For strings: shows [default] or empty.
# Sets the result in the env var named by _key.
_prompt_for_value() {
  local key="$1" type="$2" default="$3" prompt="$4"

  if [[ "$type" == "bool" ]]; then
    local hint
    if [[ "$default" == "true" ]]; then
      hint="Y/n"
    else
      hint="y/N"
    fi
    printf "  %s (%s): " "$prompt" "$hint"
    read -r response < /dev/tty
    if [[ -z "$response" ]]; then
      export "$key=$default"
    elif [[ "$response" =~ ^[Yy] ]]; then
      export "$key=true"
    else
      export "$key=false"
    fi
  else
    if [[ -n "$default" ]]; then
      printf "  %s [%s]: " "$prompt" "$default"
    else
      printf "  %s: " "$prompt"
    fi
    read -r response < /dev/tty
    if [[ -z "$response" ]]; then
      export "$key=$default"
    else
      export "$key=$response"
    fi
  fi
}

# Load config: source config.env, then for any missing schema keys either
# print the value (if set via env) or prompt the user.
# Args: $1 = config repo path, $2 = mode ("install"|"update"|"reconfigure")
load_config() {
  local config_repo="$1"
  local mode="${2:-update}"
  local config_file="$config_repo/local/config.env"

  # 1. Snapshot env vars that were explicitly set BEFORE we source config.env.
  #    These take precedence over saved config (e.g. CI exports, shell profile).
  declare -A _env_before
  local entry _key _type _default _prompt
  for entry in "${CONFIG_SCHEMA[@]}"; do
    _parse_schema_entry "$entry"
    if [[ -n "${!_key+x}" ]]; then
      _env_before[$_key]="${!_key}"
    fi
  done

  # 2. Source saved config (fills in vars that weren't already set).
  if [[ -f "$config_file" ]]; then
    source "$config_file"
  fi

  # 3. Restore env overrides (external env takes precedence over config.env).
  for _key in "${!_env_before[@]}"; do
    export "$_key=${_env_before[$_key]}"
  done

  # 4. Walk the schema. For each key:
  #    - If already set (from env or config.env): print it.
  #      On "reconfigure" mode: prompt anyway, using current value as default.
  #    - If not set: prompt for it (install/reconfigure) or use default (update with no tty).
  echo ""
  echo "📋 Configuration:"
  if [[ "$mode" == "update" && ! -f "$config_file" ]]; then
    echo "   Saving your configuration for future updates."
    echo "   Press Enter to accept defaults, or type a new value."
  fi
  echo ""

  for entry in "${CONFIG_SCHEMA[@]}"; do
    _parse_schema_entry "$entry"

    if [[ "$mode" == "reconfigure" ]]; then
      # Always prompt, using current value (or schema default) as the default
      local current="${!_key:-$_default}"
      _prompt_for_value "$_key" "$_type" "$current" "$_prompt"
    elif [[ -n "${!_key+x}" && -n "${!_key}" ]]; then
      # Value is set — just display it
      if [[ -n "${_env_before[$_key]+x}" ]]; then
        printf "  %s: %s (from environment)\n" "$_prompt" "${!_key}"
      else
        printf "  %s: %s\n" "$_prompt" "${!_key}"
      fi
    elif [[ "$mode" == "install" ]]; then
      # First install — prompt for missing values (use defaults in non-interactive)
      if [[ -t 0 ]] && [[ -e /dev/tty ]]; then
        _prompt_for_value "$_key" "$_type" "$_default" "$_prompt"
      else
        export "$_key=$_default"
        printf "  %s: %s (default)\n" "$_prompt" "$_default"
      fi
    else
      # Update with missing key — new option or first config.env creation
      if [[ -t 0 ]] && [[ -e /dev/tty ]]; then
        if [[ ! -f "$config_file" ]]; then
          # First time creating config.env — not alarming, just collecting values
          _prompt_for_value "$_key" "$_type" "$_default" "$_prompt"
        else
          # Existing config.env but this key is new
          echo ""
          echo "  ⚠️  New configuration option:"
          _prompt_for_value "$_key" "$_type" "$_default" "$_prompt"
          echo ""
        fi
      else
        # Non-interactive (CI) — use default silently
        export "$_key=$_default"
        printf "  %s: %s (default)\n" "$_prompt" "$_default"
      fi
    fi
  done

  echo ""
}

# Save current config values to config.env.
# Only writes keys that are in the current schema (drops deprecated keys).
# Call this AFTER a successful install/update.
save_config() {
  local config_repo="$1"
  local config_file="$config_repo/local/config.env"

  mkdir -p "$config_repo/local"

  {
    echo "# jacks-nix local configuration"
    echo "# Generated by jacks-nix — edit with: jacks-nix-reconfigure"
    echo ""
    local entry _key _type _default _prompt
    for entry in "${CONFIG_SCHEMA[@]}"; do
      _parse_schema_entry "$entry"
      # Write the current value, with special chars escaped for safe sourcing
      local val="${!_key:-$_default}"
      val="${val//\\/\\\\}"   # backslashes first
      val="${val//\"/\\\"}"   # double quotes
      val="${val//\$/\\\$}"   # dollar signs
      val="${val//\`/\\\`}"   # backticks
      printf 'export %s="%s"\n' "$_key" "$val"
    done
  } > "$config_file"
}

# ---------------------------------------------------------------------------
# Pre-flight fixes (macOS)
# ---------------------------------------------------------------------------
# Resolves known issues that prevent darwin-rebuild from succeeding.
# Safe to call multiple times (idempotent).
darwin_preflight() {
  # nix-darwin manages /etc/{bashrc,zshrc,...} via symlinks to /etc/static/.
  # If macOS restores the originals (e.g. after a system update), darwin-rebuild
  # fails with "Unexpected files in /etc". Move non-symlink copies out of the way.
  for f in /etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile /etc/nix/nix.conf; do
    if [[ -e "$f" && ! -L "$f" ]]; then
      echo "⚠️  Moving $f to ${f}.before-nix-darwin (nix-darwin manages this file)"
      sudo mv "$f" "${f}.before-nix-darwin"
    fi
  done

  # home-manager >= 25.11 copies apps instead of symlinking them (copyApps).
  # If the old linkApps symlink still exists, rsync fails with permission errors.
  local hm_apps="$HOME/Applications/Home Manager Apps"
  if [[ -L "$hm_apps" ]]; then
    echo "⚠️  Removing old Home Manager Apps symlink (will be replaced by copied apps)"
    rm "$hm_apps"
  fi
}
