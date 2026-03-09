#!/bin/sh

# Universal script to download helper scripts from URLs.
# Compatible with sh, bash, zsh, fish.

# Directory to store downloaded scripts
SCRIPTS_DIR="./scripts"

# Create the scripts directory if it doesn't exist
if [ ! -d "$SCRIPTS_DIR" ]; then
  echo "Creating directory $SCRIPTS_DIR..."
  mkdir -p "$SCRIPTS_DIR"
fi

# List of scripts to download
# Add entries as needed: "URL" "OUTPUT_FILE"
DOWNLOADS=(
  "https://gist.githubusercontent.com/kmassada/81938de78714eb4f9166/raw/ssh-init-key.sh" "ssh-init-key.sh"
  # Add more pairs like this:
  # "https://example.com/script2.sh" "script2.sh"
)

# Function to download and make executable
download_script() {
  URL="$1"
  OUTPUT_FILE="$2"
  FULL_PATH="$SCRIPTS_DIR/$OUTPUT_FILE"

  echo "Downloading $OUTPUT_FILE to $SCRIPTS_DIR from $URL..."
  if curl -sL "$URL" -o "$FULL_PATH"; then
    echo "Successfully downloaded $OUTPUT_FILE."
    if [ -f "$FULL_PATH" ]; then
      chmod +x "$FULL_PATH"
      echo "Made $FULL_PATH executable."
    else
      echo "Error: Download failed, file $FULL_PATH not created."
      return 1
    fi
  else
    echo "Failed to download $OUTPUT_FILE from $URL."
    return 1
  fi
  return 0
}

# Main loop
exit_code=0
i=0
while [ $i -lt ${#DOWNLOADS[@]} ]; do
  url=${DOWNLOADS[$i]}
  i=$((i + 1))
  outfile=${DOWNLOADS[$i]}
  i=$((i + 1))

  if ! download_script "$url" "$outfile"; then
    exit_code=1
  fi
done

exit $exit_code
