#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="${HOME}/dev/electrosteel_pipe_detection_prod"
HISTORY_ROOT="${PROJECT_ROOT}/var"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/storage_cleanup.log"

mkdir -p "$LOG_DIR"

TODAY_UNDERSCORE="$(date +%Y_%m_%d)"
YESTERDAY_UNDERSCORE="$(date -d yesterday +%Y_%m_%d)"

TODAY_HYPHEN="$(date +%Y-%m-%d)"
YESTERDAY_HYPHEN="$(date -d yesterday +%Y-%m-%d)"

# Only these directories are removed from yesterday's date folder.
YESTERDAY_DELETE_ITEMS=(
    "Shift_A_img"
    "Shift_A_text"
    "Shift_B_img"
    "Shift_B_text"
)

TOTAL_OLD_DATE_FOLDERS_DELETED=0
TOTAL_YESTERDAY_ITEMS_DELETED=0
TOTAL_FAILED=0
TOTAL_BYTES_FREED=0
CASTERS_CHECKED=0

log() {
    local message="$1"

    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$message" |
        tee -a "$LOG_FILE"
}

get_bytes() {
    local path="$1"
    local bytes

    bytes="$(
        du -sb -- "$path" 2>/dev/null |
            awk '{print $1}'
    )"

    printf '%s\n' "${bytes:-0}"
}

get_human_size() {
    local path="$1"
    local size

    size="$(
        du -sh -- "$path" 2>/dev/null |
            awk '{print $1}'
    )"

    printf '%s\n' "${size:-unknown}"
}

bytes_to_human() {
    local bytes="$1"

    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null ||
        printf '%s bytes\n' "$bytes"
}

delete_path() {
    local caster_name="$1"
    local target_path="$2"
    local description="$3"
    local bytes
    local human_size

    bytes="$(get_bytes "$target_path")"
    human_size="$(get_human_size "$target_path")"

    log "[$caster_name] Deleting $description | Size: $human_size"

    if rm -rf -- "$target_path"; then
        if [[ ! -e "$target_path" ]]; then
            log "[$caster_name] Deleted successfully: $description"

            TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + bytes))
            DELETE_RESULT_BYTES="$bytes"
            return 0
        fi

        log "[$caster_name] ERROR: Path still exists: $target_path"
    else
        log "[$caster_name] ERROR deleting: $target_path"
    fi

    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    DELETE_RESULT_BYTES=0
    return 1
}

log "============================================================"
log "Cleanup started"
log "Today: $TODAY_UNDERSCORE / $TODAY_HYPHEN"
log "Yesterday: $YESTERDAY_UNDERSCORE / $YESTERDAY_HYPHEN"
log "History root: $HISTORY_ROOT"
log "Yesterday cleanup: delete Shift A and Shift B; keep Shift C"
log "Folders older than yesterday will be deleted completely"

if [[ ! -d "$HISTORY_ROOT" ]]; then
    log "ERROR: History root does not exist: $HISTORY_ROOT"
    exit 1
fi

