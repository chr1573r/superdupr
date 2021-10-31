
   
#!/usr/bin/env bash
# superdupr
# Todo/Features wishlist:
# [ ] Ability to collect/display likely matches (same number of bytes, yet different checksum)
# [ ] Summarize all findings (number of GB possiple to save if all files were to be deduplicated)
# [ ] Sizefilter based on minumum saving per duplicate instead of filesize
# [ ] Store results to file
# [X] Implement progress bar
# [ ] Debug toggle
# [ ] Limit amount of files showed in duplicate summary. File x, y, z "and 2 other files"
# [X] Better OS compatibility (make it work on macOS, not just Linux)
# [ ] Support common sizes for sizefilter param (B,K,M,G,T)
# [ ] Help switch
# [X] Truncate when filenames are too long to prevent newlines during file scan
# [X] Add non-compact GUI, use this as default?
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


export prescan_counter=0
export prescan_done=false
echo "$prescan_counter" > /run/shm/superdupr_prescan

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
	tput civis
	current_object_name="$1"
	terminal_width=$(tput cols)
	while [[ ${#current_object_name} -ge $terminal_width ]]; do
		#echo "reduce loop[${#current_object_name} > $terminal_width]:"
		#echo "$current_object_name"
		local reduction=true
		current_object_name="${current_object_name:5}"
	done
	if [[ $reduction == true ]]; then
		current_object_name="... ${current_object_name}"
		current_object_name="${current_object_name:0:${terminal_width}}"
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
	local p1="$1"
	gui_super_fn condreset
	gui_super_fn recurse_print "$p1"																
}
gui_super_fn(){
	local p1="$1"
	local p2="$2"
	local p3="$3"

	case "$1" in
		init)
			reset
			gui_super_fn refresh_display_properties
			gui_super_fn header
			tput civis
			;;
		refresh_display_properties)
			header_height=6
			subheader_height=3
			content_offset="$(( header_height + subheader_height ))"

			terminal_width="$(tput cols)"
			terminal_height="$(tput lines)"

			terminal_x_center="$(( terminal_width / 2 ))"
			terminal_y_center="$(( terminal_height / 2 ))"

			# in case terminal width is in odd numbers
			if [[ $(( terminal_width % 2 )) -ne 0 ]]; then
				content_x_center="$(( terminal_x_center - 1 ))"
			else
				content_x_center="$terminal_x_center"
			fi

			if [[ $(( terminal_height % 2 )) -ne 0 ]]; then
				content_y_center="$(( (terminal_height - 1 + content_offset) / 2 ))"
			else
				content_y_center="$(( (terminal_height + content_offset) / 2 ))"
			fi

			progress_dialog_upper="$(( content_y_center - 4 ))"
			progress_dialog_lower="$(( content_y_center + 3 ))"
			progress_dialog_left="$(( content_x_center / 4 ))"
			progress_dialog_right="$(( terminal_width - content_x_center / 4 ))"
			progress_dialog_length=$(( progress_dialog_right - progress_dialog_left ))
			progress_dialog_height=$(( progress_dialog_lower - progress_dialog_upper ))

			progress_dialog_content_upper=$(( progress_dialog_upper + 2 ))
			progress_dialog_content_lower=$(( progress_dialog_lower - 2 ))
			progress_dialog_content_left=$(( progress_dialog_left + 3 ))
			progress_dialog_content_right=$(( progress_dialog_right - 3 ))
			progress_dialog_content_length=$(( progress_dialog_content_right - progress_dialog_content_left ))
			progress_dialog_content_height=$(( progress_dialog_content_lower - progress_dialog_content_upper ))

			progress_dialog_content_bar_y="$progress_dialog_content_upper"
			progress_dialog_content_bar_unit_size=$(( 100 * 100 / progress_dialog_content_length ))
			progress_dialog_content_bar_label_offset_x=$(( content_x_center - 2 ))
			progress_dialog_content_label_y="$(( progress_dialog_content_upper + 2 ))"

			progress_dialog_content_text_y="$(( progress_dialog_content_upper + 3 ))"



      		;;

		condreset)
			if [[ "$(tput cols)" -ne "$terminal_width" ]] || \
			[[ "$(tput lines)" -ne "$terminal_height" ]]; then
				clear
				echo "Resizing terminal.."
				sleep 0.1
				gui_super_fn init
				condreset=true
				return 0
			else
				condreset=false
				return 1
			fi
			;;
		move)
			#echo "Moving to X: $p3, Y: $p2"
			tput cup "$p3" "$p2"
			;;

		header)
			echo -e "${GREEN}  .dBBBBP   dBP dBP dBBBBBb  dBBBP dBBBBBb    dBBBBb  dBP dBP dBBBBBb dBBBBBb"
			echo -e "${MAGENTA}  BP                    dB'            dBP       dB'              dB'     dBP"
			echo -e "${GREEN}  \`BBBBb  dBP dBP   dBBBP' dBBP    dBBBBK   dBP dB' dBP dBP   dBBBP'  dBBBBK "
			echo -e "${GREEN}     dBP dBP_dBP   dBP    dBP     dBP  BB  dBP dB' dBP_dBP   dBP     dBP  BB "
			echo -e "${GREEN}dBBBBP' dBBBBBP   dBP    dBBBBP  dBP  dB' dBBBBB' dBBBBBP   dBP     dBP  dB'${DEF}"
			echo
			echo "superdupr started at $(date)"
			echo "Scanning ${scandir}... Size filter: $(( sizefilter / 1024 / 1024 ))M"
			tput sc
			;;

		recurse_print)
			shift
			if [[ "$recurse_files" -ne 0 ]]; then
				progress=$(( recurse_files + recurse_dirs ))

				if [[ "$prescan_done" == false ]] && [[ -d "/proc/$prescan_pid" ]]; then
					progress_total="$(</run/shm/superdupr_prescan)"
				else
					progress_total="$(</run/shm/superdupr_prescan)"
					prescan_done=true
					
				fi

				if [[ "$progress_total" -gt 0 ]]; then
					progress_percent=$(( progress * 100 / progress_total * 100 / 100 )) # imitate floating point arithmetic with integers
					if [[ "$progress_percent" -lt 10 ]]; then
						progress_percent_string=" ${progress_percent}% "
					elif [[ "$progress_percent" -ge 10 ]]; then
						progress_percent_string="${progress_percent} %"
					elif [[ "$progress_percent" -eq 100 ]]; then
						progress_percent_string="${progress_percent}%"
					fi
				else
					progress_percent=0
					progress_percent_string=" ${progress_percent}% "
				fi

				if [[ "$prescan_done" == true ]]; then
					progress_bar_string=""
					progress_bar_remainder=$((progress_percent * 100 ))
					while [[ ${progress_bar_remainder} -gt ${progress_dialog_content_bar_unit_size} ]]; do
						progress_bar_string="${progress_bar_string}█"
						progress_bar_remainder=$(( progress_bar_remainder - progress_dialog_content_bar_unit_size ))
						####DEBUG#### tput el
						####DEBUG#### echo "$progress_bar_remainder/$progress_percent/$progress_dialog_content_bar_unit_size:$progress_bar_string"
						####DEBUG#### sleep 0.1
						tput rc
					done
					progress_string="${progress}/${progress_total}"
				else
					progress_bar_string="(prescan in progress)"
					progress_percent_string=""
					progress_string="${progress}/${progress_total}++"
				fi

			fi
				current_object_name="$p2"

				while [[ ${#current_object_name} -ge $progress_dialog_content_length ]]; do
					#echo "reduce loop[${#current_object_name} > $progress_dialog_content_length]:"
					#echo "$current_object_name"
					local reduction=true
					current_object_name="${current_object_name:5}"
				done
				if [[ $reduction == true ]]; then
					current_object_name="... ${current_object_name}"
					current_object_name="${current_object_name:0:${progress_dialog_content_length}}"
					#echo "reduce result:"
					#echo "$current_object_name"
					#sleep 5
					#reset
				fi							
			#echo -e "${LIGHTBLACK}calls ${DEF}$recurse_calls${LIGHTBLACK} stack ${DEF}$recurse_stackdepth ${MAGENTA}#${LIGHTBLACK} files ${DEF}$recurse_files${LIGHTBLACK} dirs ${DEF}$recurse_dirs${LIGHTBLACK} depth ${DEF}$recurse_fsdepth ${MAGENTA}#${LIGHTBLACK} sizes ${DEF}$recurse_sizes${LIGHTBLACK} checksums ${DEF}$recurse_checksums ${MAGENTA}#${LIGHTBLACK} dupes ${DEF}${#superdupr_checksums[@]}${DEF}"
			#tput el
			####DEBUG#### clear
			####DEBUG#### echo "terminal_width:          $terminal_width"
			####DEBUG#### echo "terminal_height:         $terminal_height"
			####DEBUG#### echo
			####DEBUG#### echo "terminal_x_center:       $terminal_x_center"
			####DEBUG#### echo "terminal_y_center:       $terminal_y_center"
			####DEBUG#### echo "content_x_center:        $content_x_center"
			####DEBUG#### echo "content_y_center:        $content_y_center"
			####DEBUG####
			####DEBUG#### echo "progress_dialog_upper:   $progress_dialog_upper"
			####DEBUG#### echo "progress_dialog_lower:   $progress_dialog_lower"
			####DEBUG#### echo "progress_dialog_left:    $progress_dialog_left"
			####DEBUG#### echo "progress_dialog_right:   $progress_dialog_right"
			####DEBUG#### echo "progress_dialog_length:  $progress_dialog_length"
			####DEBUG#### 
			####DEBUG#### echo "progress_dialog_content_left:   $progress_dialog_content_left"
			####DEBUG#### echo "progress_dialog_content_right:  $progress_dialog_content_right"
			####DEBUG#### echo "progress_dialog_content_length: $progress_dialog_content_length"
			####DEBUG#### gui_super_fn move $progress_dialog_left $progress_dialog_upper && echo Q
			####DEBUG#### gui_super_fn move $progress_dialog_right $progress_dialog_upper && echo E
			####DEBUG#### gui_super_fn move $progress_dialog_left $progress_dialog_lower && echo A
			####DEBUG#### gui_super_fn move $progress_dialog_right $progress_dialog_lower && echo D
			####DEBUG#### gui_super_fn move $progress_dialog_content_left $progress_dialog_content_bar_y && echo BAR
			####DEBUG#### gui_super_fn move $progress_dialog_content_left $progress_dialog_content_label_y && echo LABEL
			####DEBUG#### gui_super_fn move $progress_dialog_content_left $progress_dialog_content_text_y && echo TEXT
			####DEBUG#### gui_super_fn move 0 $progress_dialog_lower
			####DEBUG#### echo
			####DEBUG#### echo
			####DEBUG#### exit
			tput rc
			echo
			tput el
			echo -e "${LIGHTBLACK} recurse calls            ${DEF}$recurse_calls          "
			echo -e "${LIGHTBLACK} recurse stackdepth       ${DEF}$recurse_stackdepth     "
			echo -e "${LIGHTBLACK} file counter             ${DEF}$recurse_files          "
			echo -e "${LIGHTBLACK} dir counter              ${DEF}$recurse_dirs           "
			echo -e "${LIGHTBLACK} current directory depth  ${DEF}$recurse_fsdepth        "
			echo -e "${LIGHTBLACK} files within size filter ${DEF}$recurse_sizes          "
			echo -e "${LIGHTBLACK} files checksummed        ${DEF}$recurse_checksums      "
			echo -e "${LIGHTBLACK} possible duplicates      ${DEF}${#superdupr_checksums[@]}${DEF}      "
			echo -e "${LIGHTBLACK} recurse action           ${DEF}$recurse_action         "
			gui_super_fn move $progress_dialog_left $progress_dialog_upper && echo ┌
			gui_super_fn move $progress_dialog_right $progress_dialog_upper && echo ┐
			gui_super_fn move $progress_dialog_left $progress_dialog_lower && echo └
			gui_super_fn move $progress_dialog_right $progress_dialog_lower && echo ┘
			gui_super_fn move $progress_dialog_content_left $progress_dialog_content_bar_y && tput el && echo -e "${LIGHTBLACK}${progress_bar_string}${DEF}"
			gui_super_fn move $progress_dialog_content_bar_label_offset_x $progress_dialog_content_bar_y && echo -e "${progress_percent_string}"
			gui_super_fn move $progress_dialog_content_left $progress_dialog_content_label_y && tput el && echo "Current object ($progress_string):"
			gui_super_fn move $progress_dialog_content_left $progress_dialog_content_text_y && tput el && echo "$current_object_name"
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
	superdupr_app recurse_trace "$1"

}

# prescan
# essentially does the same as recurse, but without any actual work
# counts how many files to process in the background, allowing superdupr to scan for duplicates at the same time
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
		echo "$prescan_counter" > /run/shm/superdupr_prescan
	done
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
	recurse_action="recurse dir" && recurse_trace "$1"
	(( recurse_calls++ ))
	(( recurse_stackdepth++ ))
	for i in "$1"/*; do
		if [[ -d "$i" ]] && ! [[ -L "$i" ]]; then
			(( recurse_dirs++ ))
			(( recurse_fsdepth++))
			recurse "$i"
			(( recurse_fsdepth--))
		elif [[ -f "$i" ]] && ! [[ -L "$i" ]]; then
			recurse_action="read file" && recurse_trace "$i"
			(( recurse_files++ ))
			size=$(get_filesize "$i")
			if [[ "$size" -gt "$sizefilter" ]] ; then
				(( superdupr_size_counter[${size}]++ ))
				(( recurse_sizes++ ))
				if [[ "${superdupr_size_counter[${size}]}" -eq "1" ]] ; then
					superdupr_size_first_occurence[${size}]="$i"
				fi
				if [[ "${superdupr_size_counter[${size}]}" -eq "2" ]] ; then
					recurse_action="checksumming" && recurse_trace "$i"
					crcsum=$(get_sum "${superdupr_size_first_occurence[${size}]}")
					superdupr_checksums[${crcsum}]="superdupr_filelist_checksum_$crcsum"
					superdupr_sizes[${crcsum}]="${size}"
					declare -n filelist="superdupr_filelist_checksum_$crcsum"
					filelist+=("${superdupr_size_first_occurence[${size}]}")
					(( recurse_checksums++ ))
				fi
				if [[ "${superdupr_size_counter[${size}]}" -ge "2" ]] ; then
					recurse_action="checksumming" && recurse_trace "$i"
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

superdupr_app(){
	case "$1" in
		init)
			trap trap_handler EXIT SIGTERM
			get_os
			if [[ "$os_family" == 'Unknown' ]]; then
				echo "Warning, unable to determine OS. Defaulting to generic Linux utilities syntax"
				sleep 1
			fi
			;;

		main)
			#"gui_${gui}"
			#"gui_${gui}" recurse_trace hello---world
			#exit
			prescan "$scandir" &
			prescan_pid=${!}
			
			recurse "$scandir"
			clear
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

			;;	
		recurse_trace)
			shift
			"gui_${gui}" "$1"
			;;
	esac
}
superdupr_app init
superdupr_app main

#echo "Prescan running with ${prescan_pid} ($prescan_counter), waiting"
#wait ${prescan_pid}