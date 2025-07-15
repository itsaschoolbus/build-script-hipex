#!/bin/bash
set -o pipefail

# Load configuration
if [ -f "config.env" ]; then
    source "config.env"
else
    echo "Error: config.env not found." >&2
    exit 1
fi

# Handle device codename
if [[ -z "$CONFIG_DEVICE" ]]; then
    read -p "Enter the device codename: " DEVICE
    if [[ -z "$DEVICE" ]]; then
        echo "ERROR: Device codename not provided." >&2
        exit 1
    fi
else
    DEVICE="$CONFIG_DEVICE"
fi

# Script Constants. Required variables throughout the script.
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)
BOLD_GREEN=${BOLD}$(tput setaf 2)
RED=$(tput setaf 1)
OFFICIAL="0"
ROOT_DIRECTORY="$(pwd)"

# Post Constants. Required variables for posting purposes.
ROM_NAME="$(sed "s#.*/##" <<<"$(pwd)")"
ANDROID_VERSION=$(grep -oP '(?<=android-)[0-9]+' .repo/manifests/default.xml | head -n1 || echo "N/A")
OUT_DIR="$ROOT_DIRECTORY/out/target/product/$DEVICE"
STICKER_URL="https://raw.githubusercontent.com/Weebo354342432/reimagined-enigma/main/update.webp"

# --- Helper Functions ---

# Function to print error messages and exit
die() {
    echo -e "$RED\nERROR: $1$RESET\n"
    exit 1
}

# Function to calculate and format duration
get_duration() {
    local start_time=$1
    local end_time=$2
    local difference=$((end_time - start_time))
    local hours=$((difference / 3600))
    local minutes=$(((difference % 3600) / 60))
    local seconds=$((difference % 60))

    local duration=""
    if [[ $hours -gt 0 ]]; then
        duration="${hours} hour(s), "
    fi
    if [[ $minutes -gt 0 || $hours -gt 0 ]]; then
        duration="${duration}${minutes} minute(s) and "
    fi
    duration="${duration}${seconds} second(s)"
    echo "$duration"
}

# --- Telegram Functions ---

# Function to generate a formatted Telegram message
# Arguments:
#   $1: Status Icon (e.g., 🟡)
#   $2: Status Title (e.g., "Compiling ROM...")
#   $3: Details (multiline string of key-value pairs)
#   $4: Footer (optional, e.g., "Compilation took 1 hour")
generate_telegram_message() {
    local icon="$1"
    local title="$2"
    local details="$3"
    local footer="$4"

    local message="<b>$icon | $title</b>"

    if [[ -n "$details" ]]; then
        message+="\n\n$details"
    fi

    if [[ -n "$footer" ]]; then
        message+="\n\n<i>$footer</i>"
    fi

    echo -e "$message"
}

# Function to send a message to Telegram
send_message() {
    local message="$1"
    local chat_id="$2"
    local response
    response=$(curl -s "https://api.telegram.org/bot$CONFIG_BOT_TOKEN/sendMessage" \
        -d chat_id="$chat_id" \
        -d "parse_mode=html" \
        -d "disable_web_page_preview=true" \
        -d text="$message")

    # Return message_id
    echo "$response" | grep -o '"message_id":[0-9]*' | cut -d':' -f2
}

# Function to edit a message on Telegram
edit_message() {
    local message="$1"
    local chat_id="$2"
    local message_id="$3"
    curl -s "https://api.telegram.org/bot$CONFIG_BOT_TOKEN/editMessageText" \
        -d chat_id="$chat_id" \
        -d "parse_mode=html" \
        -d "message_id=$message_id" \
        -d text="$message" > /dev/null
}

# Function to send a file to Telegram
send_file() {
    local file_path="$1"
    local chat_id="$2"
    curl --progress-bar -F document="@$file_path" "https://api.telegram.org/bot$CONFIG_BOT_TOKEN/sendDocument" \
        -F chat_id="$chat_id" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html"
}

# Function to send a sticker to Telegram
send_sticker() {
    local sticker_url="$1"
    local chat_id="$2"
    local sticker_file="$ROOT_DIRECTORY/sticker.webp"

    curl -sL "$sticker_url" -o "$sticker_file"

    curl -s "https://api.telegram.org/bot$CONFIG_BOT_TOKEN/sendSticker" \
        -F sticker="@$sticker_file" \
        -F chat_id="$chat_id" \
        -F "is_animated=false" \
        -F "is_video=false" > /dev/null

    rm -f "$sticker_file"
}

# --- Upload Function ---

