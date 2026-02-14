# ADR 001: Helm + Helmfile Over ytt/kapp

**Status:** Accepted
**Date:** 2026-02-14
**Context:** Cloud Foundry KIND Deployment toolchain selection

## Context

The previous Cloud Foundry on Kubernetes project (`cf-for-k8s`) used the Carvel
toolchain -- specifically **ytt** for YAML templating and **kapp** for
deployment orchestration. When the upstream `kind-deployment` repository was
created to deploy traditional CF components on KIND, a toolchain decision was
required.

The two options considered:

1. **ytt + kapp** (Carvel): The approach used by `cf-for-k8s`. ytt provides a
   Python-like overlay language for YAML; kapp provides diff-based deployment
   with ordered resource application.

2. **Helm + Helmfile**: The industry-standard Kubernetes package manager (Helm)
   combined with a declarative spec for deploying multiple Helm releases in
   dependency order (Helmfile).

## Decision

Use **Helm + Helmfile** for all deployment orchestration.

## Rationale

### 1. Industry Standard Tooling

Helm is the dominant package manager for Kubernetes. Most developers, SREs, and
platform engineers already know Helm charts, `values.yaml`, and GoTemplate
syntax. Choosing Helm eliminates a learning barrier for contributors.

ytt requires learning a custom overlay language that is unfamiliar outside the
Cloud Foundry ecosystem. kapp, while well-designed, has low adoption compared to
Helm.

### 2. GoTemplate for Values

Helm uses Go templates for chart rendering. While Go templates have sharp edges,
they are widely documented and understood. Helmfile extends this with additional
template functions (`requiredEnv`, `readFile`, etc.) for the release
specification itself.

ytt's Starlark-based overlays are more powerful but also more complex. For a
project that primarily needs value substitution and conditional inclusion,
GoTemplate is sufficient.

### 3. Helmfile for Dependency Ordering

Helmfile's `needs:` directive provides an explicit dependency DAG between Helm
releases. This is critical for CF deployment ordering (e.g., cert-manager before
UAA, PostgreSQL before CAPI). The ordering is declarative and visible in a single
`helmfile.yaml.gotmpl` file.

kapp provides resource-level ordering via annotations, but the dependency graph
is less visible and scattered across resources.

### 4. No CF-Specific Tooling Required

Using Helm + Helmfile means contributors only need tools from the broader
Kubernetes ecosystem. No Carvel installation is required. This reduces the
prerequisites list and avoids version compatibility issues with CF-specific
tooling.

### 5. OCI Registry and GitOps Compatibility

Helm charts can be published to OCI registries (the upstream already uses
`ghcr.io/cloudfoundry/helm` for `k8s-rep` and `policy-agent`). They integrate
with ArgoCD, Flux, and Renovate for automated updates. This aligns with modern
GitOps practices.

## Consequences

- Chart authors must use GoTemplate, which can be verbose for complex logic.
- Helm's three-way merge for upgrades can occasionally produce unexpected diffs.
- Helmfile adds a dependency beyond Helm itself (though it is a single binary).
- Existing CF ecosystem tooling (ytt overlays, kapp configs) cannot be reused
  directly.

## Alternatives Considered

| Alternative   | Reason Rejected                                               |
| ------------- | ------------------------------------------------------------- |
| ytt + kapp    | Low adoption outside CF; extra tooling burden                 |
| Plain kubectl | No templating, no dependency ordering                         |
| Kustomize     | No dependency ordering between releases; limited templating   |
| Terraform     | Too heavyweight for local development clusters                |
