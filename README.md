# tanka-influxdb2

```
./kind.sh create
tk env set --server-from-context=kind-kind environments/default
tk apply environment/default

kubectl port-forward -n influxdb service/influxdb 8086:8086

curl localhost:8086/metrics
```


