{{flutter_js}}
{{flutter_build_config}}

const builds = window._flutter?.buildConfig?.builds ?? [];
const hasSkwasmBuild = builds.some((build) => build.renderer === 'skwasm');

_flutter.loader.load({
  config: hasSkwasmBuild
      ? {
          renderer: 'skwasm',
          forceSingleThreadedSkwasm: true,
          suppressMultithreadingWarning: true,
        }
      : {},
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
