docker pull mfurquim/metrics-generator:1.0.0
docker pull flaviostutz/grafana:5.2.4
docker pull prom/prometheus:v2.7.2

cp -vR dashboards/ grafana/provisioning/dashboards
cp -vR rules/*2.7.yml prometheus/rules/
cp -vR rules/over_average_of_peaks.yml prometheus/rules/

docker-compose build

docker-compose up -d

./bin/simulate.sh &
