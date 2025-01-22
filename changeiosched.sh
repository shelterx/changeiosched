#!/bin/bash

# Prevent window debug output for kdialog
export QT_LOGGING_RULES="*.debug=false"

# Genereal function to check for existing files
check_files_exist() {
    local filenames=("$@")  # Accept filenames as arguments

    for filename in "${filenames[@]}"; do
        if [ -f "$filename" ]; then
            return 0  # Return true if at least one file exists
        fi
    done

    return 1 # Exit the script if the file isn't found
}

# Check if we have kdialog installed.
filenames=('/usr/bin/kdialog' '/usr/local/bin/kdialog')
check_files_exist "${filenames[@]}"

if [ $? -ne 0 ]; then  # Check the exit status
    echo "This script depends on kdialog, please install it."
    exit
fi

# Check if we have pkexec installed.
filenames=('/usr/bin/pkexec' '/usr/local/bin/pkexec')
check_files_exist "${filenames[@]}"

if [ $? -ne 0 ]; then  # Check the exit status
    echo "This script depends on pkexec, please install it."
    exit
fi

# Function to select a disk
select_disk() {
    disks=$(lsblk -d -n -p -o NAME | grep -v '/dev/loop')
    selected_disk=$(echo "$disks" | kdialog --menu "Select a disk" --title "Disk Selection" $(awk '{print $1, $1}' <<< "$disks"))

    if [ -z "$selected_disk" ]; then
        # Exit if no disk was selected
        exit 1
    fi

    echo "$selected_disk"
}

# Function to select I/O scheduler
select_ioscheduler() {
    local selected_disk=$1
    ioschedulers=$(cat /sys/block/$(basename "$selected_disk")/queue/scheduler | tr ' ' '\n')

    selected_ioscheduler=$(echo "$ioschedulers" | kdialog --menu "Select I/O scheduler for $selected_disk.\nIO scheduler within [ ] is active" --title "I/O Scheduler Selection" $(awk '{print $1, $1}' <<< "$ioschedulers"))

    if [ -z "$selected_ioscheduler" ]; then
        # no IO Sched was selected, return to main menu
        main
    else
    apply_ioscheduler "$selected_disk" "$selected_ioscheduler"
    fi

    echo "$selected_ioscheduler"
}

# Function to apply the selected I/O scheduler
apply_ioscheduler() {
    local selected_disk=$1
    local selected_ioscheduler=$2

    sync

    echo "$selected_ioscheduler" | pkexec tee /sys/block/$(basename "$selected_disk")/queue/scheduler > /dev/null
    # Check if pkexec failed (exit status != 0)
    if [ $? -ne 0 ]; then
        kdialog --error "Failed to apply I/O scheduler. The password may have been incorrect or the operation was canceled." --title "Error"
        exit 1  # Exit the script if pkexec failed
    else
        kdialog --msgbox "I/O scheduler for $selected_disk is set to $selected_ioscheduler"
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
