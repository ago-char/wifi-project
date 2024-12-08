#! /bin/bash

if [[ $UID -ne 0 ]]; then
	echo run as root
	exit 1
fi

nmcli &> /dev/null
status=$(echo $?)
if [[ status -ne 0 ]]; then
	airmon-ng stop wlp4s0mon
	systemctl start NetworkManager.service
	if [[ $1 == "del" ]]; then
		rm -rf cracker/
	fi
	if [[ $2 == "driver" ]] || [[ $1 == "driver" ]]; then
		modprobe -r iwlmvm && modprobe iwlmvm
	fi
fi
