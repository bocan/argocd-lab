# Parked secrets

No Argo CD Application syncs this folder.

These SealedSecrets were sealed with the old controller key, which was lost
with the NFS storage. They cannot be decrypted. Seal each one again with the
new key, then move it back to `directories/all-secrets` when its app is
enabled again.

| File | Namespace | Used by |
| --- | --- | --- |
| `grafana-keycloak-client.yaml` | monitoring | kube-prometheus-stack (Grafana) |
| `smtp-credentials.yaml` | monitoring | kube-prometheus-stack (Grafana) |
