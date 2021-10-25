---
data:
  title: "Drift internals"
  weight: 300000
  description: Work in progress documentation on drift internals
template: layouts/docs/list
---

## Using an unreleased drift version

To try out new drift features, you can choose to use a development or beta version of drift before it's
published to pub. For that, add an `dependency_overrides` section to your pubspec:

```yaml
dependency_overrides:
  drift:
    git:
      url: https://github.com/simolus3/moor.git
      ref: beta
      path: drift
  drift_dev:
    git:
      url: https://github.com/simolus3/moor.git
      ref: beta
      path: drift_dev
  sqlparser:
    git:
      url: https://github.com/simolus3/moor.git
      ref: beta
      path: sqlparser
```

If you're using `moor_flutter`, just exchange `drift` with `moor_flutter` in the package name
and path. To use the bleeding edge of drift, change `ref: beta` to `ref: develop` for all packages.
