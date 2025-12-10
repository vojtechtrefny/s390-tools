#!/bin/bash
# Test script for fdasd --script mode
#
# This script tests the script mode functionality of fdasd, including:
# - Creating partitions
# - Removing partitions
# - Changing partition types
#
# Usage: test_script_mode.sh <device>
#
# Example: test_script_mode.sh /dev/dasda
#
# WARNING: This test will destroy all data on the specified device!

set -e

# Check if device is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <device>"
    echo "Example: $0 /dev/dasda"
    exit 1
fi

DEVICE="$1"
[ -z "$FDASD_PATH" ] && FDASD_PATH=".."
FDASD=$FDASD_PATH/fdasd

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        if [ -n "$details" ]; then
            echo -e "       ${details}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Helper function to verify partition exists
partition_exists() {
    local part_num="$1"
    $FDASD -p "$DEVICE" 2>/dev/null | grep -q "${DEVICE}${part_num}"
    return $?
}

# Helper function to count partitions
count_partitions() {
    $FDASD -p "$DEVICE" 2>/dev/null | grep -c "^[[:space:]]*${DEVICE}" || true
}

# Helper function to get partition type
get_partition_type() {
    local part_num="$1"
    $FDASD -p "$DEVICE" 2>/dev/null | grep "${DEVICE}${part_num}" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//'
}

# Helper function to get partition start track
get_partition_start() {
    local part_num="$1"
    $FDASD -p "$DEVICE" 2>/dev/null | grep "${DEVICE}${part_num}" | awk '{print $2}'
}

# Helper function to get partition end track
get_partition_end() {
    local part_num="$1"
    $FDASD -p "$DEVICE" 2>/dev/null | grep "${DEVICE}${part_num}" | awk '{print $3}'
}

# Helper function to get partition length
get_partition_length() {
    local part_num="$1"
    $FDASD -p "$DEVICE" 2>/dev/null | grep "${DEVICE}${part_num}" | awk '{print $4}'
}

# Helper function to verify partition geometry
# Sets global variable GEOMETRY_ERROR_DETAILS on failure
verify_partition_geometry() {
    local part_num="$1"
    local expected_start="$2"
    local expected_end="$3"
    local expected_length="$4"

    local actual_start=$(get_partition_start "$part_num")
    local actual_end=$(get_partition_end "$part_num")
    local actual_length=$(get_partition_length "$part_num")

    if [ "$actual_start" = "$expected_start" ] && \
       [ "$actual_end" = "$expected_end" ] && \
       [ "$actual_length" = "$expected_length" ]; then
        GEOMETRY_ERROR_DETAILS=""
        return 0
    else
        GEOMETRY_ERROR_DETAILS="Expected partition $part_num: start=$expected_start, end=$expected_end, length=$expected_length\n       Actual partition $part_num:   start=$actual_start, end=$actual_end, length=$actual_length"
        return 1
    fi
}

echo "========================================="
echo "fdasd Script Mode Test Suite"
echo "========================================="
echo "Device: $DEVICE"
echo "fdasd: $FDASD"
echo ""

# Verify device exists
if [ ! -b "$DEVICE" ]; then
    echo -e "${RED}Error: Device $DEVICE does not exist or is not a block device${NC}"
    exit 1
fi

# Verify fdasd is available
if ! command -v "$FDASD" &> /dev/null; then
    echo -e "${RED}Error: fdasd not found${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will destroy all data on $DEVICE!${NC}"
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Initializing device with auto-partition..."
# Initialize the device with a single partition using auto mode
$FDASD -a "$DEVICE" >/dev/null 2>&1 || true

echo ""
echo "Running tests..."
echo ""

# Test 1: Remove all existing partitions
echo "Test 1: Removing all existing partitions"
PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -gt 0 ]; then
    DELETE_CMDS=""
    for i in $(seq 1 "$PART_COUNT"); do
        DELETE_CMDS="${DELETE_CMDS}d 1 "
    done
    $FDASD --script "${DELETE_CMDS}w" "$DEVICE" >/dev/null 2>&1
fi

PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -eq 0 ]; then
    print_test_result "Remove all partitions" "PASS"
else
    ERROR_DETAILS="Expected: 0 partitions\n       Actual:   $PART_COUNT partitions"
    print_test_result "Remove all partitions" "FAIL" "$ERROR_DETAILS"
fi

# Test 2: Create a single partition
echo "Test 2: Creating a single partition (tracks 2-1000)"
$FDASD --script "n 2 1000 w" "$DEVICE" >/dev/null 2>&1

if partition_exists "1" && verify_partition_geometry "1" "2" "1000" "999"; then
    print_test_result "Create single partition (with correct size)" "PASS"
