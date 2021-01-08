local ksm = import 'kube-state-metrics.libsonnet';

(import 'influxdb/telegraf.libsonnet') +
ksm {
  name: 'kube-state-metrics',
  namespace: 'kube-system',
  version: '1.9.7',
  image: 'quay.io/coreos/kube-state-metrics:v' + self.version,
}
