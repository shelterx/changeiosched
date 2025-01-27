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

# Only use whiptail in non graphical sessions.
if [ -z "$DISPLAY" ] || [ -z "$WAYLAND_DISPLAY" ]; then
    # Check if we have whiptail installed before continuing
    filenames=('/usr/bin/whiptail' '/usr/local/bin/whiptail' '/usr/bin/zenity' '/usr/local/bin/zenity')
    check_files_exist "${filenames[@]}"

    if [ $? -ne 0 ]; then  # Check the exit status
        echo "This script depends on whiptail, please intall it."
        exit
    else
        use_whiptail=true
    fi

else
    # For graphical sessions, check if we have kdialog or zenity installed.
    filenames=('/usr/bin/kdialog' '/usr/local/bin/kdialog' '/usr/bin/zenity' '/usr/local/bin/zenity')
    check_files_exist "${filenames[@]}"

    if [ $? -ne 0 ]; then  # Check the exit status
        echo "This script depends on kdialog or zenity, please install one of them."
        exit
    fi

    # Also check if we have pkexec installed.
    filenames=('/usr/bin/pkexec' '/usr/local/bin/pkexec')
    check_files_exist "${filenames[@]}"

    if [ $? -ne 0 ]; then  # Check the exit status
        echo "This script depends on pkexec, please install it."
        exit
    fi
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
if [ ! "$use_whiptail"  ]; then
    if command -v kdialog &> /dev/null; then
        gui_tool=kdialog
    elif command -v zenity &> /dev/null; then
        gui_tool=zenity
    else
        echo "$GENERAL_ERROR_MESSAGE"
        exit 1
    fi
else
    # If there's no X or Wayland session, use whiptail if available
    if command -v whiptail &> /dev/null; then
        gui_tool=whiptail
    else
        echo "$GENERAL_ERROR_MESSAGE"
        exit 1
    fi
fi


# Function to select I/O scheduler
select_ioscheduler() {
    local selected_disk=$1

#    echo "$selected_ioscheduler"
}Documents

# Function to apply the selected I/O scheduler
apply_ioscheduler() {
    local selected_disk=$1
    local selected_ioscheduler=$2
    local set_success="$(printf "$SUCCESS_MESSAGE" "$selected_disk" "$selected_ioscheduler")"

    if [[ "$selected_ioscheduler" =~ \[.*\] ]]; then
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --title "Already set" --sorry  "$selected_ioscheduler is already active on $selected_disk"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --info --width 400 --title "Already set" --text "$selected_ioscheduler is already active on $selected_disk"
        elif [ $gui_tool = "whiptail" ]; then
            $gui_tool --title "Already Active" --msgbox "$selected_ioscheduler is already active on $selected_disk" 8 45
        fi
        main # return to main
    fi

    # Sync disks before changing IO scheduler
    sync

    if [ ! $gui_tool = "whiptail" ]; then
        echo "$selected_ioscheduler" | pkexec tee /sys/block/$(basename "$selected_disk")/queue/scheduler > /dev/null
    else
          # Check for sudo, if that fails, use su.
        if command -v sudo >/dev/null 2>&1; then
            echo "Enter sudo password to change IO scheduler for $selected_disk"
            echo "$selected_ioscheduler" | sudo tee /sys/block/$(basename "$selected_disk")/queue/scheduler > /dev/null 2>&1
        else
            echo "Enter root password to change IO scheduler for $selected_disk"
            su -c "echo '$selected_ioscheduler' > /sys/block/$(basename "$selected_disk")/queue/scheduler"
        fi
    fi

    # Check if pkexec or sudo/su failed (exit status != 0)
    if [ $? -ne 0 ]; then
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --error "$ERROR_MESSAGE"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --error --title "Error" --text "$ERROR_MESSAGE"
        elif [ $gui_tool = "whiptail" ]; then
            # Since we're already in console with sudo we don't need a whiptail error msgbox here.
            echo "$ERROR_MESSAGE"
        fi
        exit 1  # Exit the script if pkexec failed
    else
        if [ $gui_tool = "kdialog" ]; then
            $gui_tool --title "Success" --msgbox "$set_success"
        elif [ $gui_tool = "zenity" ]; then
            $gui_tool --info --width 400 --title "Success" --text "$set_success"
        elif [ $gui_tool = "whiptail" ]; then
            $gui_tool --title "Success" --msgbox "$set_success" 8 45
        fi
        # Done, return to main window.
        main
    fi
}

# Main shebang
# Some stuff had to be done in main() because of whiptail weirdness. :(
main() {
    # Get available disks
    local disks=$(lsblk -d -n -p -o NAME | grep -v '/dev/loop'| sort)

    # Disk menu list for kdialog and whiptail
    local disk_menu_items=()
    for disk in $disks; do
        disk_label=$(basename "$disk")
        disk_menu_items+=("$disk_label" "$disk")  # Label = disk name, Description = full path
    done

    if [ $gui_tool = "kdialog" ]; then
        local selected_disk=$($gui_tool --menu "$DISK_SELECTION_MESSAGE" --title "$DISK_SELECTION_TITLE" "${disk_menu_items[@]}")
    elif [ $gui_tool = "zenity" ]; then
        local selected_disk=$($gui_tool --list --width=450 --height=490 --title "$DISK_SELECTION_TITLE" --column "$DISK_SELECTION_MESSAGE" $disks)
    elif [ $gui_tool = "whiptail" ]; then
        selected_disk=$($gui_tool --title "$DISK_SELECTION_TITLE" --menu "$DISK_SELECTION_MESSAGE" 25 30 10 \
    "${disk_menu_items[@]}" 3>&1 1>&2 2>&3)
    fi

    if [ -z "$selected_disk" ]; then
        # Exit if no disk was selected
        exit 1
    fi


    #################################################
    ### Disk is selected, now select IO scheduler ###
    #################################################

    local ioschedulers=$(cat /sys/block/$(basename "$selected_disk")/queue/scheduler | tr ' ' '\n')
    local column_text=$(printf "$IOSCHEDULER_SELECTION_MESSAGE $selected_disk\n$ACTIVE_SCHED_MESSAGE")

    # IO sched list for kdialog and whiptail
    local io_menu_items=()
    for iosched in $ioschedulers; do
        io_menu_items+=("$iosched" "$iosched")
    done

    if [ $gui_tool = "kdialog" ]; then
        local selected_ioscheduler=$($gui_tool --menu "$IOSCHEDULER_SELECTION_MESSAGE $selected_disk\n$ACTIVE_SCHED_MESSAGE" --title "$IOSCHEDULER_SELECTION_TITLE" "${io_menu_items[@]}")
    elif [ $gui_tool = "zenity" ]; then
        local selected_ioscheduler=$($gui_tool --list --width=450 --height=490 --title "$IOSCHEDULER_SELECTION_TITLE" --column "$column_text" $ioschedulers)
    elif [ $gui_tool = "whiptail" ]; then
        selected_ioscheduler=$($gui_tool --title "$IOSCHEDULER_SELECTION_TITLE" --menu "$IOSCHEDULER_SELECTION_MESSAGE $selected_disk\n$ACTIVE_SCHED_MESSAGE" 20 60 8 \
    "${io_menu_items[@]}" 3>&1 1>&2 2>&3)
    fi

    if [ -z "$selected_ioscheduler" ]; then
        # No IO scheduler 5was selected, return to main menu
        main
    else
        apply_ioscheduler "$selected_disk" "$selected_ioscheduler"
    fi

}

# Execute the main function
main