else
    if ! partition_exists "1"; then
        ERROR_DETAILS="Partition 1 does not exist"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Create single partition (with correct size)" "FAIL" "$ERROR_DETAILS"
fi

# Test 3: Create multiple partitions
echo "Test 3: Creating multiple partitions"
# Remove existing partition first
$FDASD --script "d 1 w" "$DEVICE" >/dev/null 2>&1
# Create three partitions
$FDASD --script "n 2 1000 n 1001 2000 n 2001 3000 w" "$DEVICE" >/dev/null 2>&1

PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -eq 3 ] && \
   verify_partition_geometry "1" "2" "1000" "999" && \
   verify_partition_geometry "2" "1001" "2000" "1000" && \
   verify_partition_geometry "3" "2001" "3000" "1000"; then
    print_test_result "Create multiple partitions (with correct sizes)" "PASS"
else
    if [ "$PART_COUNT" -ne 3 ]; then
        ERROR_DETAILS="Expected: 3 partitions\n       Actual:   $PART_COUNT partitions"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Create multiple partitions (with correct sizes)" "FAIL" "$ERROR_DETAILS"
fi

# Test 4: Remove specific partition (middle one)
echo "Test 4: Removing partition 2"
$FDASD --script "d 2 w" "$DEVICE" >/dev/null 2>&1

PART_COUNT=$(count_partitions)
# After removing partition 2, we should have partitions 1 and 2 (was 3, renumbered)
# Partition 1: tracks 2-1000
# Partition 2: tracks 2001-3000 (was partition 3)
if [ "$PART_COUNT" -eq 2 ] && \
   verify_partition_geometry "1" "2" "1000" "999" && \
   verify_partition_geometry "2" "2001" "3000" "1000"; then
    print_test_result "Remove middle partition (verify renumbering)" "PASS"
else
    if [ "$PART_COUNT" -ne 2 ]; then
        ERROR_DETAILS="Expected: 2 partitions after removal\n       Actual:   $PART_COUNT partitions"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Remove middle partition (verify renumbering)" "FAIL" "$ERROR_DETAILS"
fi

# Test 5: Change partition type
echo "Test 5: Changing partition type"
# Partition type 1 is Linux native, 2 is Linux swap
# Get initial geometry
INITIAL_TYPE=$(get_partition_type "1")

# Change to swap (type 2) - geometry should not change
$FDASD --script "t 1 2 w" "$DEVICE" >/dev/null 2>&1
NEW_TYPE=$(get_partition_type "1")

if [ "$NEW_TYPE" = "Linux swap" ] && verify_partition_geometry "1" "2" "1000" "999"; then
    print_test_result "Change partition type to swap (size preserved)" "PASS"
else
    if [ "$NEW_TYPE" != "Linux swap" ]; then
        ERROR_DETAILS="Expected type: Linux swap\n       Actual type:   $NEW_TYPE"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Change partition type to swap (size preserved)" "FAIL" "$ERROR_DETAILS"
fi

# Change back to native (type 1) - geometry should not change
$FDASD --script "t 1 1 w" "$DEVICE" >/dev/null 2>&1
NEW_TYPE=$(get_partition_type "1")

if [ "$NEW_TYPE" = "Linux native" ] && verify_partition_geometry "1" "2" "1000" "999"; then
    print_test_result "Change partition type to native (size preserved)" "PASS"
else
    if [ "$NEW_TYPE" != "Linux native" ]; then
        ERROR_DETAILS="Expected type: Linux native\n       Actual type:   $NEW_TYPE"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Change partition type to native (size preserved)" "FAIL" "$ERROR_DETAILS"
fi

# Test 6: Multiple operations in one command
echo "Test 6: Multiple operations in single command"
# Start fresh: remove all, create 2 partitions, change type of first to swap
$FDASD --script "d 1 d 1 n 2 500 n 501 1000 t 1 2 w" "$DEVICE" >/dev/null 2>&1

PART_COUNT=$(count_partitions)
TYPE1=$(get_partition_type "1")
TYPE2=$(get_partition_type "2")

if [ "$PART_COUNT" -eq 2 ] && \
   [ "$TYPE1" = "Linux swap" ] && \
   [ "$TYPE2" = "Linux native" ] && \
   verify_partition_geometry "1" "2" "500" "499" && \
   verify_partition_geometry "2" "501" "1000" "500"; then
    print_test_result "Multiple operations in one command (with sizes)" "PASS"
