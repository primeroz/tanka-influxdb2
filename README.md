# tanka-influxdb2

```
./kind.sh create
tk env set --server-from-context=kind-kind environments/influxdb
tk apply environments/influxdb

kubectl port-forward -n influxdb service/influxdb 8086:8086

curl localhost:8086/metrics
```

* bootstrap by visiting http://localhost:8086
* Create a Token for the telgraf Daemonset using the UI 

```

tk env set --server-from-context=kind-kind environments/telegraf
tk apply environments/telegraf --ext-str telegraf_token=<TELEGRAF_TOKEN>
```

