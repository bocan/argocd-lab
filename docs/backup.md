# Backup and restore

This cluster does not use a Kubernetes backup tool such as Velero. Git
already holds the cluster configuration, and Argo CD rebuilds the cluster
from it. Only a few things are outside git, and each one has its own backup.

## What is where

| What | Where it lives | Backup | If you lose it |
| --- | --- | --- | --- |
| Cluster config: charts, values, Applications | This git repo (GitHub) | GitHub, plus each clone | Nothing. Clone again. |
| Node setup: k3s, NFS client | The home-build Ansible repo | Local git repo only | Rebuild it from memory. Copy the repo somewhere safe. |
| **Sealed-secrets private key** | Secret in namespace `sealed-secrets` | **Manual export to your password manager** | Every SealedSecret in git is useless. Seal each one again. |
| PVC data | NAS `192.168.0.55:/volume1/pi-cluster/<namespace>-<pvc>/` | NAS snapshots and a NAS backup task | The data of every app. |
| k3s datastore | SQLite, `/var/lib/rancher/k3s/server/db/` on pi5-1 | None | Nothing that matters. Argo CD rebuilds every object from git. |

RAID on the NAS is not a backup. It protects against one failed disk, not
against a delete, a bad write, ransomware or the loss of the NAS.

## 1. The sealed-secrets key

The controller encrypts every SealedSecret in `directories/all-secrets` with
this key. Without it, nobody can decrypt them. The key was lost once, with the
old NFS drive, and every secret had to be sealed again.

### Export

```sh
kubectl -n sealed-secrets get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```

Put the file in your password manager, then delete the local copy:

```sh
rm sealed-secrets-key.yaml
```

Never commit it to git, not even to a local repo. Anybody with this file
can decrypt every SealedSecret.

### When to export again

The controller makes a new key every 30 days and keeps the old ones. `kubeseal`
always uses the newest key. So a backup decrypts only the SealedSecrets that
were sealed before the backup.

Export again:

- after you seal a new secret, and
- once a month.

Each export contains all the keys, old and new, so the newest export replaces
the older ones.

To see the keys and their ages:

```sh
kubectl -n sealed-secrets get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
```

## 2. PVC data on the NAS

csi-driver-nfs makes one folder for each PVC, named `<namespace>-<pvc name>`,
under `/volume1/pi-cluster`. A deleted PVC's folder is renamed to
`archived-<namespace>-<pvc name>` and kept.

Set these up on the NAS (UGOS), not in Kubernetes:

- [ ] **Snapshots** of the volume or the `pi-cluster` shared folder, on a
      schedule. They protect against deletes and bad writes, and they restore
      fast.
- [ ] **A backup task** that copies `pi-cluster` off the NAS: to a cloud
      bucket (AWS S3, Backblaze B2) or to a USB disk that you keep somewhere
      else. This protects against the loss of the NAS.
- [ ] **Recycle bin:** check whether NFS deletes go to `#recycle` in the
      share. If they do, archived folders and deleted files use disk space
      that you do not see.

### Databases

A file copy of a running database is not always consistent. For each database,
add a dump job that writes a dump file to an NFS volume, for example a
`pg_dump` CronJob for PostgreSQL. The NAS backup then copies the dump files.

## 3. Restore after the loss of the cluster

Do the steps in this order. The NAS and its data are still there.

1. **Build the nodes** with the home-build repo:

   ```sh
   cd ~/Play/home-build
   ansible-playbook playbooks/k3s-cluster.yml
   export KUBECONFIG=~/Play/home-build/playbooks/kubeconfig-pi5-1
   ```

   This installs k3s and makes each node an NFS client of the NAS, with
   `rpc-statd` for NFSv3 locking.

2. **Put back the sealed-secrets key**, before Argo CD installs the
   controller:

   ```sh
   kubectl create namespace sealed-secrets
   kubectl apply -f sealed-secrets-key.yaml   # from your password manager
   ```

   If the controller already runs, it made a new key at start and did not
   load yours. Apply the file, then restart it:

   ```sh
   kubectl -n sealed-secrets delete pod -l app.kubernetes.io/name=sealed-secrets
   ```

3. **Install Argo CD** with Helm, with the same release name and namespace
   that the `argo-cd` Application uses. Argo CD then takes over its own
   release:

   ```sh
   helm dependency build charts/argo-cd
   helm install argo-cd charts/argo-cd --namespace argocd --create-namespace
   ```

4. **Start the app of apps:**

   ```sh
   make bootstrap
   kubectl -n argocd get applications -w
   ```

   Argo CD installs every enabled app from `charts/root-app/values.yaml`.
   The order sorts itself out with retries. The first cert-manager sync can
   take a few minutes (see the retry comment in the values).

5. **PVC data comes back by itself.** A new PVC with the same namespace and
   name gets the same folder on the NAS, because the StorageClass names the
   folders after the PVC. Check with:

   ```sh
   kubectl get pvc -A
   ```

   A PVC that was deleted before the loss has an `archived-` folder. To use
   its data, rename the folder on the NAS before you make the PVC.

6. **DNS and TLS come back by themselves.** external-dns points the names at
   `192.168.0.50`, and cert-manager gets new certificates from Let's Encrypt.

### Check that it worked

```sh
kubectl -n argocd get applications            # all Synced and Healthy
kubectl get sealedsecret -A                   # no "no key could decrypt" events
kubectl get certificate -A                    # all READY True
curl -sS -o /dev/null -w '%{http_code}\n' https://argocd.funderburg.uk/
```

## 4. Restore one app's data

To go back to an older copy of one PVC's data:

1. Scale the app to zero, so that nothing writes to the volume.
2. On the NAS, restore the folder `<namespace>-<pvc>` from a snapshot or
   from the backup task.
3. Scale the app up again.

The PVC and PV do not change, because they point at the folder by name.
