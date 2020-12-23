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

  // Common Resources
  telegraf_secret:
    secret.new('telegraf', {}) +
    secret.metadata.withNamespace($._config.namespace) +
    secret.withStringDataMixin({
      env: 'local',
      influx_token: $._config.telegraf.influx_token,
    }),

  // Daemonset to monitor kubelet and nodes
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

  telegraf_ds_config_map:
    configMap.new('telegraf-ds') +
    configMap.metadata.withNamespace($._config.namespace) +
    configMap.withData({
      'telegraf.conf': importstr 'configs/telegraf-ds.conf',
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

  //Single Deployment to monitor generic endpoints ( kubelet api and other core components, cloudwatch, ... )
  telegraf_deploy_rbac: {
    local this = self,
    local clusterRole = $.rbac.v1.clusterRole,
    local clusterRoleBinding = $.rbac.v1.clusterRoleBinding,
    local subject = $.rbac.v1.subject,
    local serviceAccount = $.core.v1.serviceAccount,
    local aggregate_view_telegraf_label = { 'rbac.authorization.k8s.io/aggregate-view-telegraf': 'true' },

    cluster_viewer: clusterRole.new('influx:cluster:viewer') +
                    clusterRole.metadata.withLabelsMixin($._config.telegraf.labels + aggregate_view_telegraf_label + { scope: 'single' }) +
                    clusterRole.withRules([
                      policyRule.withApiGroups(['']) +
                      policyRule.withResources(['persistentvolumes', 'nodes']) +
                      policyRule.withVerbs(['get', 'list']),
                      policyRule.withNonResourceURLs(['/metrics']) +
                      policyRule.withVerbs(['get']),
                    ]),

    cluster_telegraf: clusterRole.new('influx:telegraf') +
                      clusterRole.metadata.withLabelsMixin($._config.telegraf.labels { scope: 'single' }) +
                      clusterRole.aggregationRule.withClusterRoleSelectors([
                        { matchLabels: selector }
                        for selector in [
                          aggregate_view_telegraf_label,
                          { 'rbac.authorization.k8s.io/aggregate-to-view': 'true' },
                        ]
                      ]),

    service_account:
      serviceAccount.new('influx-deploy') +
      serviceAccount.metadata.withNamespace($._config.namespace) +
      serviceAccount.metadata.withLabelsMixin($._config.telegraf.labels { scope: 'single' }),

    cluster_role_binding:
      clusterRoleBinding.new('influx-deploy') +
      clusterRoleBinding.mixin.metadata.withNamespace($._config.namespace) +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withKind('ClusterRole') +
      clusterRoleBinding.mixin.roleRef.withName(this.cluster_telegraf.metadata.name) +
      clusterRoleBinding.withSubjects([
        subject.withKind('ServiceAccount') +
        subject.withName(this.service_account.metadata.name) +
        subject.withNamespace($._config.namespace),
      ]),

  },

  telegraf_deploy_config_map:
    configMap.new('telegraf-deploy') +
    configMap.metadata.withNamespace($._config.namespace) +
    configMap.withData({
      'telegraf.conf': importstr 'configs/telegraf-deploy.conf',
    }),

  telegraf_deploy_container::
    container.new('telegraf', $._images.telegraf) +
    container.withEnvMixin([
      $.core.v1.envVar.fromFieldPath('HOSTNAME', 'spec.nodeName'),
      $.core.v1.envVar.fromSecretRef('ENV', $.telegraf_secret.metadata.name, 'env'),
      $.core.v1.envVar.fromSecretRef('INFLUX_TOKEN', $.telegraf_secret.metadata.name, 'influx_token'),
    ]) +
    $.util.resourcesRequests('100m', '128Mi') +
    $.util.resourcesLimits('500m', '256Mi'),
  // Probes

  telegraf_deployment:
    deployment.new(
      'telegraf-deploy',
      1,
      $.telegraf_deploy_container,
      $._config.telegraf.labels { scope: 'single' },
    ) +
    deployment.metadata.withNamespace($._config.namespace) +
    deployment.metadata.withLabelsMixin($._config.telegraf.labels { scope: 'single' }) +
    $.util.configMapVolumeMount($.telegraf_deploy_config_map, '/etc/telegraf') +
    ds.spec.template.spec.withServiceAccountName($.telegraf_deploy_rbac.service_account.metadata.name) +
    ds.spec.template.spec.withTerminationGracePeriodSeconds(30),
  // statefulSet.mixin.spec.template.spec.securityContext.withRunAsUser(0) +


  // ServiceFor https://github.com/influxdata/kube-influxdb/blob/master/telegraf-s/templates/service.yaml

}
