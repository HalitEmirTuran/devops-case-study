# Kurulum Sırasında Yaşadığım Sorunlar ve Çözümleri

Bu projeyi (Spring Petclinic devops stack) kurarken, özellikle Kubernetes güvenlik ayarları, NetworkPolicy'ler ve yerel Kind kümesinin bazı gariplikleri nedeniyle karşılaştığım sorunları ve bunları nasıl çözdüğümü buraya not ettim.

*İngilizce kılavuz için [troubleshooting.md](./troubleshooting.md) dosyasına göz atabilirsiniz.*

---

### 1. K8s runAsNonRoot ve named user (`petclinic`) hatası

* **Ne oldu:** 
  Deployment'ı ayağa kaldırmaya çalışırken pod şu hata ile çöktü:
  `container has runAsNonRoot and image has non-numeric user (petclinic), cannot verify user is non-root`
* **Neden:** 
  Dockerfile'da `USER petclinic` tanımı yapmıştım, Kubernetes deployment'ında ise `runAsNonRoot: true` vardı. Kubernetes biraz pimpirikli—konteyner ayağa kalkmadan önce imajın içindeki `/etc/passwd` dosyasını okuyup `petclinic` kullanıcısının gerçekten yetkisiz (non-root) olup olmadığını doğrulayamıyor. Kesinlikle numeric bir UID görmek istiyor.
* **Nasıl çözdüm:** 
  Hem Dockerfile'ı hem de deployment manifestindeki `securityContext` bloğunu numeric UID `10001` kullanacak şekilde güncelledim.
  * Dockerfile: `USER 10001:10001`
  * K8s deployment:
    ```yaml
    securityContext:
      runAsUser: 10001
      runAsGroup: 10001
      runAsNonRoot: true
    ```

---

### 2. NetworkPolicy yüzünden uygulamaya dışarıdan (localhost) erişilememesi

* **Ne oldu:** 
  Pod'lar sorunsuz `Running` durumundaydı, servis NodePort olarak tanımlanmıştı ama tarayıcıdan `http://localhost:8080` açmaya çalıştığımda istek sürekli timeout'a düştü.
* **Neden:** 
  Yazdığım ilk `NetworkPolicy` çok katıydı. Açıkça izin verilmeyen her şeyi engelliyordu. Ingress veya NodePort üzerinden gelen dış trafiğin uygulama poduna ulaşmasına izin vermediğim için bağlantı kopuyordu.
* **Nasıl çözdüm:** 
  NetworkPolicy'yi iki ayrı dosyaya böldüm: `app-networkpolicy.yaml` ve `postgres-networkpolicy.yaml`.
  * Uygulama (App) policy: Dışarıdan (ingress/nodeport) 8080 portuna gelen trafiğe izin verdim. Ayrıca pod'un dışarıya (PostgreSQL 5432 ve DNS) konuşabilmesini sağladım.
  * Veritabanı (DB) policy: Sadece uygulama podlarından ve yedekleme (backup) podlarından gelen trafiğe izin verecek şekilde daralttım.

---

### 3. Yedekleme (Backup) CronJob'ının DB NetworkPolicy tarafından engellenmesi

* **Ne oldu:** 
  Her gece çalışması gereken veritabanı yedekleme işi (backup cronjob) şu hatayla başarısız oldu:
  `pg_dump: error: connection to server at "postgres" port 5432 failed: Operation timed out`
* **Neden:** 
  PostgreSQL için yazdığım NetworkPolicy sadece `app.kubernetes.io/component: application` (uygulama podları) etiketine sahip podlara izin veriyordu. Backup cronjob podunun bu servise erişebileceğinden haberi yoktu.
* **Nasıl çözdüm:** 
  `postgres-networkpolicy.yaml` dosyasına yedekleme podunun etiketini de ekledim:
  ```yaml
  - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: postgres
            app.kubernetes.io/component: backup
  ```

---