# Function to upload a file to PixelDrain
upload_file() {
    local file_path="$1"
    local response
    response=$(curl -s -T "$file_path" -u ":$CONFIG_PDUP_API" https://pixeldrain.com/api/file/)
    local hash
    hash=$(echo "$response" | grep -Po '(?<="id":")[^"]*')

    if [[ -n "$hash" ]]; then
        echo "https://pixeldrain.com/u/$hash"
    else
        echo "Upload failed"
    fi
}

# --- Build Functions ---

# Function to get build progress
fetch_progress() {
    local progress
    progress=$( \
        sed -n '/ ninja/,$p' "$ROOT_DIRECTORY/build.log" | \
            grep -Po '\d+% \d+/\d+' | \
            tail -n1 | \
            sed -e 's/ / (/; s/$/)/' \
    )

    if [ -z "$progress" ]; then
        echo "Initializing..."
    else
        echo "$progress"
    fi
}

# --- Main Script ---

# CLI parameters parsing
while [[ $# -gt 0 ]]; do
    case $1 in
    -s | --sync) SYNC="1" ;;
    -c | --clean) CLEAN="1" ;;
    -o | --official)
        if [ -n "$CONFIG_OFFICIAL_FLAG" ]; then
            OFFICIAL="1"
        else
            die "Official flag (CONFIG_OFFICIAL_FLAG) not set in configuration."
        fi
        ;;
    -h | --help)
        echo -e "\nNote: • You should specify all the mandatory variables in the script!"
        echo -e "      • Just run \"./$(basename "$0")\" for a normal build"
        echo -e "Usage: ./$(basename "$0") [OPTION]\n"
        echo -e "Options:"
        echo -e "    -s, --sync            Sync sources before building."
        echo -e "    -c, --clean           Clean build directory before compilation."
        echo -e "    -o, --official        Build the official variant."
        echo -e "    -h, --help            Show this help message.\n"
        exit 0
        ;;
    *)
        die "Unknown parameter(s) passed: $1"
        ;;
    esac
    shift
done

# Configuration Checking
if [[ -z "$CONFIG_TARGET" || -z "$CONFIG_BOT_TOKEN" || -z "$CONFIG_CHATID" ]]; then
    die "Please set all mandatory variables in config.env: CONFIG_TARGET, CONFIG_BOT_TOKEN, CONFIG_CHATID."
fi

# Set error chat ID to main chat ID if not specified
if [[ -z "$CONFIG_ERROR_CHATID" ]]; then
    CONFIG_ERROR_CHATID="$CONFIG_CHATID"
fi

# Cleanup old files
rm -f "out/error.log" "out/.lock" "$ROOT_DIRECTORY/build.log"

# Jobs Configuration
CORE_COUNT=$(nproc --all)
CONFIG_SYNC_JOBS=$((CORE_COUNT > 8 ? 12 : CORE_COUNT))
CONFIG_COMPILE_JOBS=$CORE_COUNT

# Sync sources if requested
if [[ -n "$SYNC" ]]; then
    echo -e "$BOLD_GREEN\nStarting to sync sources...$RESET\n"

    details="<b>• ROM:</b> <code>$ROM_NAME</code>\n<b>• DEVICE:</b> <code>$DEVICE</code>\n<b>• JOBS:</b> <code>$CONFIG_SYNC_JOBS Cores</code>"
    sync_start_message=$(generate_telegram_message "🟡" "Syncing sources..." "$details")
    sync_message_id=$(send_message "$sync_start_message" "$CONFIG_CHATID")

    sync_start_time=$(date -u +%s)

    if ! repo sync -c --jobs-network="$CONFIG_SYNC_JOBS" -j"$CONFIG_SYNC_JOBS" --jobs-checkout="$CONFIG_SYNC_JOBS" --optimized-fetch --prune --force-sync --no-clone-bundle --no-tags; then
        echo -e "$YELLOW\nInitial sync failed. Retrying with fewer arguments...$RESET\n"
        if ! repo sync -j"$CONFIG_SYNC_JOBS"; then
            sync_end_time=0
            echo -e "$RED\nSync failed completely. Proceeding with build anyway...$RESET\n"
            sync_failed_message=$(generate_telegram_message "🔴" "Syncing sources failed!" "" "Proceeding with build...")
            edit_message "$sync_failed_message" "$CONFIG_CHATID" "$sync_message_id"
        else
            sync_end_time=$(date -u +%s)
        fi
    else
        sync_end_time=$(date -u +%s)
    fi

    if [[ "$sync_end_time" -ne 0 ]]; then
        duration=$(get_duration "$sync_start_time" "$sync_end_time")
        details="<b>• ROM:</b> <code>$ROM_NAME</code>\n<b>• DEVICE:</b> <code>$DEVICE</code>"
        sync_finished_message=$(generate_telegram_message "🟢" "Sources synced!" "$details" "Syncing took $duration.")
        edit_message "$sync_finished_message" "$CONFIG_CHATID" "$sync_message_id"
    fi
fi

# Clean out directory if requested
if [[ -n "$CLEAN" ]]; then
    echo -e "$BOLD_GREEN\nNuking the out directory...$RESET\n"
    rm -rf "out"
fi

# --- Build Process ---

BUILD_TYPE=$([ "$OFFICIAL" == "1" ] && echo "Official" || echo "Unofficial")

details="<b>• ROM:</b> <code>$ROM_NAME</code>\n<b>• DEVICE:</b> <code>$DEVICE</code>\n<b>• ANDROID VERSION:</b> <code>$ANDROID_VERSION</code>\n<b>• TYPE:</b> <code>$BUILD_TYPE</code>\n<b>• PROGRESS:</b> <code>Initializing...</code>"
build_start_message=$(generate_telegram_message "🟡" "Compiling ROM..." "$details")
build_message_id=$(send_message "$build_start_message" "$CONFIG_CHATID")

