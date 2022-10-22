#!/usr/bin/env bash

### Begin config

## IMPORTANT: Configure 'audioFile' and 'enableAudio' vars to have audio alerts.

# General config
loopDelay="31" # Loop delay in minutes to check for new build. 
dateTimeFormat="+%F %T" # 'yyyy-mm-dd hh:mm:ss' for output log (see 'man date')
usePager=1 # 1 = use a pager to display patch note. 0 = dumps to stdout
pager="/usr/bin/less" # less, more, most, etc.
clearScreenEachResult=1 # Clears the screen for every build result for a cleaner look

# Audio config
enableAudio=0  # Alert audio sound: 1 = true, 0 = false
audioFile=""
audioLoopDelay=3   # In seconds. Needs to exceed audio duration
audioMaxLoops=10   # Max number of times the audio file will be played
audioPlayer="/usr/bin/paplay" # paplay, mplayer, mpv, etc. 
audioPlayerOpts="--" # i.e. '-novideo' for mplayer. If nothing, then use "--" to prevent error.

# URL config
curlOpts="-sA 'Mozilla/5.0 (X11; Linux x86_64; rv:105.0) Gecko/20100101 Firefox/105.0'"
indexUrl="https://pastebin.com/u/tzAria" # The Pastebin URL for user that posts the pastes
rawPostUrl="https://pastebin.com/raw/" # The paste key (ID) will be appended to end of this URL

# Parsing operation config
# 	sed commands are in dual-indexed array b/c sed disliking literal quotes in '-e' args
lineGrepOpts="-Em1" # First match only; use extended RegEx
lineGrepString='^.*<a href.*>Evocati.*$' # Retrieves first href line that matches 'Evocati'
idSedString=('s|^.*\<a href=\"/||' 's|\">.*$||') # Parses paste key aka paste ID 
titleSedString=('s|^.*<a href=.*\">||' 's|</a>.*$||') # Parses title of the paste

# Misc & logging config
scriptName="${0%.*}" scriptName="${scriptName##*/}" # just filename with path and ext removed.
scriptVer="1.0"
logFile="./output.log" # Log file is overwritten on each script invocation
logIpAddress=0 # 1 = write outside IP address to the log, 0 = don't
depends=('curl' 'grep' 'sed') # on_init() will check dependencies
pasteKeyFile="./paste-key-history.txt" # where Paste keys (id) are stored for comparison

### End config
### Begin functions

## The MIT License (MIT). See LICENSE file included with this script.

on_init () {
	
	# Prompt if root
	if [[ "$EUID" -eq 0 ]]
	then
		local isRoot=1 # Holding off writing to log file until prepared
		echo -e "\n$scriptName is running as root. This is not recommended.\n"

		read -p "Do you wish to continue? (y/Y)es, or any other key to exit: " -N1

		if [[ "$REPLY" != [Yy] ]]
		then
			on_error 1 "User-initiated abort, is root."
		fi
	fi

	# Prepare the logFile
	if [[ ! "$(file -b $logFile)" =~ 'ASCII text' ]]
	then
		on_error 2 "Error: $logFile is not an ASCII file! Exiting."
	else
		touch "$logFile"
		[[ "$?" -ne 0 ]] && on_error 2 "Error: Cannot write to ${logFile}! Exiting."
	fi

	audioPlayerOuts=${audioPlayerOpts:---} # If empty or unset
	
	# Overwrite redirect for clean logFile
	echo "$(date "$dateTimeFormat"): New $scriptName v$scriptVer log file created." > "$logFile"

	# The log is now available
	write_log 0 " ---- "
	write_log 0 "on_init() was called from main."

	# Log that user is running as root.
	[[ "$isRoot" -eq 1 ]] && write_log 0 "Script running as root! User was prompted."

	# Write outside IP to logFile if enabled in above config
	[[ "$logIpAddress" -eq 1 ]] && write_log 0 "IP address: $(curl -s ifconfig.me)"

	# Create temp files
	tempIndex=$(mktemp --suffix="-${scriptName}-index.output")
	[[ "$?" -ne 0 ]] && on_error 3 "Error: mktemp cannot write to temp directory! Exiting."

	write_log 0 "$tempIndex temp file created."

#	tempRaw=$(mktemp --suffix="-${scriptName}-raw.output")
#	write_log 0 "$tempRaw temp file created."
	
	# Dependency check
	for dep in "${depends[@]}"
	do
		type -p $dep &>/dev/null
	       	[[ "$?" -gt 0 ]] && on_error 4 "Error: $dep not found. Exiting."
		write_log 0 "$dep found at $(type -p $dep)"
	done

	# Check for audio file and player if audio is enabled
	if [[ "$enableAudio" -eq 1 ]]
	then
		write_log 0 "Alert audio is ENABLED."
		[[ -e "$audioFile" ]] || on_error 8 "Error: audio file $audioFile does not exist. Exiting."
		type -p "$audioPlayer" &>/dev/null || on_error 8 "Can't locate ${audioPlayer}. Check config. Exiting."
	else
		write_log 0 "Alert audio is DISABLED."
	fi

	write_log 0 "Audio file found at $(type -p $audioFile)"
	write_log 0 "Audio player found at $(type -p $audioPlayer)"

}