### 4. Backup betiğinin hata almasına rağmen "Başarılı" çıktısı vermesi

* **Ne oldu:** 
  Yedekleme işlemi timeout alıp başarısız olmasına rağmen loglarda en sonda hâlâ `Backup created: /backup/...` yazıyordu.
* **Neden:** 
  Klasik bir shell script hatası. Script içinde hata kontrolü yoktu; `pg_dump` hata verip çökse bile script çalışmaya devam ediyor ve en alttaki `echo` komutunu çalıştırıyordu.
* **Nasıl çözdüm:** 
  Betiğin başına herhangi bir hata anında doğrudan durması için `set -eu` ekledim. Ayrıca `pg_dump` komutunu koşturmadan önce veritabanının ayakta ve erişilebilir olduğundan emin olmak için `pg_isready` kontrolü koydum.

---

### 5. Kind kümesinde Docker imajının çekilememesi (`ErrImagePull`)

* **Ne oldu:** 
  Kubernetes pod'ları `localhost:5001/petclinic-app:v1.0.x-local` imajını çekmeye çalışırken `ErrImagePull` hatası verdi.
* **Neden:** 
  Kind node'ları aslında kendi başlarına birer Docker konteyneridir. Kind içindeki Kubernetes `localhost:5001` adresine gitmeye çalıştığında, buradaki "localhost" benim ana bilgisayarımı değil, *Kind node konteynerinin kendisini* gösterir.
* **Nasıl çözdüm:** 
  Şu adımları otomatize eden `create-cluster-with-registry.ps1` betiğini yazdım:
  1. Host üzerinde 5001 portunda bir local registry konteyneri açıyor.
  2. Bu registry konteynerini Kind'ın docker ağına bağlıyor.
  3. Her bir Kind node'unun containerd ayar dosyasına (`hosts.toml`) `localhost:5001` adresini `http://kind-registry:5000` yönlendirecek konfigürasyonu yazıyor.
  4. Kubernetes'in bundan haberdar olması için `local-registry-hosting` ConfigMap'ini oluşturuyor.

---

### 6. HPA (Yatay Otomatik Ölçekleyici) CPU değerinin `<unknown>` kalması

* **Ne oldu:** 
  `kubectl get hpa` komutunu çalıştırdığımda CPU sütununda değer yerine `<unknown>/70%` görüyordu.
* **Neden:** 
  Kind kümeleri varsayılan olarak bir metrics server ile gelmez. Kümede metrics server olmayınca HPA podların CPU tüketim verilerini sorgulayamıyor ve ölçekleme yapamıyordu.
* **Nasıl çözdüm:** 
  Standart metrics server bileşenini kurdum. Ancak Kind yerel bir ortam olduğu için kubelet sertifikalarını doğrulayamayıp hata verdi. Deplomynet'i `--kubelet-insecure-tls` ve `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname` argümanlarıyla yamalayarak (patch) sorunu çözdüm. Artık HPA değerleri okuyor ve podları ölçekleyebiliyor.

---

### 7. Küme yeniden başlatıldığında DB şifre uyuşmazlığı hatası (Postgres PVC durumu)

* **Ne oldu:** 
  Cluster'ı kapatıp açtıktan sonra veya `.\start-all.ps1` betiğini tekrar çalıştırdığımda uygulama podları `CrashLoopBackOff` durumuna düştü:
  `FATAL: password authentication failed for user "petclinic_app"`
* **Neden:** 
  PostgreSQL imajı, dışarıdan verilen şifre dosyasını (`POSTGRES_PASSWORD_FILE`) **sadece ilk kurulumda (PVC boşken)** okur ve veritabanını initialize eder. Sonraki açılışlarda PVC'de zaten veri olduğu için bu dosyayı tamamen görmezden gelir ve kendi içindeki eski şifreyi kullanmaya devam eder.
  Ancak `init-secrets.ps1` betiği her çalıştığında yeni bir rastgele şifre üretiyordu. K8s Secret ve uygulama podları yeni şifreyi alırken, PostgreSQL eski şifrede kilitli kaldığı için bağlantı kopuyordu.