build_start_time=$(date -u +%s)

echo -e "$BOLD_GREEN\nSetting up build environment...$RESET"
source build/envsetup.sh

echo -e "$BOLD_GREEN\nRunning breakfast for \"$DEVICE\"...$RESET"
breakfast "$DEVICE"

if [ $? -ne 0 ]; then
    build_failed_message=$(generate_telegram_message "🔴" "ROM compilation failed" "" "Failed at running breakfast for $DEVICE.")
    edit_message "$build_failed_message" "$CONFIG_CHATID" "$build_message_id"
    send_sticker "$STICKER_URL" "$CONFIG_CHATID"
    exit 1
fi

echo -e "$BOLD_GREEN\nStarting build...$RESET"
m installclean -j"$CONFIG_COMPILE_JOBS"
m "$CONFIG_TARGET" -j"$CONFIG_COMPILE_JOBS" > "$ROOT_DIRECTORY/build.log" 2>&1 &

# Monitor build progress
previous_progress=""
while jobs -r &>/dev/null; do
    current_progress=$(fetch_progress)
    if [[ "$current_progress" != "$previous_progress" ]]; then
        details="<b>• ROM:</b> <code>$ROM_NAME</code>\n<b>• DEVICE:</b> <code>$DEVICE</code>\n<b>• ANDROID VERSION:</b> <code>$ANDROID_VERSION</code>\n<b>• TYPE:</b> <code>$BUILD_TYPE</code>\n<b>• PROGRESS:</b> <code>$current_progress</code>"
        progress_message=$(generate_telegram_message "🟡" "Compiling ROM..." "$details")
        edit_message "$progress_message" "$CONFIG_CHATID" "$build_message_id"
        previous_progress="$current_progress"
    fi
    sleep 10
done

wait # Wait for the background build process to finish

build_end_time=$(date -u +%s)
build_duration=$(get_duration "$build_start_time" "$build_end_time")

# Check build result
if ! grep -q "#### build completed successfully" "$ROOT_DIRECTORY/build.log"; then
    echo -e "$RED\nBuild failed. Check build.log for details.$RESET"
    build_failed_message=$(generate_telegram_message "🔴" "ROM compilation failed" "" "Build failed after $build_duration. Check out the log for more details.")
    edit_message "$build_failed_message" "$CONFIG_CHATID" "$build_message_id"
    send_file "$ROOT_DIRECTORY/build.log" "$CONFIG_ERROR_CHATID"
    send_sticker "$STICKER_URL" "$CONFIG_CHATID"
else
    echo -e "$BOLD_GREEN\nBuild successful!$RESET"

    # Find build artifacts
    zip_file=$(find "$OUT_DIR" -name "*$DEVICE*.zip" -type f | tail -n1)
    json_file=$(find "$OUT_DIR" -name "*$DEVICE*.json" -type f | tail -n1)

    if [[ -z "$zip_file" ]]; then
        build_failed_message=$(generate_telegram_message "🔴" "Build finished, but no ZIP file found!" "" "Check the output directory for details.")
        edit_message "$build_failed_message" "$CONFIG_CHATID" "$build_message_id"
        exit 1
    fi

    echo -e "$BOLD_GREEN\nUploading build artifacts...$RESET"

    zip_file_url=$(upload_file "$zip_file")
    zip_file_md5sum=$(md5sum "$zip_file" | awk '{print $1}')
    zip_file_size=$(ls -sh "$zip_file" | awk '{print $1}')

    json_file_url=""
    if [[ -n "$json_file" ]]; then
        json_file_url=$(upload_file "$json_file")
    fi

    details="<b>• ROM:</b> <code>$ROM_NAME</code>\n<b>• DEVICE:</b> <code>$DEVICE</code>\n<b>• ANDROID VERSION:</b> <code>$ANDROID_VERSION</code>\n<b>• TYPE:</b> <code>$BUILD_TYPE</code>\n<b>• SIZE:</b> <code>$zip_file_size</code>\n<b>• MD5SUM:</b> <code>$zip_file_md5sum</code>"
    if [[ -n "$json_file_url" && "$json_file_url" != "Upload failed" ]]; then
        details+="\n<b>• JSON:</b> <a href=\"$json_file_url\">Here</a>"
    fi
    if [[ -n "$zip_file_url" && "$zip_file_url" != "Upload failed" ]]; then
        details+="\n<b>• DOWNLOAD:</b> <a href=\"$zip_file_url\">Here</a>"
    fi

    build_finished_message=$(generate_telegram_message "🟢" "ROM compiled successfully!" "$details" "Compilation took $build_duration.")

    edit_message "$build_finished_message" "$CONFIG_CHATID" "$build_message_id"
    send_sticker "$STICKER_URL" "$CONFIG_CHATID"
fi

if [[ "$POWEROFF" == "true" ]]; then
    echo -e "$BOLD_GREEN\nPowering off server...$RESET"
    sudo poweroff
fi