get_paste_index () {
	
	write_log 0 "get_paste_index() called."
	write_log 0 "Running curl to get paste index from $indexUrl"

	# by default, curlOpts is using -s silent option to stdout
	curl "$curlOpts" "$indexUrl" > "$tempIndex"
	[[ "$?" -ne 0 ]] && write_log 1 "Curl exited with $? on this run." && return 1

	if [ -s "$tempIndex" ]
	then
		write_log 0 "$tempIndex returned with data. ($(wc -l <$tempIndex) lines)"
	else
		write_log 1 "Nothing was output by curl to $tempIndex"
		write_log 0 "Returning to main loop due to error. Check parsing."
		return 1
	fi

	return 0

}


parse_paste_index () {

	write_log 0 "parse_paste_index() called."

	# Grep relevant line from curl output
	local line=$(grep "$lineGrepOpts" "$lineGrepString" "$tempIndex")

	write_log 0 "Grep output (${#line} chars): $line"

	if [[ "${#line}" -le 70 ]]
	then
	       	write_log 1 "Grep parse contains only ${#line} chars. (Expected >90)"
		write_log 0 "Continuing. If failure results, check $tempIndex output."
	fi

	# Sed to extract Paste key
	pasteId=$(sed -e "${idSedString[0]}" -e "${idSedString[1]}" <<<"$line")

	write_log 0 "Sed Paste key output: $pasteId"

	if [[ "${#pasteId}" -ne 8 ]] # Pastebin keys contain 8 [a-z A-Z 0-9] characters
	then
		write_log 1 "Sed Paste key output contains ${#pasteId} chars! (expected 8)"
		write_log 0 "Returning to main loop due to error. Check parsing."
		unset pasteId
		return 1
	fi

	# Sed to extract Paste title
	pasteTitle=$(sed -e "${titleSedString[0]}" -e "${titleSedString[1]}" <<< "$line")

	write_log 0 "Sed Paste title output: $pasteTitle"

	if [[ "${#pasteTitle}" -le 18 ]]
	then
		write_log 1 "Sed Paste title output contains ${#pasteTitle} chars! (expected >20)"
		write_log 0 "Returning to main loop due to error. Check parsing."
		unset pasteId pasteTitle
		return 1
	fi

	compare_index_link "$pasteId" "$pasteTitle"
		
}


compare_index_link () {
	
	# args are global vars, but using this to check validity of call
	write_log 0 "compare_index_link() called with args: $@"

	# function requires >=2 args
	if [[ "$#" -lt 2 ]]
	then
		write_log 1 "compare_index_link() called without at least 2 arguments."
		write_log 0 "Returning to main loop due to error."
		return 1
	fi

	touch "$pasteKeyFile"
	[[ "$?" -ne 0 ]] && on_error 7 "Couldn't write to ${pasteKeyFile}. Exiting."

	if grep "$pasteId" "$pasteKeyFile" &>/dev/null
	then
		local new=0
		write_log 0 "Paste key $pasteId matched in ${pasteKeyFile}. Old build."
	else
		local new=1
		write_log 0 "Paste key $pasteId did not match in ${pasteKeyFile}. NEW build."
		echo "$pasteId" >> "$pasteKeyFile"
		write_log 0 "$pasteId written to pasteKeyFile ${pasteKeyFile}."
	fi

	print_index_result "$new"

}


print_index_result () {
	
	# $1=0 same build, $1=1 new build
	# globals from previous function: pasteId, pasteTitle
	
	# \e[2J = clear screen, \e[H = send cursor to 0,0
	[[ "$clearScreenEachResult" -eq 1 ]] && printf '\e[2J\e[H'

	write_log 0 "print_index_result() called with arg: $@"

	if [[ "$#" -lt 1 ]]
	then
		write_log 1 "print_index_result() called without an argument."
		write_log 0 "Returning to main loop due to error."
		unset pasteId pasteTitle
		return 1
	fi

	if [[ "$1" -eq 0 ]] # change to "1" to debug "new build" code.
	then
		echo -e "\nNo new Evocati build detected."
		echo -e "Title: ${pasteTitle}\n"
		echo -e "\nNext check in $loopDelay minutes."
		return 0
	else
		play_audio

		echo -e "\nNEW EVOCATI BUILD DETECTED!\n"
		echo -e "Title: ${pasteTitle}\n"
		echo -e "\nRead patch notes? (y)es or any other key to exit: "

		read -sN1

		kill "$audioPID" 2>>"$logFile"
		write_log 0 "Killing audio loop process $audioPID"

		# Ensure the subshell process has ended, otherwise on_exit() will SIGKILL it.
		ps | grep "$audioPID" &>/dev/null || unset audioPID
		
		if [[ "$REPLY" == [Yy] ]]
		then
			write_log 0 "User requested print_raw_paste()."
			print_raw_paste

		else [[ "$REPLY" == [Nn] ]]
			write_log 0 "User requested to exit without print_raw_paste()."
			on_exit 0
		fi


	fi

}


