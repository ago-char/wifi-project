# Getting wifi list and saving file <available_APs> i.e aval_APs
`nmcli dev wifi list | sed 's/\*/ /' > aval_APs`

# Columns
`head -1 aval_APs`
in-use bssid(ap) ssid(wifi_name) mode chan rate signal bars security
0		1			2				3   4	5		6	7	   8

# we will need only col 1,2,4,8  better use :
`nmcli dev wifi list | sed 's/\*/ /' | awk '{print $1, $2, $4, $8}' > aval_APs`

# well `nmcli` gives us selection option as `-f`
`nmcli -f BSSID,SSID,CHAN,SECURITY dev wifi list > aval_APs`

# get the list of connected Aps, if any
`nmcli -t -f ACTIVE,SSID dev wifi | grep '^yes' | cut -d ':' -f 2`

# you can get list of APs, your device has already password of
`nmcli -t -f NAME,TYPE connection | grep wireless | cut -d ':' -f 1`
# well those passwords maybe stored from failed connection, so better verify
# well there may be situation that your device already know the password of nearby APs, so try connecting each one (no pw required as device already has cached), we will wait for 5 second, if not connected it should give some err, the purpose of doing this is we will want to exclude such APs from our attack 
`sudo nmcli --wait 5 dev wifi connect 'some_wifi'`


*remember by default `airodump-ng` lists only 2.4GHz wifi, you need to specify `--band a` to list ony 5GHz wifi, for both use `--band abg`*

# network adapter list
`ls /sys/class/net/`

# wireless adapter
`iw dev | awk '/Interface/ {print $2}'`
`nmcli -t dev st | grep "wifi:" | awk -F ':' '{print $1}'`

# use `--band a` to capture 5GHz only with `airodump-ng`, use `--band abg` for all, default is `b|g`

# remove duplicates from file
`awk '!seen[$0]++' file > output.txt && mv output.txt file`



# monitor mode for $apapter in $channel
what we have is just name of AP : 'helloAp'
we will have to find : channel number, where 'helloAp' advertises and its freq (not needed)
we will have to find : mac add or bssid of that 'helloAp'
we will only go into monitor mode if the wifi 'helloAp' is still available
how to check if it is still available ? go see nmcli output or that previously captured (but this could be useless because we have spent alot of time since that step has been performed.)

# parsing can be challenging sometimes, but hey les go me need mac addres from here
`nmcli -t -f BSSID,SSID,CHAN,SECURITY dev wifi list`


output will be like this : `74\:3C\:18\:C9\:86\:89:gopal999_fbrtc:8:WPA1 WPA2` and converted to :
nmcli -t -f BSSID,SSID,CHAN,SECURITY dev wifi list |  awk -F: '{print $1":"$2":"$3":"$4":"$5":"$6}'  | sed 's/\\:/:/g' 
we get: 74:3C:18:C9:86:89 lesgo


```
(
.......
) &
pid=$!
```
`kill $pid` will simply not work here because, in the list of grouped commands, there may be commands like 'aircrack-ng', 'sleep', those will intend to occupy the terminal/shell, they will have different pid, so killing just pid of backgrounded task won't help, you should kill it's all sub process as such `kill -- -$pid`, this `$pid` is acutally process group ID, which is able to kill all the process on its group, since (...)& is grouping, `$!` is group ID. You can find group PID from any of othter PID on that group except for group PID itself, which is root PID for that group, use : `group_pid=$(ps -o pgid= $other_pid | grep -o '[0-9]*')`