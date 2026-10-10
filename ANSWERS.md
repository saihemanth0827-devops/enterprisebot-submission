# Part 5 — Gateway API migration

I would treat this as a controller migration, not a one-shot rewrite of 40 Ingress objects.

1. **Inventory and baseline:** export all Ingresses and controller configuration; group routes by host, path, TLS, rewrites, auth, rate limits, timeouts, body size, source-IP rules and annotations. Capture current request/error rates and run synthetic probes for critical routes.
2. **Compatibility mapping:** map standard host/path/TLS rules to Gateway API `Gateway` and `HTTPRoute` resources. Identify ingress-nginx-specific annotations that need Gateway API filters, policies, or implementation-specific configuration. Choose a maintained Gateway API controller and verify its conformance and feature support before committing.
3. **Install in parallel:** install CRDs/controller and configure a separate Gateway/listener without changing the existing ingress-nginx entry point. Set up certificates, DNS, observability, network policy and RBAC. Validate status conditions and backend references.
4. **Migrate in batches:** convert a low-risk service first, preserve the old Ingress, and test with a temporary hostname or controlled traffic split. Check redirects, headers, TLS, WebSockets, large uploads, timeouts, client IP, auth and error handling. Compare synthetic and production telemetry.
5. **Shift traffic gradually:** move DNS or load-balancer traffic in measured increments, with health checks and an explicit rollback path to the old controller. Avoid deleting old routes until the new path has been stable through peak traffic and a defined observation window.
6. **Retire safely:** migrate remaining routes in batches, remove obsolete annotations/config only after owners sign off, then decommission ingress-nginx and update runbooks.

Expected breakage includes unsupported annotations, differences in path matching and rewrite semantics, TLS/certificate attachment, header handling, source-IP preservation, timeouts, controller-specific auth/rate limits, and DNS/load-balancer propagation. “No downtime” depends on parallel operation, representative tests, monitoring and rollback—not merely valid YAML.
