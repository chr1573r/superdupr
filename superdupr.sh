
   
#!/usr/bin/env bash
# superdupr
# Todo/Features wishlist:
# [ ] Ability to collect/display likely matches (same number of bytes, yet different checksum)
# [ ] Summarize all findings (number of GB possiple to save if all files were to be deduplicated)
# [ ] Sizefilter based on minumum saving per duplicate instead of filesize
# [ ] Store results to file
# [ ] Implement supdup visualiser
# [ ] Debug toggle
# [ ] Limit amount of files showed in duplicate summary. File x, y, z "and 2 other files"
# [X] Better OS compatibility (make it work on macOS, not just Linux)
# [ ] Support common sizes for sizefilter param (B,K,M,G,T)
# [ ] Help switch
# [X] Truncate when filenames are too long to prevent newlines during file scan
# [ ] Add non-compact GUI, use this as default?
# [ ] Strip uneccessary trailing forwardslash from $1
# [ ] Verify that $1 is a directory
# Known bugs
# - Filename truncation does not seem to work with non-latin characters (such as japanese hiragana)

scandir="$1"
! [[ -d "$1" ]] && echo -e "'$1' is not a valid directory." && exit
[[ -z "$2" ]] && sizefilter="0" || sizefilter="$2"
sizefilter=$(( sizefilter * 1024 * 1024 ))

gui=super

recurse_calls=0
recurse_stackdepth=0
recurse_files=0
recurse_dirs=0
recurse_fsdepth=0
recurse_sizes=0
recurse_checksums=0
superdupr_checksums=0


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
	tput cnorm
	tput sgr0
	exit
}

get_os(){
	# fallback and Linux will use assume GNU/Linux binaries, not BSD binaries/syntax
	os_family="Unknown"
	os_id="Fallback"
	os_filesize_in_bytes='stat -c%s'

	if [[ -f '/etc/os-release' ]]; then
		 source /etc/os-release
		 os_family=Linux
		 os_id=$ID
	elif hash sw_vers &> /dev/null; then
		os_family=Darwin
		os_id=$(sw_vers -productName)
		os_filesize_in_bytes='stat -f%z'
	fi

}
gui_compact(){
	current_object_name="$1"
	display_length=$(tput cols)
	while [[ ${#current_object_name} -ge $display_length ]]; do
		#echo "reduce loop[${#current_object_name} > $display_length]:"
		#echo "$current_object_name"
		local reduction=true
		current_object_name="${current_object_name:5}"
	done
	if [[ $reduction == true ]]; then
		current_object_name="... ${current_object_name}"
		current_object_name="${current_object_name:0:${display_length}}"
		#echo "reduce result:"
		#echo "$current_object_name"
		#sleep 5
		#reset
	fi
	tput rc
	tput el
	echo -e "${MAGENTA}r${GREEN}> ${LIGHTBLACK}calls ${DEF}$recurse_calls${LIGHTBLACK} stack ${DEF}$recurse_stackdepth ${MAGENTA}#${LIGHTBLACK} files ${DEF}$recurse_files${LIGHTBLACK} dirs ${DEF}$recurse_dirs${LIGHTBLACK} depth ${DEF}$recurse_fsdepth ${MAGENTA}#${LIGHTBLACK} sizes ${DEF}$recurse_sizes${LIGHTBLACK} checksums ${DEF}$recurse_checksums ${MAGENTA}#${LIGHTBLACK} dupes ${DEF}${#superdupr_checksums[@]}${DEF}"
	tput el
	echo -e "${current_object_name}"
}

gui_super(){
	p1="$1"
	if [[ "$gui_super_init" == true ]]; then
		gui_super_fn recurse_print "$p1"
	else
		gui_super_fn init
		gui_super_fn header
		gui_super_init=true
	fi																		
}
gui_super_fn(){
	p1="$1"
	p2="$2"
	case "$1" in
		init)
			clear
			;;
		header)
			echo -e "${GREEN}  .dBBBBP   dBP dBP dBBBBBb  dBBBP dBBBBBb    dBBBBb  dBP dBP dBBBBBb dBBBBBb"
			echo -e "${MAGENTA}  BP                    dB'            dBP       dB'              dB'     dBP"
			echo -e "${GREEN}  \`BBBBb  dBP dBP   dBBBP' dBBP    dBBBBK   dBP dB' dBP dBP   dBBBP'  dBBBBK "
			echo -e "${GREEN}     dBP dBP_dBP   dBP    dBP     dBP  BB  dBP dB' dBP_dBP   dBP     dBP  BB "
			echo -e "${GREEN}dBBBBP' dBBBBBP   dBP    dBBBBP  dBP  dB' dBBBBB' dBBBBBP   dBP     dBP  dB'${DEF}"
			echo
			tput sc
			;;
		recurse_print)
			shift
			tput rc
			tput el
			if [[ "$recurse_files" -ne 0 ]]; then
				progress=$(( recurse_files + recurse_dirs ))
				progress_percent=$(( progress * 100 / prescan_counter * 100 / 100 )) # imitate floating point arithmetic with integers
			fi

			echo "${progress}/${prescan_counter} (${progress_percent}%)"
			#echo -e "${LIGHTBLACK}calls ${DEF}$recurse_calls${LIGHTBLACK} stack ${DEF}$recurse_stackdepth ${MAGENTA}#${LIGHTBLACK} files ${DEF}$recurse_files${LIGHTBLACK} dirs ${DEF}$recurse_dirs${LIGHTBLACK} depth ${DEF}$recurse_fsdepth ${MAGENTA}#${LIGHTBLACK} sizes ${DEF}$recurse_sizes${LIGHTBLACK} checksums ${DEF}$recurse_checksums ${MAGENTA}#${LIGHTBLACK} dupes ${DEF}${#superdupr_checksums[@]}${DEF}"
			tput el
			echo "$p2"
			;;
		stats_print)

	esac
}


get_filesize(){
	${os_filesize_in_bytes} "${1}"
}

get_sum(){
  shasum "${1}" | cut -f1 -d' '
}

recurse_trace(){
	"gui_${gui}" "$1"
}

# recurse
# recurse input directory
#   if directory is encountered, call recurse again with this dir as input
#   if file is encountered
#       get file size
#           if filesize higher than sizelimit threshold
#               store increment size counter for this size
#               store filename in first occurence array if it is first file of this exact size
prescan(){
	for i in "$1"/*; do
		if [[ -d "$i" ]] && ! [[ -L "$i" ]]; then
			#echo dir
			prescan "$i"
			(( prescan_counter++ ))
		elif [[ -f "$i" ]] && ! [[ -L "$i" ]]; then
			#echo fil: "$i"
			(( prescan_counter++ ))
		fi
	done
}
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

trap trap_handler EXIT SIGTERM
clear
echo "superdupr started at $(date)"
get_os
if [[ "$os_family" == 'Unknown' ]]; then
	echo "Warning, unable to determine OS. Defaulting to generic Linux utilities syntax"
fi
echo "Scanning ${scandir}... Size filter: $(( sizefilter / 1024 / 1024 ))M"
prescan "$scandir"
tput sc
tput civis
recurse "$scandir"
echo
if [[ "${#superdupr_checksums[@]}" -ge 1 ]]; then
	echo -e "Found ${LIGHTYELLOW}${#superdupr_checksums[@]}${DEF} possible duplicate(s)"
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

