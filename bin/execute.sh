cp -vR rules/*2.7.yml prometheus/rules/
cp -vR rules/over_average_of_peaks.yml prometheus/rules/

docker-compose build

docker-compose up -d

#./bin/simulate.sh &
