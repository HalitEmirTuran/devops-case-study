# Stuff I hit during setup (and how I fixed it)

Here is a quick list of issues we ran into while getting this petclinic devops stack up and running, mostly around k8s security, network policies, and some local kind quirks.

---

### 1. K8s runAsNonRoot complaining about named user (`petclinic`)

* **What happened:** 
  Deployment failed to start with a weird error:
  `container has runAsNonRoot and image has non-numeric user (petclinic), cannot verify user is non-root`
* **Why:** 
  I had `USER petclinic` in the Dockerfile, and `runAsNonRoot: true` in the k8s deployment. K8s is paranoid—it doesn't actually parse the `/etc/passwd` inside the image before running it, so it can't verify if `petclinic` is actually root or not. It needs a number.
* **Fix:** 
  Updated both Dockerfile and deployment `securityContext` to use numeric UID `10001`.
  * Dockerfile: `USER 10001:10001`
  * K8s deployment:
    ```yaml
    securityContext:
      runAsUser: 10001
      runAsGroup: 10001
      runAsNonRoot: true
    ```

---

### 2. NetworkPolicy blocked app access from outside (localhost)

* **What happened:** 
  Pods were running fine, service was set up as NodePort, but `http://localhost:8080` just timed out.
* **Why:** 
  The default `NetworkPolicy` I wrote was way too strict. It blocked *everything* that wasn't explicitly allowed, including the ingress/nodeport traffic hitting the app pod.
* **Fix:** 
  Split the network policies into `app-networkpolicy.yaml` and `postgres-networkpolicy.yaml`. 
  * App policy: Allowed ingress on port 8080 (so ingress/nodeport can talk to it) and allowed egress to postgres (port 5432) and DNS.
  * DB policy: Blocked everything except ingress from app pods and backup job pods.

---

### 3. Backup CronJob getting blocked by DB NetworkPolicy

* **What happened:** 
  The daily database backup cronjob failed with:
  `pg_dump: error: connection to server at "postgres" port 5432 failed: Operation timed out`
* **Why:** 
  The postgres NetworkPolicy only whitelisted connections coming from `app.kubernetes.io/component: application` (the app pods). It didn't know anything about the backup cronjob pods.
* **Fix:** 
  Added the backup label selector to `postgres-networkpolicy.yaml` so it allows connections from both the app and the backup job:
  ```yaml
  - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: postgres
            app.kubernetes.io/component: backup
  ```

---

### 4. Backup script printed success when it actually failed (false positive)

* **What happened:** 
  When the backup timed out, the logs still printed `Backup created: /backup/...` at the end.
* **Why:** 
  Classic shell script mistake. There was no error handling, so even if `pg_dump` crashed, the script kept running and executed the `echo` at the bottom.
* **Fix:** 
  Added `set -eu` at the beginning of the script so it exits immediately on any error, and threw in a `pg_isready` check before running `pg_dump` to make sure the database is actually reachable first.

---

### 5. Docker image pull failed inside Kind cluster

* **What happened:** 
  K8s pods got `ErrImagePull` trying to get `localhost:5001/petclinic-app:v1.0.x-local`.
* **Why:** 
  Kind nodes are actually Docker containers themselves. When K8s inside Kind tries to pull from `localhost:5001`, "localhost" means the *Kind node container*, not my host machine.
* **Fix:** 
  Wrote a script (`create-cluster-with-registry.ps1`) that:
  1. Spins up a registry container on host port 5001.
  2. Connects that registry container to the Kind docker network.
  3. Configures each Kind node's containerd config (`hosts.toml`) to point `localhost:5001` to `http://kind-registry:5000`.
  4. Configures a `local-registry-hosting` ConfigMap so k8s knows about it.

---

### 6. HPA targeting CPU stayed `<unknown>`

* **What happened:** 
  Running `kubectl get hpa` showed `cpu: <unknown>/70%`.
* **Why:** 
  Kind doesn't come with a metrics server by default. Without a metrics server, the Horizontal Pod Autoscaler cannot query the CPU utilization metrics of the pods.
* **Fix:** 
  Deployed the standard metrics server, but since this is Kind, it failed to authenticate kubelet certificates. Had to patch the deployment with `--kubelet-insecure-tls` and `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname`. Now HPA works and scales replicas properly.

---

### 7. DB password auth failed on re-deploys (Postgres PVC issue)

* **What happened:** 
  Re-running `.\start-all.ps1` would cause app pods to crash with:
  `FATAL: password authentication failed for user "petclinic_app"`
* **Why:** 
  Postgres only reads the `POSTGRES_PASSWORD_FILE` environment secret **during the very first boot** (when the PVC is blank). If the PVC already has database files, Postgres ignores the secret file and uses whatever password was set during the first boot. 
  But `init-secrets.ps1` generated a brand new password every time the script ran. This meant K8s secrets and App pods got the new password, but the Postgres DB was still locked with the old one.
* **Fix:** 
  Modified `deploy-k8s.ps1` (and the Jenkins pipeline) to automatically run an `ALTER USER` command inside the Postgres container using `kubectl exec` as soon as it boots up, forcing the database-internal password to match the freshly generated secret. Then we do a `rollout restart` on the app so everything is in sync.
  ```powershell
  kubectl exec postgres-0 -n $Namespace -- psql -U $DbUser -d $DbName -c "ALTER USER $DbUser WITH PASSWORD '$DbPassword';"
  ```

---

### 8. Pod Security Standard warnings on Namespace

* **What happened:** 
  Saw lots of audit warnings like `would violate PodSecurity "restricted:latest"`.
* **Why:** 
  We set `pod-security.kubernetes.io/audit: restricted` on the namespace. By default, standard pods (like the postgres container) violate this by having access to host namespaces, missing seccomp profiles, or not dropping capabilities.
* **Fix:** 
  Squeezed the security settings in `app-deployment.yaml`, `postgres-statefulset.yaml`, and `postgres-backup-cronjob.yaml`. Added `allowPrivilegeEscalation: false`, dropped `ALL` capabilities, and added `seccompProfile: {type: RuntimeDefault}`. 
  *Note: Kept read-only root FS disabled on Postgres since it obviously needs to write to its own volumes.*

---

### 9. Jenkins pipeline missing secrets

* **What happened:** 
  Jenkins build worked but failed at the deploy stage because secret files like `secrets/postgres.password` are gitignored.
* **Why:** 
  We don't commit secrets to Git (obviously), so the Jenkins agent couldn't read them during the checkout stage.
* **Fix:** 
  Configured three credentials in Jenkins UI (`petclinic-postgres-db`, `petclinic-postgres-user`, `petclinic-postgres-password`). In the `Jenkinsfile`, we use `withCredentials` to fetch them, write them temporarily into a `.jenkins-secrets` dir on the agent, generate the K8s generic secret `petclinic-db-secret` on the fly, and then wipe the temp dir.

---

### 10. Trivy and Platform Setup Pipeline Decisions

* **Trivy security checks:** I put Trivy in the pipeline to scan the final app image, but configured it to output to a file (`trivy-image-scan.txt`) and not fail the build (`--exit-code 0` behavior). Some base OS vulnerabilities in Temurin are out of our control and shouldn't block the CI/CD pipeline.
* **Platform Add-ons (Ingress / Metrics Server):** Installing these takes time. It's stupid to reinstall them on every single code commit. I made them an optional, parameterized stage (`RUN_PLATFORM_SETUP` flag) in `Jenkinsfile`. We only run it if we're setting up a new cluster or upgrading tools.
