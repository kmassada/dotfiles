#!/bin/bash
#
# Lightweight cherry-pick installer for Nerd Fonts.
# Downloads only selected font family archives directly from GitHub releases
# instead of cloning the multi-gigabyte ryanoasis/nerd-fonts git repository.
#
# Usage:
#   ./install_nerd_fonts.sh [FontName1] [FontName2] ...
#   ./install_nerd_fonts.sh Hack NerdFontsSymbolsOnly
#   ./install_nerd_fonts.sh JetBrainsMono Meslo

set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_nerd_fonts() {
  local fonts=("$@")
  if [ ${#fonts[@]} -eq 0 ]; then
    fonts=("Hack" "NerdFontsSymbolsOnly")
  fi

  local font_dir="${HOME}/.local/share/fonts/NerdFonts"
  mkdir -p "${font_dir}"

  local temp_font_dir
  temp_font_dir="$(mktemp -d)"
  local updated=false

  echo "============================================================"
  echo " Installing Nerd Fonts to ${font_dir}"
  echo " Target families: ${fonts[*]}"
  echo "============================================================"

  for font in "${fonts[@]}"; do
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.tar.xz"
    local archive="${temp_font_dir}/${font}.tar.xz"
    local extract_dir="${temp_font_dir}/${font}"
    mkdir -p "${extract_dir}"

    echo "==> Downloading ${font} (${url})..."
    if wget -q --show-progress "${url}" -O "${archive}" 2>/dev/null || curl -sSL "${url}" -o "${archive}"; then
      if [ -f "${archive}" ] && [ -s "${archive}" ]; then
        tar -xf "${archive}" -C "${extract_dir}"
        # Move only true type and open type font files to destination
        find "${extract_dir}" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec mv -f {} "${font_dir}/" \;
        echo "    ✓ ${font} successfully installed."
        updated=true
      else
        echo "    ✗ Downloaded archive for ${font} is empty or corrupt."
      fi
    else
      echo "    ✗ Failed to download ${font} from ${url}"
    fi
  done

  # Clean up temporary downloads
  rm -rf "${temp_font_dir}"

  if [ "${updated}" = true ]; then
    echo "==> Refreshing font cache..."
    if command_exists fc-cache; then
      fc-cache -f "${font_dir}"
    fi
    echo "==> Font cache refresh complete."
  fi

  # Optional warning/cleanup for legacy multi-GB git clone
  if [ -d "${HOME}/nerd-fonts" ]; then
    echo "============================================================"
    echo " Notice: Found legacy ~/nerd-fonts git clone repository."
    echo " You can safely reclaim multi-GB disk space by running:"
    echo "   rm -rf ~/nerd-fonts"
    echo "============================================================"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_nerd_fonts "$@"
fi
