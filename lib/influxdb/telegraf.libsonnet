(import 'k.libsonnet') +
(import 'ksonnet-util/kausal.libsonnet') +
{
  _config+:: {
    telegraf: {
      labels: {
        app: 'telegraf',
      },
      service_ignored_labels: [],
    },
  },

  _images+:: {
    telegraf: 'telegraf:1.16.3',
  },

  local ds = $.apps.v1.daemonSet,
  local container = $.core.v1.container,
  local volumeMount = $.core.v1.volumeMount,
  local volume = $.core.v1.volume,
  local configMap = $.core.v1.configMap,

  telegraf_config_map:
    configMap.new('telegraf') +
    configMap.metadata.withNamespace('influxdb') +
    configMap.withData({
      'telegraf.conf': importstr 'configs/telegraf.conf',
    }),

  telegraf_container::
    container.new('telegraf', $._images.telegraf) +
    container.withEnvMixin([
      $.core.v1.envVar.fromFieldPath('HOSTNAME', 'status.nodeName'),
      $.core.v1.container.envType.new('HOST_PROC', '/rootfs/proc'),
      $.core.v1.container.envType.new('HOST_SYS', '/rootfs/sys'),
      $.core.v1.envVar.fromSecretRef('ENV', '<SECRET_NAME>', 'env'),
      $.core.v1.envVar.fromSecretRef('INFLUX_TOKEN', '<SECRET_NAME>', 'influx_token'),
    ]) +
    $.util.resourcesRequests('100m', '128Mi') +
    $.util.resourcesLimits('500m', '256Mi') +
    container.withVolumeMountsMixin([
      volumeMount.new('sys', '/rootfs/sys', true),
      volumeMount.new('proc', '/rootfs/proc', true),
      volumeMount.new('utmp', '/var/run/utmp', true),
      volumeMount.new('docker-socket', '/var/run/docker.sock', true),
    ]),

  telegraf_daemonset:
    ds.new(
      'telegraf',
      $.telegraf_container,
      $._config.telegraf.labels
    ) +
    ds.metadata.withNamespace('influxdb') +
    ds.metadata.withLabelsMixin($._config.telegraf.labels) +
    ds.spec.template.spec.withVolumesMixin([
      volume.fromHostPath('sys', '/sys'),
      volume.fromHostPath('proc', '/proc'),
      volume.fromHostPath('docker-socket', '/var/run/docker.sock'),
      volume.fromHostPath('utmp', '/var/run/utmp'),
    ]) +
    $.util.configMapVolumeMount($.telegraf_config_map, '/etc/telegraf') +
    ds.spec.template.spec.withTerminationGracePeriodSeconds(30),
  // statefulSet.mixin.spec.template.spec.securityContext.withRunAsUser(0) +

}
