#!/bin/bash
# supdup2 - superdupr
# Todo/Features wishlist:
# - Ability to collect/display likely matches (same number of bytes, yet different checksum)
# - Summarize all findings (number of GB possiple to save if all files were to be deduplicated)
# - Sizefilter based on minumum saving per duplicate instead of filesize
# - Store results to file
# - Implement supdup visualiser
# - Debug toggle
# - Limit amount of files showed in duplicate summary. File x, y, z "and 2 other files"
#
# Known bugs
# - "Scanning.." message uses pwd instead of scandir to display scan location

scandir="$1"
! [[ -d "$1" ]] && echo -e "'$1' is not a valid directory." && exit
[[ -z "$2" ]] && sizefilter="0" || sizefilter="$2"
sizefilter=$(( sizefilter * 1024 * 1024 ))

recurse_calls=0
recurse_files=0
recurse_dirs=0
recurse_sizes=0
recurse_checksums=0

declare -A superdupr_size_counter
declare -A superdupr_sizes
declare -A superdupr_checksums


DEF="\x1b[0m"
GRAY="\x1b[37;0m"
LIGHTBLACK="\x1b[30;01m"
DARKGRAY="\x1b[30;11m"
LIGHTBLUE="\x1b[34;01m"
BLUE="\x1b[34;11m"
LIGHTCYAN="\x1b[36;01m"
CYAN="\x1b[36;11m"
LIGHTGRAY="\x1b[37;01m"
WHITE="\x1b[37;11m"
LIGHTGREEN="\x1b[32;01m"
GREEN="\x1b[32;11m"
LIGHTMAGENTA="\x1b[35;01m"
MAGENTA="\x1b[35;11m"
LIGHTRED="\x1b[31;01m"
RED="\x1b[31;11m"
LIGHTYELLOW="\x1b[33;01m"
YELLOW="\x1b[33;11m"

trap_handler(){
  echo "superdupr terminated at $(date)"
  tput sgr0
  tput cnorm
  exit
}

get_filesize(){
  stat -c%s "${1}"
}

get_sum(){
  shasum "${1}" | cut -f1 -d' '
}

recurse_trace(){
    tput rc
    tput el
    echo -n -e "${MAGENTA}r${GREEN}> ${LIGHTBLACK}calls ${DEF}$recurse_calls${LIGHTBLACK} stack ${DEF}$recurse_stackdepth ${MAGENTA}#${LIGHTBLACK} files ${DEF}$recurse_files${LIGHTBLACK} dirs ${DEF}$recurse_dirs${LIGHTBLACK} depth ${DEF}$recurse_fsdepth ${MAGENTA}#${LIGHTBLACK} sizes ${DEF}$recurse_sizes${LIGHTBLACK} checksums ${DEF}$recurse_checksums ${MAGENTA}#${LIGHTBLACK} dupes ${DEF}${#superdupr_checksums[@]}${DEF} ${MAGENTA}#${LIGHTBLACK} p1 ${DEF}${1}${DEF}"
}

# recurse
# recurse input directory
#   if directory is encountered, call recurse again with this dir as input
#   if file is encountered
#       get file size
#           if filesize higher than sizelimit threshold
#               store increment size counter for this size
#               store filename in first occurence array if it is first file of this exact size

recurse(){
    recurse_trace "$1"
    (( recurse_calls++ ))
    (( recurse_stackdepth++ ))
    for i in "$1"/*; do
        if [[ -d "$i" ]] && ! [[ -L "$i" ]]; then
            (( recurse_dirs++ ))
            (( recurse_fsdepth++))
            recurse "$i"
            (( recurse_fsdepth--))
        elif [[ -f "$i" ]] && ! [[ -L "$i" ]]; then
            recurse_trace "$i"
            (( recurse_files++ ))
            size=$(get_filesize "$i")
            if [[ "$size" -gt "$sizefilter" ]] ; then
                (( superdupr_size_counter[${size}]++ ))
                (( recurse_sizes++ ))
                if [[ "${superdupr_size_counter[${size}]}" -eq "1" ]] ; then
                    superdupr_size_first_occurence[${size}]="$i"
                fi
                if [[ "${superdupr_size_counter[${size}]}" -eq "2" ]] ; then
                    crcsum=$(get_sum "${superdupr_size_first_occurence[${size}]}")
                    superdupr_checksums[${crcsum}]="superdupr_filelist_checksum_$crcsum"
                    superdupr_sizes[${crcsum}]="${size}"
                    declare -n filelist="superdupr_filelist_checksum_$crcsum"
                    filelist+=("${superdupr_size_first_occurence[${size}]}")
                    (( recurse_checksums++ ))
                fi
                if [[ "${superdupr_size_counter[${size}]}" -ge "2" ]] ; then
                    crcsum="$(get_sum "$i")"
                    superdupr_checksums[${crcsum}]="superdupr_filelist_checksum_$crcsum"
                    superdupr_sizes[${crcsum}]="${size}"
                    declare -n filelist="superdupr_filelist_checksum_$crcsum"
                    filelist+=("$i")
                    (( recurse_checksums++ ))
                fi
            fi
        fi
    done
    (( recurse_stackdepth-- ))
    recurse_trace "$1"
}

trap trap_handler EXIT SIGTERM SIGKILL
echo "superdupr started at $(date)"
echo "Scanning $(pwd)... Size filter: $(( sizefilter / 1024 / 1024 ))M"
tput sc
tput civis
recurse "$scandir"
echo
if [[ "${#superdupr_checksums[@]}" -ge 1 ]]; then
    echo -e "Found${LIGHTYELLOW}${#superdupr_checksums[@]}${DEF} possible duplicate(s)"
    echo
    fake_dupes=0
    duplicate_counter=1
    for sum in "${!superdupr_checksums[@]}"; do

        declare -n filelist=${superdupr_checksums[${sum}]}
        occurences="${#filelist[@]}"
        filesize=$(( superdupr_sizes[${sum}] / 1024 / 1024 ))
        totalsize=$(( filesize * occurences))
        sizesave=$(( filesize * occurences - filesize ))

        if [[ "$occurences" -gt 1 ]]; then
            echo -e "${LIGHTYELLOW}Duplicate #${duplicate_counter}${DEF} - ${LIGHTBLACK}$sum${DEF}:"
            for file in "${filelist[@]}"; do
                echo " $file"
            done
            echo
            echo -e " ${occurences} occurences x ${filesize}M = ${totalsize}M (${GREEN}${sizesave}M can be reclaimed${DEF})"
            echo
            echo -e "$LIGHTBLACK#########################################$DEF"
            echo
            echo
            ((duplicate_counter++))
        else
            (( fake_dupes++ ))
        fi

    done
    echo "${fake_dupes} entries was not printed since they matched on filesize only, not checksum"
else
    echo -e "${GREEN}No duplicates found!${DEF}"
fi