* **Nasıl çözdüm:** 
  `deploy-k8s.ps1` (ve Jenkins pipeline) içine, veritabanı hazır olduktan hemen sonra `kubectl exec` ile içeride bir `ALTER USER` komutu koşturan satırlar ekledim. Bu sayede veritabanı içindeki şifre, üretilen güncel secret ile her deploy aşamasında eşitleniyor. Ardından uygulamaya rolling-update atarak her şeyin senkronize olmasını sağladım.
  ```powershell
  kubectl exec postgres-0 -n $Namespace -- psql -U $DbUser -d $DbName -c "ALTER USER $DbUser WITH PASSWORD '$DbPassword';"
  ```

---

### 8. Namespace üzerindeki Pod Security Restricted uyarıları

* **Ne oldu:** 
  Namespace'e Pod Security Standartları ekledikten sonra loglarda sürekli şu tarz uyarılar gördüm:
  `would violate PodSecurity "restricted:latest"`
* **Neden:** 
  Namespace üzerinde `pod-security.kubernetes.io/audit: restricted` kuralı aktifti. Standart postgres veya uygulama podları varsayılan olarak host namespace erişimi, seccomp profili eksikliği veya yetki sınırlandırması olmaması gibi nedenlerle bu kuralları ihlal ediyordu.
* **Nasıl çözdüm:** 
  `app-deployment.yaml`, `postgres-statefulset.yaml` ve `postgres-backup-cronjob.yaml` dosyalarındaki `securityContext` ayarlarını sıkılaştırdım. `allowPrivilegeEscalation: false` ekledim, `ALL` yetkilerini düşürdüm ve `seccompProfile: {type: RuntimeDefault}` tanımını yaptım. 
  *(Not: Postgres stateful olduğu ve diske yazması gerektiği için read-only root FS ayarını onda bilerek devre dışı bıraktım.)*

---

### 9. Jenkins Pipeline'ında secret dosyalarının bulunamaması

* **Ne oldu:** 
  Jenkins build'i başarılı oluyordu ama deploy aşamasına gelince `secrets/postgres.password` gibi dosyaları bulamadığı için çöküyordu.
* **Neden:** 
  Güvenlik gereği secret dosyalarını `.gitignore` ile Git dışında tutuyoruz. Bu yüzden Jenkins agent repoyu çektiğinde bu dosyalar workspace'e gelmiyordu.
* **Nasıl çözdüm:** 
  Jenkins arayüzünde 3 adet credential tanımladım (`petclinic-postgres-db`, `petclinic-postgres-user`, `petclinic-postgres-password`). `Jenkinsfile` içinde bu şifreleri `withCredentials` bloğuyla çekip, derleme ajanı üzerinde geçici bir `.jenkins-secrets` klasörüne yazdırdım. K8s secret'ını oluşturduktan hemen sonra da bu geçici klasörü sildim.

---

### 10. Trivy Tarama ve Eklenti Kurulum Kararları

* **Trivy İmaj Taraması:** Pipeline'a Trivy aracıyla güvenlik taraması ekledim fakat bunu `--exit-code 0` (reporting mode) olarak bıraktım. Temurin base imajındaki bazı OS seviyesi açıklar bizim kontrolümüzde olmadığı için pipeline'ın gereksiz yere kırılmasını engelledim.
* **Platform Add-ons (Ingress / Metrics Server):** Bu bileşenleri her kod değişikliğinde sıfırdan kurmak çok gereksiz zaman alıyordu. Bu yüzden `Jenkinsfile` üzerinde `RUN_PLATFORM_SETUP` adında opsiyonel bir parametre tanımladım. Sadece küme sıfırdan kurulduğunda bu adımı aktifleştiriyoruz.
