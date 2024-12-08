function friction () {
	echo friction haina fiction ho.
}

function loll () {
	echo lolipop
}

function hello () {
	while IFS='' read -r l || [[ -n "$l" ]]; do
		echo "$l"
		echo hawa tal ma
		friction
	done < lol
}

if [[ $(loll) == "lolipop" ]]; then
	echo lolipop kha
else
	echo hawa
fi