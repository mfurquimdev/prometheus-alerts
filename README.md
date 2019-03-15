# Alertas do Prometheus

Alerta de aumento anormal no número de requisições por segundo, utilizando o prometheus com visualização no grafana.

![Alerta de aumento anormal nas requisições](./img/Alerta_de_aumento_anormal_nas_requisicoes.png "Alerta de aumento anormal nas requisições")

No gráfico acima, a linha em verde representa a taxa de requisições por segundo (suavizada fazendo a média em um minuto). A linha em amarelo é a predição de qual a taxa de requisição em dez minuto, com base em quinze minutos de histórico. A linha em azul é a média dos picos da taxa de requisições. Por fim, a área vermelha representa os períodos em que a predição é maior que a média dos máximo. Caso isso continue a acontecer por dez minutos, um alerta será lançado

## Aumento no número de requisições por segundo

A simulação do aumento de requisições por segundo foi feita com um script em bash alterando o gerador de métricas. Mas antes disso, foi enviado uma requisição para zerar o número de requisições de erro (5xx). Isto garante que o número de requisições 2xx por segundo gerado é o mais próximo de 100% o possível. Ainda há algumas requisições 5xx, algo em torno de 60 requisições 5xx para cada 6000 2xx (1%).

```bash
curl --header "Content-Type: application/json" --request POST --data '{"resourcename": "/resource/test-0001", "type": "errorrate", "value": 0.0}' http://localhost:3000/accidents
```

Com a garantia de que 99% das requisições geradas pelo gerador são 2xx, foi escrito o script para aumentar gradualmente o número de requisições. Para isso, o script envia uma requisição POST a cada cinco minutos para o gerador usando o curl. Os dois loops aumentam as requisições de acordo com a seguinte série: 100, 200, 300, ..., 800, 900, 1000, 2000, 3000, ..., 8000, e 9000. Após 1.5h, o prometheus terá capturado as métrias e as _queries_ podem ser executadas em cima dos dados gerados.

```bash
for (( i = 100; i < 10000; i = i * 10 )); do
	for (( j = 1; j < 10; j++ )); do
		echo "$(( i * j ))";
		curl --header "Content-Type: application/json" --request POST --data \
      "{\"resourcename\": \"/resource/test-0001\",\"type\": \"calls\",\"value\": $(( i * j ))}" \
      http://localhost:3000/accidents;
		sleep 300;
	done;
done;
```

## Regras de armazenamento e de alerta

O teste foi realizado na versão 2.7 do prometheus por conta da facilidade com sub-queries, mas posteriormente foi traduzido para a versão 2.4 utilizando as _recording rules_.

A primeira regra é agregar, por `uri` e `status`, a taxa de requisições. Foi filtrado a `uri=/resource/test-0001` e `status="2xx"` para capturar apenas o grupo de requisições do gerador de acordo com o script acima.

```yml
# Rate of requests per second
- record: http_requests_seconds_summary_count:sum_irate1m
  expr:
    sum(
      irate(http_requests_seconds_summary_count{uri="/resource/test-0001", status="2xx"}[1m])
    ) by (uri, status)
```

O comportamento dessa expressão é relativamente caótico, com vários vales e picos. Para suavizar os dados, foi feito uma regra de média ao longo de um minuto. Todas as regras são baseadas nesta média.

```yml
# Average over time (1m) to make data smoother
- record: http_requests_seconds_summary_count:avg1m_sum_irate1m
  expr: avg_over_time( http_requests_seconds_summary_count:sum_irate1m[1m] )
```

Para predizer o número de requisições em um determinado tempo no futuro, foi utilizado a função `predict_linear`, que utiliza regressão linear internamente. Está sendo observado os últimos 15 minutos para predizer a taxa de requisições em 10 minutos a frente.

```yml
# Predict rate of requests in 10m based on smoothed data
- record: http_requests_seconds_summary_count:predict15m_avg1m_sum_irate1m
  expr: predict_linear( http_requests_seconds_summary_count:avg1m_sum_irate1m[15m], 600 ) > 0
```

Para realizar o alerta de crescimento anormal do número de requisições por segundo é preciso ter um limiar, adaptável de acordo com o histórico já observado. Um bom limiar é a média dos picos em um determinado tempo. Os picos são calculados com a função `max_over_time`, e está sendo observado até uma hora de dados. Para suavizar os dados, foi utilizado a média destes picos ao longo de três horas.

```yml
# Record max rate of requests over 1h based on smoothed data
- record: http_requests_seconds_summary_count:max1h_avg1m_sum_irate1m
  expr: max_over_time( http_requests_seconds_summary_count:avg1m_sum_irate1m[1h] )

# Average over time (3h) of peaks (max) rate of requests to use on alert
- record: http_requests_seconds_summary_count:avg3h_max1h_avg1m_sum_irate1m
  expr: avg_over_time( http_requests_seconds_summary_count:max1h_avg1m_sum_irate1m[3h] )
```

O alerta é disparado caso a predição supere, durante dez minutos, a média dos picos observados anteriormente.

```yml
  # If rate of requests per second is greater than the average of peaks
  - alert: http_requests_seconds_summary_count_abnormal_increase
    expr:
      http_requests_seconds_summary_count:predict15m_avg1m_sum_irate1m
      >
      http_requests_seconds_summary_count:avg3h_max1h_avg1m_sum_irate1m
    for: 10m
    annotations:
      description: Taxa de crescimento anormal da taxa de requisições por segundo, indicando quebra de recorde histórico. Versão do Centralizador '{{ $labels.component_version }}', Status '{{ $labels.status }}', Versão App '{{ $labels.device_app_version }}'.
      summary: Caso a predição sobre a média da taxa de requisições http do aplicativo supere a média dos picos durante dez minutos, um alerta será lançado.
```
