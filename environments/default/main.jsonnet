(import 'influxdb/influxdb.libsonnet') +
(import 'influxdb/telegraf.libsonnet') +
{
  local ns = $.core.v1.namespace,

  influxdb_namespace: ns.new('influxdb'),

}
