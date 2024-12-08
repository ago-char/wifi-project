# perform some task every X seconds

(   SECONDS=0
    while   sleep   "$((RANDOM%10))"
    do      sleep   "$((10-(SECONDS%10)))"
            echo    "$SECONDS"
    done
)

# kill task after X seconds

# watchdog process
mainpid=$$
(sleep 5; kill $mainpid) &
watchdogpid=$!

# rest of script
while :
do
   ...stuff...
done
kill $watchdogpid

# THE FOLLOWING SHOULD BE THE APPROACH IF YOU CAN NOT CAPURE 'EAPOL' AFTER 'X' SECOND JUST GIVE UP!!

(
	# capture 
) &
capturepid=$!

(
	# deauth 
) &
deauthpid=$!

# watching now
timetowait=200
(sleep "$timetowait"; kill $deauthpid; kill capturepid) &
watchpid=$!

while true; do
	if grep "Handshake" cracker//errlog &> /dev/null; then
		kill $watchpid
		return 0
	fi
done

