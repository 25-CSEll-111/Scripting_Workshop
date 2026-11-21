#!/bin/bash

rooms_db="rooms.txt"
bookings_db="bookings.txt"

init_db() {
    if [[ ! -f "$rooms_db" ]]; then
        cat <<EOF > "$rooms_db"
101,AC,Available,2500
102,AC,Available,2500
103,Non-AC,Available,1500
104,Non-AC,Available,1500
201,AC,Available,3500
EOF
    fi
    if [[ ! -f "$bookings_db" ]]; then
        touch "$bookings_db"
    fi
}

valid_date() {
    local date_str="$1"
    if [[ "$date_str" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
        return 0
    else
        return 1
    fi
}

view_rooms() {
    echo -e "\n--- ROOM DIRECTORY ---"
    printf "%-10s %-12s %-15s %-10s\n" "RoomNo" "Type" "Status" "Price/Night"
 
    while IFS=',' read -r room_no type status price; do
        printf "%-10s %-12s %-15s %-10s\n" "$room_no" "$type" "$status" "₹$price"
    done < "$rooms_db"
 
}

book_room() {
    view_rooms
    read -p "Enter Room Number to book: " room_no

    room_record=$(grep "^${room_no}," "$rooms_db")
    if [[ -z "$room_record" ]]; then
        echo "Error: Room $room_no does not exist."
        return
    fi

    status=$(echo "$room_record" | cut -d',' -f3)
    if [[ "$status" != "Available" ]]; then
        echo "Error: Room $room_no is currently $status."
        return
    fi

    read -p "Enter Guest Name: " guest_name
    if [[ -z "$guest_name" ]]; then
        echo "Error: Guest name cannot be empty."
        return
    fi

    while true; do
        read -p "Enter Check-In Date (DD-MM-YYYY): " checkin_date
        if valid_date "$checkin_date"; then
            break
        else
            echo "Invalid format! Please use DD-MM-YYYY (e.g., 25-11-2026)."
        fi
    done

    while true; do
        read -p "Enter Number of Nights: " nights
        if [[ "$nights" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo "Invalid input! Enter a positive number."
        fi
    done

    awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r {$3="Booked"} {print}' "$rooms_db" > "${rooms_db}.tmp" && mv "${rooms_db}.tmp" "$rooms_db"

    echo "${room_no},${guest_name},${checkin_date},${nights},Pending" >> "$bookings_db"
    echo "Success! Room $room_no booked for $guest_name starting $checkin_date."
}

check_in() {
    echo -e "\n To check in: "
    grep ",Pending$" "$bookings_db" | awk -F',' '{printf "Room: %s | Guest: %s | Date: %s | Nights: %s\n", $1, $2, $3, $4}'
    echo "-------------------------"

    read -p "Enter Room Number for Check-In: " room_no

    if grep -q "^${room_no},.*,Pending$" "$bookings_db"; then
        awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r && $5=="Pending" {$5="Checked-In"} {print}' "$bookings_db" > "${bookings_db}.tmp" && mv "${bookings_db}.tmp" "$bookings_db"
        echo "Success! Guest in Room $room_no has been checked in."
    else
        echo "Error: No pending booking found for Room $room_no."
    fi
}

init_db
while true; do
    echo -e "\n=== HOTEL BOOKING SYSTEM ==="
    echo "1. View Room Database"
    echo "2. Book a Room"
    echo "3. Guest Check-In"
    echo "4. Exit"
    read -p "Choose an option [1-4]: " choice

    case $choice in
        1) view_rooms ;;
        2) book_room ;;
        3) check_in ;;
        4) echo "Exiting system. Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
