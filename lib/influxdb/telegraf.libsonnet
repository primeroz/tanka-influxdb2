(import 'k.libsonnet') +
(import 'ksonnet-util/kausal.libsonnet') +
{
  _config+:: {
    namespace: 'influxdb',
    telegraf: {
      labels: {
        app: 'telegraf',
      },
      service_ignored_labels: [],
      influx_token: std.extVar('telegraf_token'),
    },
  },

  _images+:: {
    telegraf: 'telegraf:1.16.3',
  },

  local ds = $.apps.v1.daemonSet,
  local deployment = $.apps.v1.deployment,
  local container = $.core.v1.container,
  local volumeMount = $.core.v1.volumeMount,
  local volume = $.core.v1.volume,
  local configMap = $.core.v1.configMap,
  local secret = $.core.v1.secret,
  local policyRule = $.rbac.v1.policyRule,

  telegraf_ds_rbac: $.util.rbac('telegraf-ds', [
    policyRule.withApiGroups(['']) +
    policyRule.withResources(['nodes/stats', 'nodes/metrics', 'nodes/proxy']) +
    policyRule.withVerbs(['get']),
    //policyRule.withApiGroups(['']) +
    //policyRule.withResources(['nodes', 'pods']) +
    //policyRule.withVerbs(['get']),
    policyRule.withNonResourceURLs(['/metrics']) +
    policyRule.withVerbs(['get']),
  ]) + {
    cluster_role+: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
    },
    cluster_role_binding+: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
    },
  },

  telegraf_secret:
    secret.new('telegraf', {}) +
    secret.metadata.withNamespace($._config.namespace) +
    secret.withStringDataMixin({
      env: 'local',
      influx_token: $._config.telegraf.influx_token,
    }),

  telegraf_ds_config_map:
    configMap.new('telegraf-ds') +
    configMap.metadata.withNamespace($._config.namespace) +
    configMap.withData({
      'telegraf.conf': importstr 'configs/telegraf.conf',
    }),

  telegraf_ds_container::
    container.new('telegraf', $._images.telegraf) +
    container.withEnvMixin([
      $.core.v1.envVar.fromFieldPath('HOSTNAME', 'spec.nodeName'),
      $.core.v1.envVar.fromFieldPath('KUBELET', 'status.hostIP'),
      $.core.v1.container.envType.new('HOST_PROC', '/rootfs/proc'),
      $.core.v1.container.envType.new('HOST_SYS', '/rootfs/sys'),
      $.core.v1.envVar.fromSecretRef('ENV', $.telegraf_secret.metadata.name, 'env'),
      $.core.v1.envVar.fromSecretRef('INFLUX_TOKEN', $.telegraf_secret.metadata.name, 'influx_token'),
    ]) +
    $.util.resourcesRequests('100m', '128Mi') +
    $.util.resourcesLimits('500m', '256Mi') +
    container.withVolumeMountsMixin([
      volumeMount.new('sys', '/rootfs/sys', true),
      volumeMount.new('proc', '/rootfs/proc', true),
      //volumeMount.new('utmp', '/var/run/utmp', true),
      //volumeMount.new('docker-socket', '/var/run/docker.sock', true),
    ]),
  // Probes

  telegraf_daemonset:
    ds.new(
      'telegraf-ds',
      $.telegraf_ds_container,
      $._config.telegraf.labels { scope: 'kubelet' },
    ) +
    ds.metadata.withNamespace($._config.namespace) +
    ds.metadata.withLabelsMixin($._config.telegraf.labels { scope: 'kubelet' }) +
    ds.spec.template.spec.withVolumesMixin([
      volume.fromHostPath('sys', '/sys'),
      volume.fromHostPath('proc', '/proc'),
      //volume.fromHostPath('docker-socket', '/var/run/docker.sock'),
      //volume.fromHostPath('utmp', '/var/run/utmp'),
    ]) +
    $.util.configMapVolumeMount($.telegraf_ds_config_map, '/etc/telegraf') +
    //ds.spec.template.spec.withHostNetwork(true) +
    ds.spec.template.spec.withServiceAccountName($.telegraf_ds_rbac.service_account.metadata.name) +
    ds.spec.template.spec.withTerminationGracePeriodSeconds(30),
  // statefulSet.mixin.spec.template.spec.securityContext.withRunAsUser(0) +

}