for CASTER_DIR in "$HISTORY_ROOT"/caster_*; do
    [[ -d "$CASTER_DIR" ]] || continue

    CASTER_NAME="$(basename "$CASTER_DIR")"
    HISTORY_DIR="$CASTER_DIR/history"

    if [[ ! -d "$HISTORY_DIR" ]]; then
        log "[$CASTER_NAME] No history directory. Skipping."
        continue
    fi

    CASTERS_CHECKED=$((CASTERS_CHECKED + 1))

    CASTER_OLD_DATE_FOLDERS_DELETED=0
    CASTER_YESTERDAY_ITEMS_DELETED=0
    CASTER_FAILED=0
    CASTER_BYTES_FREED=0

    log "[$CASTER_NAME] Checking history directory: $HISTORY_DIR"

    # ---------------------------------------------------------
    # Step 1: Clean yesterday's folder.
    #
    # Delete Shift A and Shift B directories only.
    # Shift C and all other unlisted items remain untouched.
    # ---------------------------------------------------------

    YESTERDAY_DIR=""

    if [[ -d "$HISTORY_DIR/$YESTERDAY_UNDERSCORE" ]]; then
        YESTERDAY_DIR="$HISTORY_DIR/$YESTERDAY_UNDERSCORE"
    elif [[ -d "$HISTORY_DIR/$YESTERDAY_HYPHEN" ]]; then
        YESTERDAY_DIR="$HISTORY_DIR/$YESTERDAY_HYPHEN"
    fi

    if [[ -n "$YESTERDAY_DIR" ]]; then
        log "[$CASTER_NAME] Cleaning yesterday's folder: $(basename "$YESTERDAY_DIR")"

        for ITEM_NAME in "${YESTERDAY_DELETE_ITEMS[@]}"; do
            ITEM_PATH="$YESTERDAY_DIR/$ITEM_NAME"

            if [[ ! -e "$ITEM_PATH" ]]; then
                log "[$CASTER_NAME] Yesterday item not present: $ITEM_NAME"
                continue
            fi

            if delete_path \
                "$CASTER_NAME" \
                "$ITEM_PATH" \
                "$(basename "$YESTERDAY_DIR")/$ITEM_NAME"; then

                CASTER_YESTERDAY_ITEMS_DELETED=$(
                    (CASTER_YESTERDAY_ITEMS_DELETED + 1)
                )
                TOTAL_YESTERDAY_ITEMS_DELETED=$(
                    (TOTAL_YESTERDAY_ITEMS_DELETED + 1)
                )
                CASTER_BYTES_FREED=$(
                    (CASTER_BYTES_FREED + DELETE_RESULT_BYTES)
                )
            else
                CASTER_FAILED=$((CASTER_FAILED + 1))
            fi
        done
    else
        log "[$CASTER_NAME] Yesterday's folder does not exist."
    fi

    # ---------------------------------------------------------
    # Step 2: Delete complete date folders older than yesterday.
    #
    # Today and yesterday are explicitly excluded.
    # ---------------------------------------------------------

    OLD_FOLDER_FOUND=0

    while IFS= read -r -d '' OLD_FOLDER; do
        OLD_FOLDER_FOUND=1
        FOLDER_NAME="$(basename "$OLD_FOLDER")"

        if delete_path \
            "$CASTER_NAME" \
            "$OLD_FOLDER" \
            "old date folder $FOLDER_NAME"; then

            CASTER_OLD_DATE_FOLDERS_DELETED=$(
                (CASTER_OLD_DATE_FOLDERS_DELETED + 1)
            )
            TOTAL_OLD_DATE_FOLDERS_DELETED=$(
                (TOTAL_OLD_DATE_FOLDERS_DELETED + 1)
            )
            CASTER_BYTES_FREED=$(
                (CASTER_BYTES_FREED + DELETE_RESULT_BYTES)
            )
        else
            CASTER_FAILED=$((CASTER_FAILED + 1))
        fi
    done < <(
        find "$HISTORY_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            \( \
                -name '20??_??_??' \
                -o \
                -name '20??-??-??' \
            \) \
            ! -name "$TODAY_UNDERSCORE" \
            ! -name "$YESTERDAY_UNDERSCORE" \
            ! -name "$TODAY_HYPHEN" \
            ! -name "$YESTERDAY_HYPHEN" \
            -print0
    )

    if [[ "$OLD_FOLDER_FOUND" -eq 0 ]]; then
        log "[$CASTER_NAME] No date folders older than yesterday found."
    fi

    CASTER_FREED_HUMAN="$(bytes_to_human "$CASTER_BYTES_FREED")"

    log "[$CASTER_NAME] Summary: yesterday_items_deleted=$CASTER_YESTERDAY_ITEMS_DELETED, old_date_folders_deleted=$CASTER_OLD_DATE_FOLDERS_DELETED, failed=$CASTER_FAILED, freed=$CASTER_FREED_HUMAN"
done

TOTAL_FREED_HUMAN="$(bytes_to_human "$TOTAL_BYTES_FREED")"

log "Cleanup completed"
log "Casters checked: $CASTERS_CHECKED"
log "Yesterday Shift A/B items deleted: $TOTAL_YESTERDAY_ITEMS_DELETED"
log "Old date folders deleted: $TOTAL_OLD_DATE_FOLDERS_DELETED"
log "Failures: $TOTAL_FAILED"
log "Total space freed: $TOTAL_FREED_HUMAN"

log "Root filesystem usage:"
df -h / 2>&1 | tee -a "$LOG_FILE"

log "SSD filesystem usage:"
df -h /mnt/ssd 2>&1 | tee -a "$LOG_FILE"

log "============================================================"

if [[ "$TOTAL_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