else
    ERROR_DETAILS=""
    if [ "$PART_COUNT" -ne 2 ]; then
        ERROR_DETAILS="Expected: 2 partitions, Actual: $PART_COUNT partitions"
    fi
    if [ "$TYPE1" != "Linux swap" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       Expected partition 1 type: Linux swap, Actual: $TYPE1"
    fi
    if [ "$TYPE2" != "Linux native" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       Expected partition 2 type: Linux native, Actual: $TYPE2"
    fi
    if [ -n "$GEOMETRY_ERROR_DETAILS" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       ${GEOMETRY_ERROR_DETAILS}"
    fi
    print_test_result "Multiple operations in one command (with sizes)" "FAIL" "$ERROR_DETAILS"
fi

# Test 7: Recreate VTOC
echo "Test 7: Recreating VTOC with 'r' command"
# First, verify we have partitions from previous test
PART_COUNT_BEFORE=$(count_partitions)

# Recreate VTOC - this should delete all partitions
$FDASD --script "r w" "$DEVICE" >/dev/null 2>&1

PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -eq 0 ]; then
    print_test_result "Recreate VTOC (all partitions deleted)" "PASS"
else
    ERROR_DETAILS="Expected: 0 partitions after VTOC recreation\n       Actual:   $PART_COUNT partitions"
    print_test_result "Recreate VTOC (all partitions deleted)" "FAIL" "$ERROR_DETAILS"
fi

# Test 7b: Create partition after VTOC recreation to verify VTOC is functional
echo "Test 7b: Creating partition after VTOC recreation"
$FDASD --script "n 2 1500 w" "$DEVICE" >/dev/null 2>&1

if partition_exists "1" && verify_partition_geometry "1" "2" "1500" "1499"; then
    print_test_result "Create partition after VTOC recreate (verify functional)" "PASS"
else
    if ! partition_exists "1"; then
        ERROR_DETAILS="Partition 1 does not exist after VTOC recreation"
    else
        ERROR_DETAILS="$GEOMETRY_ERROR_DETAILS"
    fi
    print_test_result "Create partition after VTOC recreate (verify functional)" "FAIL" "$ERROR_DETAILS"
fi

# Test 7c: Recreate VTOC and create partitions in one command
echo "Test 7c: Recreate VTOC and create partitions in one command"
# This tests that 'r' can be combined with 'n' commands
$FDASD --script "r n 2 800 n 801 1600 t 2 2 w" "$DEVICE" >/dev/null 2>&1

PART_COUNT=$(count_partitions)
TYPE1=$(get_partition_type "1")
TYPE2=$(get_partition_type "2")

if [ "$PART_COUNT" -eq 2 ] && \
   [ "$TYPE1" = "Linux native" ] && \
   [ "$TYPE2" = "Linux swap" ] && \
   verify_partition_geometry "1" "2" "800" "799" && \
   verify_partition_geometry "2" "801" "1600" "800"; then
    print_test_result "Recreate VTOC with new partitions in one command" "PASS"
else
    ERROR_DETAILS=""
    if [ "$PART_COUNT" -ne 2 ]; then
        ERROR_DETAILS="Expected: 2 partitions, Actual: $PART_COUNT partitions"
    fi
    if [ "$TYPE1" != "Linux native" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       Expected partition 1 type: Linux native, Actual: $TYPE1"
    fi
    if [ "$TYPE2" != "Linux swap" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       Expected partition 2 type: Linux swap, Actual: $TYPE2"
    fi
    if [ -n "$GEOMETRY_ERROR_DETAILS" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}\n       ${GEOMETRY_ERROR_DETAILS}"
    fi
    print_test_result "Recreate VTOC with new partitions in one command" "FAIL" "$ERROR_DETAILS"
fi

# Test 8: Exit command (using 'q' instead of 'w')
echo "Test 8: Testing 'q' (quit without writing)"
# Create a partition without writing
$FDASD --script "d 1 q" "$DEVICE" >/dev/null 2>&1

# Partition should still exist since we didn't write
PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -eq 1 ]; then
    print_test_result "Quit without writing (partitions unchanged)" "PASS"
else
    ERROR_DETAILS="Expected: 1 partition (unchanged)\n       Actual:   $PART_COUNT partitions"
    print_test_result "Quit without writing (partitions unchanged)" "FAIL" "$ERROR_DETAILS"
fi

# Clean up: remove all partitions
echo ""
echo "Cleaning up..."
PART_COUNT=$(count_partitions)
if [ "$PART_COUNT" -gt 0 ]; then
    DELETE_CMDS=""
    for i in $(seq 1 "$PART_COUNT"); do
        DELETE_CMDS="${DELETE_CMDS}d 1 "
    done
    $FDASD --script "${DELETE_CMDS}w" "$DEVICE" >/dev/null 2>&1 || true
fi

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo "========================================="

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