print_raw_paste () {
	
	write_log 0 "print_raw_paste() called."
	
	if [[ "$usePager" -eq 1 ]]
	then
		curl "$curlOpts" "${rawPostUrl}${pasteId}" | "$pager"
	else
		curl "$curlOpts" "${rawPostUrl}${pasteId}"
	fi

	on_exit 0

}

play_audio () {

	if [[ "$enableAudio" -eq 0 ]] 
	then
		write_log 0 "Not playing audio file, is disabled."
		return
	fi
	
	# Subshell loop process for playing audio.
	( 
	inc=0
	write_log 0 "Audio loop PID: $BASHPID"

       	while [[ "$inc" -lt "$audioMaxLoops" ]]
	do

		$audioPlayer "$audioPlayerOpts" "$audioFile" 2>>"$logFile"
		sleep "$audioLoopDelay"
		((inc++))

	done

	echo "!Audio alert has ended. audioMaxLoops = $audioMaxLoops"
	unset inc

	) & audioPID="$!" # Track PID


}

#read_sleep () { # Issues with implementation. Will look more into it later.
#	
	# read_sleep 1, read_sleep 0.1 etc. 
	# Sleeping without an external command. Read times $1 to the next file descriptor
	#    while reading : (true) from a subshell. If fails, always returns true.
#	read -rt "$1" <> <(:) || :

#}

write_log () {

	# if $1 = 1, "ERROR:" is prefixed to message line
	# on_exit() will automatically write error to log

	if [[ "$1" -ne 0 ]]
	then
		local logError="ERROR: "
	else
		local logError=""
	fi       
	
	echo "$(date "$dateTimeFormat"): ${logError}${@:2}" >> "$logFile"
	[[ "$verbose" -eq 1 ]] && echo "::${logError}${@:2}"

}


on_error () {

	# 1=user-initiated abort, 2=log file write error
	# 3=/tmp/ write error,    4=dependency missing
	# 6=curl error,           7=parsing error
	# 8=audio error,          9=main 'function' exit
       	# 99=termination signal (except SIGKILL)

	write_log 0 "on_error() called with args: $@"
	errMsg="${@:2} Exit code $1"
	write_log 0 "Exiting script. Args: $@"

	on_exit "$1"

}


on_exit () {
	
	printf '\e[u' # Restore cursor position

	[[ "$1" -gt 0 ]] && echo -e "\n${errMsg}\nDetailed logs at $logFile"
	echo -e "\nExiting ${scriptName}."

	write_log 0 "on_exit() called. Exiting script."

	# Handy to clean up even the temp files as some bash environments, such
        #	as Cygwin, like to keep them around unless custom scheduled.
	rm -f "$tempIndex"
	write_log 0 "Cleaned up temp file(s): $tempIndex"
	unset pasteId pasteTitle

	trap SIGHUP SIGINT SIGTERM # clear out our traps
	
	# SIGKILL audio loop subshell process if it exists.
	#    audioLoopDelay may be set too low.
	if [[ ! -z "$audioPID" ]]
	then
		write_log 1 "Audio loop PID $audioPID was not killed properly, passing SIGKILL."
		kill -9 "$audioPID" 2>/dev/null
	fi

	exit "$1"

}


on_signal () {
	
	echo -e "\nCleaning up and exiting..."

	write_log 1 "${1}! on_signal() invoked."
	on_error 99 "Signal received: $1."

}

### End functions
### Begin main()

trap "on_signal SIGHUP" SIGHUP
trap "on_signal SIGINT" SIGINT
trap "on_signal SIGTERM" SIGTERM

case "$1" in
	-v|--verbose) verbose=1;;
esac

# Initial run
on_init
get_paste_index # called seperately so return can bring it to the main loop.
[[ "$?" -ne 1 ]] && parse_paste_index   # not called if returned /w error.

write_log 0 "Entering main loop. Configured for $loopDelay minutes."

# Main infinite loop
loop=0
while true
do

	sleep 60
	((loop++))

	if [[ "$((loopDelay - loop))" -ne 0 ]]
	then
		# Using ANSI escape sequences to keep timer on one line
		#    \e[s = save cusrsor pos, \e[1A = cursor up 1 line, \e[2K = erase line
		printf '\e[s\e[1A\e[2K'
		echo "Next check in $((loopDelay - loop)) minutes."
	fi

	if [[ "$loop" -eq "$loopDelay" ]]
	then
		write_log 0 "--- Main loop has reached loop $loop of ${loopDelay}. Calling functions."
		printf '\e[s\e[1A\e[2K' # erase our timer
		get_paste_index 
		[[ "$?" -ne 1 ]] && parse_paste_index
		loop=0
	fi

done

on_error 9 "Reached end of main(). Script failed." # mostly for debugging

### End main()
### End script
