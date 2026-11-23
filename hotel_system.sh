#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rooms_db="$script_dir/rooms.txt"
bookings_db="$script_dir/bookings.txt"

input_closed() {
    echo -e "\nInput closed. Exiting."
    exit 0
}

init_db() {
    if [[ ! -f "$rooms_db" ]]; then
        cat <<EOF > "$rooms_db"
101,AC,2500
102,AC,2500
103,Non-AC,1500
104,Non-AC,1500
201,AC,3500
EOF
    fi
    if [[ ! -f "$bookings_db" ]]; then
        touch "$bookings_db"
    fi
}

to_days() {
    local y=$((10#${1:6:4})) m=$((10#${1:3:2})) d=$((10#${1:0:2}))
    y=$(( y - (m <= 2) ))
    local era=$(( y / 400 ))
    local yoe=$(( y - era * 400 ))
    local doy=$(( (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1 ))
    local doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    echo $(( era * 146097 + doe - 719468 ))
}

from_days() {
    local z=$(( $1 + 719468 ))
    local era=$(( z / 146097 ))
    local doe=$(( z - era * 146097 ))
    local yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
    local doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
    local mp=$(( (5 * doy + 2) / 153 ))
    local d=$(( doy - (153 * mp + 2) / 5 + 1 ))
    local m=$(( mp < 10 ? mp + 3 : mp - 9 ))
    local y=$(( yoe + era * 400 + (m <= 2) ))
    printf "%02d-%02d-%04d\n" "$d" "$m" "$y"
}

add_nights() {
    from_days $(( $(to_days "$1") + $2 ))
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
    [[ "$(add_nights "$d" 0)" == "$d" ]]
}

room_status() {
    awk -F',' -v r="$1" -v today="$(date +%Y%m%d)" '
        function ymd(d) { return (substr(d, 7, 4) substr(d, 4, 2) substr(d, 1, 2)) + 0 }
        $2 == r && $7 == "Checked-In" { occupied = 1 }
        $2 == r && $7 == "Pending" && ymd($4) <= today + 0 && today + 0 < ymd($5) { booked = 1 }
        END { print (occupied ? "Occupied" : (booked ? "Booked" : "Available")) }
    ' "$bookings_db"
}

find_clashes() {
    awk -F',' -v r="$1" -v s="$2" -v e="$3" '
        function ymd(d) { return (substr(d, 7, 4) substr(d, 4, 2) substr(d, 1, 2)) + 0 }
        $2 == r && ($7 == "Pending" || $7 == "Checked-In") && ymd(s) < ymd($5) && ymd($4) < ymd(e) {
            printf "  Booking #%s | Guest: %s | %s to %s | %s\n", $1, $3, $4, $5, $7
        }
    ' "$bookings_db"
}

next_booking_id() {
    awk -F',' '$1 + 0 > max { max = $1 + 0 } END { print max + 1 }' "$bookings_db"
}

get_booking() {
    awk -F',' -v id="$1" '$1 == id' "$bookings_db"
}

set_booking_status() {
    awk -F',' -v id="$1" -v s="$2" 'BEGIN {OFS=","} $1 == id {$7 = s} {print}' "$bookings_db" > "${bookings_db}.tmp" && mv "${bookings_db}.tmp" "$bookings_db"
}

list_bookings() {
    awk -F',' -v s="$1" '
        $7 == s {
            printf "Booking #%s | Room: %s | Guest: %s | %s to %s | Nights: %s\n", $1, $2, $3, $4, $5, $6
            found = 1
        }
        END { exit !found }
    ' "$bookings_db"
}

prompt_booking_id() {
    read -r -p "$1" booking_id
    if [[ ! "$booking_id" =~ ^[0-9]+$ ]]; then
        echo "Error: Booking ID must be digits only."
        return 1
    fi
    IFS=',' read -r b_id b_room b_guest b_in b_out b_nights b_status <<< "$(get_booking "$booking_id")"
    if [[ -z "$b_id" ]]; then
        echo "Error: Booking #$booking_id does not exist."
        return 1
    fi
}

view_rooms() {
    echo -e "\nRoom Directory (status today): "
    printf "%-10s %-12s %-15s %-10s\n" "RoomNo" "Type" "Status" "Price/Night"
    while IFS=',' read -r room_no type price; do
        printf "%-10s %-12s %-15s %-10s\n" "$room_no" "$type" "$(room_status "$room_no")" "₹$price"
    done < "$rooms_db"
}

view_bookings() {
    echo -e "\nAll Bookings: "
    if [[ ! -s "$bookings_db" ]]; then
        echo "No bookings yet."
        return
    fi
    printf "%-5s %-6s %-20s %-12s %-12s %-7s %-12s\n" "ID" "Room" "Guest" "Check-In" "Check-Out" "Nights" "Status"
    while IFS=',' read -r id room guest checkin checkout nights status; do
        printf "%-5s %-6s %-20s %-12s %-12s %-7s %-12s\n" "$id" "$room" "$guest" "$checkin" "$checkout" "$nights" "$status"
    done < "$bookings_db"
}

book_room() {
    view_rooms
    read -r -p "Enter Room Number to book: " room_no

    if [[ ! "$room_no" =~ ^[0-9]+$ ]]; then
        echo "Error: Room number must be digits only."
        return
    fi

    if ! grep -q "^${room_no}," "$rooms_db"; then
        echo "Error: Room $room_no does not exist."
        return
    fi

    read -r -p "Enter Guest Name: " guest_name
    if [[ -z "$guest_name" ]]; then
        echo "Error: Guest name cannot be empty."
        return
    fi
    if [[ "$guest_name" == *,* ]]; then
        echo "Error: Guest name cannot contain commas."
        return
    fi

    while true; do
        read -r -p "Enter Check-In Date (DD-MM-YYYY): " checkin_date || [[ -n "$checkin_date" ]] || input_closed
        if valid_date "$checkin_date"; then
            break
        else
            echo "Invalid date! Please use DD-MM-YYYY (e.g., 25-11-2026)."
        fi
    done

    while true; do
        read -r -p "Enter Number of Nights: " nights || [[ -n "$nights" ]] || input_closed
        if [[ "$nights" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo "Invalid input! Enter a positive number."
        fi
    done

    checkout_date=$(add_nights "$checkin_date" "$nights")
    clashes=$(find_clashes "$room_no" "$checkin_date" "$checkout_date")
    if [[ -n "$clashes" ]]; then
        echo "Error: Room $room_no is already booked for part of $checkin_date to $checkout_date:"
        echo "$clashes"
        return
    fi

    booking_id=$(next_booking_id)
    echo "${booking_id},${room_no},${guest_name},${checkin_date},${checkout_date},${nights},Pending" >> "$bookings_db"
    echo "Success! Booking #$booking_id: Room $room_no for $guest_name, $checkin_date to $checkout_date."
}

check_in() {
    echo -e "\nPending bookings: "
    if ! list_bookings "Pending"; then
        echo "No pending bookings."
        return
    fi

    prompt_booking_id "Enter Booking ID for Check-In: " || return
    if [[ "$b_status" != "Pending" ]]; then
        echo "Error: Booking #$b_id is $b_status, not Pending."
        return
    fi

    if [[ "$(room_status "$b_room")" == "Occupied" ]]; then
        echo "Error: Room $b_room is still occupied by another guest."
        return
    fi

    set_booking_status "$b_id" "Checked-In"
    echo "Success! $b_guest (Booking #$b_id) checked in to Room $b_room."
}

check_out() {
    echo -e "\nGuests currently checked in: "
    if ! list_bookings "Checked-In"; then
        echo "No guests checked in."
        return
    fi

    prompt_booking_id "Enter Booking ID for Check-Out: " || return
    if [[ "$b_status" != "Checked-In" ]]; then
        echo "Error: Booking #$b_id is $b_status, not Checked-In."
        return
    fi

    price=$(grep "^${b_room}," "$rooms_db" | cut -d',' -f3)
    total=$((b_nights * price))

    echo -e "\n----- BILL -----"
    echo "Guest : $b_guest"
    echo "Room  : $b_room"
    echo "Stay  : $b_in to $b_out"
    echo "Nights: $b_nights x ₹$price"
    echo "Total : ₹$total"
    echo "----------------"

    set_booking_status "$b_id" "Checked-Out"
    echo "Room $b_room is now available."
}

cancel_booking() {
    echo -e "\nPending bookings: "
    if ! list_bookings "Pending"; then
        echo "No pending bookings."
        return
    fi

    prompt_booking_id "Enter Booking ID to cancel: " || return
    if [[ "$b_status" != "Pending" ]]; then
        echo "Error: Booking #$b_id is $b_status, not Pending."
        return
    fi

    set_booking_status "$b_id" "Cancelled"
    echo "Booking #$b_id for Room $b_room cancelled."
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
    read -r -p "Choose an option [1-7]: " choice || [[ -n "$choice" ]] || input_closed

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
