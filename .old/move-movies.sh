#!/bin/bash

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Installing dialog..."
    sudo apt-get update && sudo apt-get install -y dialog
fi

# Configuration
PLEX1_PATH="/plex-1"
PLEX2_PATH="/plex-2"
DIALOG_HEIGHT=30
DIALOG_WIDTH=100

# Function to get movies and folders from a directory
get_items() {
    local base_path="$1"
    local type="$2"  # "movies" or "tv"

    if [ "$type" = "movies" ]; then
        local content_path="$base_path/Movies"
        # Handle Movies structure
        for lang in "English" "Hindi"; do
            if [ -d "$content_path/$lang" ]; then
                # List directories
                while IFS= read -r -d $'\0' dir; do
                    if [ -d "$dir" ]; then
                        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                        echo "DIR:$dir:$size"
                    fi
                done < <(find "$content_path/$lang" -mindepth 1 -maxdepth 1 -type d -print0)

                # List standalone movie files
                while IFS= read -r -d $'\0' file; do
                    size=$(du -sh "$file" 2>/dev/null | cut -f1)
                    echo "FILE:$file:$size"
                done < <(find "$content_path/$lang" -mindepth 1 -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" \) -print0)
            fi
        done
    else
        # Handle TV Shows structure
        local content_path="$base_path/TV-Shows"
        if [ -d "$content_path" ]; then
            # List TV Show folders
            while IFS= read -r -d $'\0' dir; do
                if [ -d "$dir" ]; then
                    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    echo "DIR:$dir:$size"
                fi
            done < <(find "$content_path" -mindepth 1 -maxdepth 1 -type d -print0)
        fi
    fi
}

# Function to move items
move_item() {
    local src="$1"
    local dst="$2"
    local filename="$3"

    # Ensure the destination directory exists
    mkdir -p "$(dirname "$dst")"

    # Move the item
    mv "$src" "$dst"

    if [ $? -eq 0 ]; then
        echo "Moved: $filename"
    else
        echo "Failed to move: $filename"
    fi
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(dialog --clear --title "Plex Media Mover" \
            --menu "Choose an action:" $DIALOG_HEIGHT $DIALOG_WIDTH 6 \
            1 "Move Movies: NAS to Local (Onload)" \
            2 "Move Movies: Local to NAS (Offload)" \
            3 "Move TV Shows: NAS to Local (Onload)" \
            4 "Move TV Shows: Local to NAS (Offload)" \
            5 "Exit" \
            2>&1 >/dev/tty)

        case $choice in
            1) move_items "$PLEX1_PATH" "$PLEX2_PATH" "movies" ;;
            2) move_items "$PLEX2_PATH" "$PLEX1_PATH" "movies" ;;
            3) move_items "$PLEX1_PATH" "$PLEX2_PATH" "tv" ;;
            4) move_items "$PLEX2_PATH" "$PLEX1_PATH" "tv" ;;
            5) clear; exit 0 ;;
        esac
    done
}

# Function to handle moving items
move_items() {
    local source_path="$1"
    local dest_path="$2"
    local content_type="$3"  # "movies" or "tv"

    # Get list of items
    mapfile -t items < <(get_items "$source_path" "$content_type")

    if [ ${#items[@]} -eq 0 ]; then
        if [ "$content_type" = "movies" ]; then
            dialog --msgbox "No movies or folders found in the source directory!" 8 40
        else
            dialog --msgbox "No TV Show folders found in the source directory!" 8 40
        fi
        return
    fi

    local options=()
    local i=1

    # Create options array for dialog
    for item in "${items[@]}"; do
        local type=${item%%:*}
        local path=${item#*:}
        local size=${path##*:}
        path=${path%:*}
        local name
        name=$(basename -- "$path")

        # Add an icon to distinguish folders and files
        if [ "$type" = "DIR" ]; then
            if [ "$content_type" = "tv" ]; then
                name="📺 $name ($size)"  # TV Show folder
            else
                name="📁 $name ($size)"  # Movie folder
            fi
        else
            name="🎬 $name ($size)"  # Movie file
        fi

        options+=("$i" "$name" OFF)
        ((i++))
    done

    # Show item selection menu with checkboxes
    local title_text
    if [ "$content_type" = "movies" ]; then
        title_text="Select Movies or Folders"
        menu_text="Choose files or folders (📁 = folder, 🎬 = movie):"
    else
        title_text="Select TV Shows"
        menu_text="Choose TV Show folders (📺 = TV Show):"
    fi

    local selections
    selections=$(dialog --clear --title "$title_text" \
        --checklist "$menu_text" $DIALOG_HEIGHT $DIALOG_WIDTH $((i-1)) \
        "${options[@]}" \
        2>&1 >/dev/tty)

    if [ -n "$selections" ]; then
        local selected_items=()
        local move_summary=()
        for selection in $selections; do
            local selected_item="${items[$((selection-1))]}"
            selected_items+=("$selected_item")

            local type=${selected_item%%:*}
            local path=${selected_item#*:}
            path=${path%:*}
            local name
            name=$(basename -- "$path")
            local source_dir
            source_dir=$(dirname -- "$path")
            local relative_path=${source_dir#$source_path/}
            local dest_dir="$dest_path/$relative_path"

            move_summary+=("$source_dir/$name -> $dest_dir/$name")
        done

        # Show confirmation for all selected moves
        dialog --yesno "Confirm the following moves:\n\n$(printf "%s\n" "${move_summary[@]}")" 20 80

        if [ $? -eq 0 ]; then
            # Move each selected item
            clear
            echo "Moving items..."
            for item in "${selected_items[@]}"; do
                local type=${item%%:*}
                local path=${item#*:}
                path=${path%:*}
                local name
                name=$(basename -- "$path")
                local source_dir
                source_dir=$(dirname -- "$path")
                local relative_path=${source_dir#$source_path/}
                local dest_dir="$dest_path/$relative_path"

                # Move the item
                move_item "$path" "$dest_dir/" "$name"
            done

            dialog --msgbox "All selected items have been moved!" 8 40
        fi
    fi
}

# Clear screen before starting
clear

# Check if paths are configured
if [[ "$PLEX1_PATH" == "/path/to/plex-1" ]]; then
    echo "Please configure the paths in the script first!"
    echo "Edit PLEX1_PATH and PLEX2_PATH variables."
    exit 1
fi

# Start the main menu
main_menu
