(import 'k.libsonnet') +
(import 'ksonnet-util/kausal.libsonnet') +
{
  _config+:: {
    influxdb: {
      labels: {
        app: 'influxdb',
      },
      replicas: 1,
      statefulset_disk: '10G',
      service_ignored_labels: [],
    },
  },

  _images+:: {
    influxdb: 'quay.io/influxdb/influxdb:v2.0.3',
  },

  local ss = $.apps.v1.statefulSet,
  local container = $.core.v1.container,
  local containerPort = $.core.v1.containerPort,
  local volumeMount = $.core.v1.volumeMount,
  local pvc = $.core.v1.persistentVolumeClaim,
  local volume = $.core.v1.volume,

  influxdb_pvc::
    pvc.new('influx-data') +
    pvc.mixin.spec.resources.withRequests({ storage: $._config.influxdb.statefulset_disk }) +
    pvc.mixin.spec.withAccessModes(['ReadWriteOnce']),

  influxdb_container::
    container.new('influxdb', $._images.influxdb) +
    container.withPorts(containerPort.newNamed(name='influxdb', containerPort=8086)) +
    container.withVolumeMountsMixin(
      volumeMount.new($.influxdb_pvc.metadata.name, '/root/.influxdbv2')
    ),

  influxdb_statefulset:
    ss.new(
      'influxdb',
      $._config.influxdb.replicas,
      $.influxdb_container,
      [$.influxdb_pvc],
      $._config.influxdb.labels
    ) +
    ss.metadata.withNamespace('influxdb') +
    ss.metadata.withLabelsMixin($._config.influxdb.labels) +
    ss.mixin.spec.withServiceName('influxdb'),
  // statefulSet.mixin.spec.template.spec.securityContext.withRunAsUser(0) +
  // resources

  influxdb_service: $.util.serviceFor($.influxdb_statefulset, $._config.influxdb.service_ignored_labels) +
                    $.core.v1.service.spec.withType('ClusterIP'),
}
