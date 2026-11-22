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
    local d="$1"
    if [[ ! "$d" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
        return 1
    fi
    local day=$((10#${d:0:2}))
    local month=$((10#${d:3:2}))
    if (( day < 1 || day > 31 || month < 1 || month > 12 )); then
        return 1
    fi
    return 0
}

view_rooms() {
    echo -e "\nRoom Directory: "
    printf "%-10s %-12s %-15s %-10s\n" "RoomNo" "Type" "Status" "Price/Night"
    while IFS=',' read -r room_no type status price; do
        printf "%-10s %-12s %-15s %-10s\n" "$room_no" "$type" "$status" "₹$price"
    done < "$rooms_db"
}

view_bookings() {
    echo -e "\nAll Bookings: "
    if [[ ! -s "$bookings_db" ]]; then
        echo "No bookings yet."
        return
    fi
    printf "%-8s %-20s %-12s %-8s %-12s\n" "Room" "Guest" "Check-In" "Nights" "Status"
    while IFS=',' read -r room guest date nights status; do
        printf "%-8s %-20s %-12s %-8s %-12s\n" "$room" "$guest" "$date" "$nights" "$status"
    done < "$bookings_db"
}

book_room() {
    view_rooms
    read -r -p "Enter Room Number to book: " room_no

    if [[ ! "$room_no" =~ ^[0-9]+$ ]]; then
        echo "Error: Room number must be digits only."
        return
    fi

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

    read -r -p "Enter Guest Name: " guest_name
    if [[ -z "$guest_name" ]]; then
        echo "Error: Guest name cannot be empty."
        return
    fi

    while true; do
        read -r -p "Enter Check-In Date (DD-MM-YYYY): " checkin_date
        if valid_date "$checkin_date"; then
            break
        else
            echo "Invalid date! Please use DD-MM-YYYY (e.g., 25-11-2026)."
        fi
    done

    while true; do
        read -r -p "Enter Number of Nights: " nights
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
    echo -e "\nPending bookings: "
    if ! grep -q ",Pending$" "$bookings_db"; then
        echo "No pending bookings."
        return
    fi
    grep ",Pending$" "$bookings_db" | awk -F',' '{printf "Room: %s | Guest: %s | Date: %s | Nights: %s\n", $1, $2, $3, $4}'

    read -r -p "Enter Room Number for Check-In: " room_no
    if [[ ! "$room_no" =~ ^[0-9]+$ ]]; then
        echo "Error: Room number must be digits only."
        return
    fi

    if grep -q "^${room_no},.*,Pending$" "$bookings_db"; then
        awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r && $5=="Pending" {$5="Checked-In"} {print}' "$bookings_db" > "${bookings_db}.tmp" && mv "${bookings_db}.tmp" "$bookings_db"
        awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r {$3="Occupied"} {print}' "$rooms_db" > "${rooms_db}.tmp" && mv "${rooms_db}.tmp" "$rooms_db"
        echo "Success! Guest in Room $room_no has been checked in."
    else
        echo "Error: No pending booking found for Room $room_no."
    fi
}

check_out() {
    echo -e "\nGuests currently checked in: "
    if ! grep -q ",Checked-In$" "$bookings_db"; then
        echo "No guests checked in."
        return
    fi
    grep ",Checked-In$" "$bookings_db" | awk -F',' '{printf "Room: %s | Guest: %s | Nights: %s\n", $1, $2, $4}'

    read -r -p "Enter Room Number for Check-Out: " room_no
    if [[ ! "$room_no" =~ ^[0-9]+$ ]]; then
        echo "Error: Room number must be digits only."
        return
    fi

    booking=$(grep "^${room_no},.*,Checked-In$" "$bookings_db")
    if [[ -z "$booking" ]]; then
        echo "Error: No checked-in guest in Room $room_no."
        return
    fi

    guest=$(echo "$booking" | cut -d',' -f2)
    nights=$(echo "$booking" | cut -d',' -f4)
    price=$(grep "^${room_no}," "$rooms_db" | cut -d',' -f4)
    total=$((nights * price))

    echo -e "\n----- BILL -----"
    echo "Guest : $guest"
    echo "Room  : $room_no"
    echo "Nights: $nights x ₹$price"
    echo "Total : ₹$total"
    echo "----------------"

    awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r && $5=="Checked-In" {$5="Checked-Out"} {print}' "$bookings_db" > "${bookings_db}.tmp" && mv "${bookings_db}.tmp" "$bookings_db"
    awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r {$3="Available"} {print}' "$rooms_db" > "${rooms_db}.tmp" && mv "${rooms_db}.tmp" "$rooms_db"
    echo "Room $room_no is now available."
}

cancel_booking() {
    read -r -p "Enter Room Number to cancel: " room_no
    if [[ ! "$room_no" =~ ^[0-9]+$ ]]; then
        echo "Error: Room number must be digits only."
        return
    fi

    if grep -q "^${room_no},.*,Pending$" "$bookings_db"; then
        awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r && $5=="Pending" {$5="Cancelled"} {print}' "$bookings_db" > "${bookings_db}.tmp" && mv "${bookings_db}.tmp" "$bookings_db"
        awk -F',' -v r="$room_no" 'BEGIN {OFS=","} $1==r {$3="Available"} {print}' "$rooms_db" > "${rooms_db}.tmp" && mv "${rooms_db}.tmp" "$rooms_db"
        echo "Booking for Room $room_no cancelled."
    else
        echo "Error: No pending booking found for Room $room_no."
    fi
}

init_db
while true; do
    echo -e "\nHotel Booking System: "
    echo "1. View Rooms"
    echo "2. Book a Room"
    echo "3. Guest Check-In"
    echo "4. Guest Check-Out"
    echo "5. Cancel Booking"
    echo "6. View All Bookings"
    echo "7. Exit"
    read -r -p "Choose an option [1-7]: " choice

    case $choice in
        1) view_rooms ;;
        2) book_room ;;
        3) check_in ;;
        4) check_out ;;
        5) cancel_booking ;;
        6) view_bookings ;;
        7) echo "Exiting system. Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
