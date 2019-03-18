curl --header "Content-Type: application/json" --request POST --data '{"resourcename": "/resource/test-0001", "type": "errorrate", "value": 0.0}' http://localhost:3000/accidents

for (( i = 100; i < 10000; i = i * 10 )); do
	for (( j = 1; j < 10; j++ )); do
		curl --header "Content-Type: application/json" --request POST --data "{\"resourcename\": \"/resource/test-0001\",\"type\": \"calls\",\"value\": $(( i * j ))}" http://localhost:3000/accidents;
		sleep 300;
	done;
done;
