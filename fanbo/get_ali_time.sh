#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: get_ali_time.sh align_with_length_file"
	exit -1
fi

phone=data/lang/phones.txt

#awk,get phone_map
awk -v phone_map=$phone  'BEGIN{
	while(getline < phone_map) {
		map[$2] = $1
	}
	FS=";"
}
{
	cur=0
	split($1, arr, " ")
	printf("%s    ", arr[1]) #file name
	#key=arr[2] 
	#print key, map[key], map["1"] 
	printf("%s %d %d ; ", map[arr[2]], cur, cur+arr[3])
	cur+=arr[3]
	for(i=2; i<=NF; i++) {
		split($i, arr, " ")
		printf("%s %d %d ; ", map[arr[1]], cur, cur+arr[2])
		cur+=arr[2]
	}
	printf("\n")
}
END{
#	for(x in map)
#		print x, map[x]
}' $1
