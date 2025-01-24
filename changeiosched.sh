#!/bin/bash

if [ ! "$(uname)" == "Linux" ]; then
    echo "Unsupported OS! This script is only supported on Linux."
fi

# Prevent window debug output for kdialog
export QT_LOGGING_RULES="*.debug=false"

# General function to check for existing files
check_files_exist() {
    local filenames=("$@")  # Accept filenames as arguments

    for filename in "${filenames[@]}"; do
        if [ -f "$filename" ]; then
            return 0  # Return true if at least one file exists
        fi
    done

    return 1 # Exit the script if the file isn't found
}

# Check if we have kdialog or zenity installed.
filenames=('/usr/bin/kdialog' '/usr/local/bin/kdialog' '/usr/bin/zenity' '/usr/local/bin/zenity')
check_files_exist "${filenames[@]}"

if [ $? -ne 0 ]; then  # Check the exit status
    echo "This script depends on kdialog or zenity, please install one of them."
    exit
fi

# Check if we have pkexec installed.
filenames=('/usr/bin/pkexec' '/usr/local/bin/pkexec')
check_files_exist "${filenames[@]}"

if [ $? -ne 0 ]; then  # Check the exit status
    echo "This script depends on pkexec, please install it."
    exit
fi

# Shared text strings
DISK_SELECTION_TITLE="Disk Selection"
IOSCHEDULER_SELECTION_TITLE="I/O Scheduler Selection"
DISK_SELECTION_MESSAGE="Select a disk"
IOSCHEDULER_SELECTION_MESSAGE="Select I/O scheduler for"
ACTIVE_SCHED_MESSAGE="IO scheduler within [ ] is active."
SUCCESS_MESSAGE="I/O scheduler for %s is set to %s"
ERROR_MESSAGE="Failed to apply I/O scheduler. The password may have been incorrect or the operation was canceled."
GENERAL_ERROR_MESSAGE="No suitable dialog tool found."

# Figure out what dialog tool to use.
if command -v kdialog &> /dev/null; then
    # Use kdialog if available
    gui_tool=kdialog
elif command -v zenity &> /dev/null; then
    # Use zenity if kdialog is not available
    gui_tool=zenity
else
    echo "$GENERAL_ERROR_MESSAGE"
    exit 1
fi

# Function to select a disk
select_disk() {
    local disks=$(lsblk -d -n -p -o NAME | grep -v '/dev/loop'| sort)

    # Disk list for kdialog
    local disk_menu_items=""
    for disk in $disks; do
        disk_menu_items="$disk_menu_items $disk $disk"
    done

    if [ $gui_tool = "kdialog" ]; then
        local selected_disk=$($gui_tool --menu "$DISK_SELECTION_MESSAGE" --title "$DISK_SELECTION_TITLE" $disk_menu_items)
    elif [ $gui_tool = "zenity" ]; then
        local selected_disk=$($gui_tool --list --width=450 --height=490 --title "$DISK_SELECTION_TITLE" --column "$DISK_SELECTION_MESSAGE" $disks)
    fi

    if [ -z "$selected_disk" ]; then
        # Exit if no disk was selected
        exit 1
    fi

    echo "$selected_disk"
}

# Function to select I/O scheduler
select_ioscheduler() {
    local selected_disk=$1
    local ioschedulers=$(cat /sys/block/$(basename "$selected_disk")/queue/scheduler | tr ' ' '\n')
    local column_text=$(printf "$IOSCHEDULER_SELECTION_MESSAGE $selected_disk\n$ACTIVE_SCHED_MESSAGE")

    # IO sched list for kdialog
    local io_menu_items=""
    for iosched in $ioschedulers; do
        io_menu_items="$io_menu_items $iosched $iosched"
    done

    if [ $gui_tool = "kdialog" ]; then
        local selected_ioscheduler=$($gui_tool --menu "$IOSCHEDULER_SELECTION_MESSAGE $selected_disk\n$ACTIVE_SCHED_MESSAGE" --title "$IOSCHEDULER_SELECTION_TITLE" $io_menu_items)
    elif [ $gui_tool = "zenity" ]; then
        local selected_ioscheduler=$($gui_tool --list --width=450 --height=490 --title "$IOSCHEDULER_SELECTION_TITLE" --column "$column_text" $ioschedulers)
    fi

    if [ -z "$selected_ioscheduler" ]; then
        # No IO scheduler was selected, return to main menu
        main
    elif [[ "$selected_ioscheduler" =~ \[.*\] ]]; then
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --title "Already set" --sorry  "$selected_ioscheduler is already active on $selected_disk"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --info --width 400 --title "Already set" --text "$selected_ioscheduler is already active on $selected_disk"
        fi
        main # return to main
    else
        apply_ioscheduler "$selected_disk" "$selected_ioscheduler"
    fi

    echo "$selected_ioscheduler"
}

# Function to apply the selected I/O scheduler
apply_ioscheduler() {
    local selected_disk=$1
    local selected_ioscheduler=$2
    local set_success="$(printf "$SUCCESS_MESSAGE" "$selected_disk" "$selected_ioscheduler")"

    sync

    echo "$selected_ioscheduler" | pkexec tee /sys/block/$(basename "$selected_disk")/queue/scheduler > /dev/null

    # Check if pkexec failed (exit status != 0)
    if [ $? -ne 0 ]; then
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --error "$ERROR_MESSAGE"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --error --title "Error" --text "$ERROR_MESSAGE"
        fi
        exit 1  # Exit the script if pkexec failed
    else
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --title "Success" --msgbox "$set_success"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --info --width 400 --title "Success" --text "$set_success"
        fi
        # Done, return to main window.
        main
    fi
}

# Main function to orchestrate the steps
main() {
    selected_disk=$(select_disk)
    if [ $? -ne 0 ]; then  # Check if the function returned a non-zero exit status
        exit 1  # Quit the script if no disk was selected
    fi

    selected_ioscheduler=$(select_ioscheduler "$selected_disk")
}

# Execute the main function
main
