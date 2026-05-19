# Troubleshooting: Karşılaşılan Sorunlar ve Çözümleri

## 1. Kubernetes runAsNonRoot ve Named User Hatası

**Belirti:** Pod başlatılamıyor:
```
container has runAsNonRoot and image has non-numeric user (petclinic), cannot verify user is non-root
```

**Neden:** Kubernetes, named user'ın (`USER petclinic`) gerçekten non-root olup olmadığını doğrulayamaz. Numeric UID olmadan güvenlik garantisi veremez.

**Çözüm:** Dockerfile'da ve Deployment securityContext'te numeric UID/GID kullanıldı:
```dockerfile
USER 10001:10001
```
```yaml
securityContext:
  runAsUser: 10001
  runAsGroup: 10001
  runAsNonRoot: true
```

---

## 2. NetworkPolicy Dış Trafiği Engelledi

**Belirti:** Pod'lar `Running` durumda ama uygulama tarayıcıdan açılmıyor.

**Neden:** İlk NetworkPolicy fazla kısıtlayıcıydı. NodePort/Ingress üzerinden gelen trafik uygulama pod'una ulaşamıyordu.

**Çözüm:** NetworkPolicy'ler app ve database için ayrıldı. App policy ingress trafiğine 8080 portunu açarken, PostgreSQL policy'si sadece uygulama ve backup pod'larından gelen bağlantılara izin verecek şekilde yapılandırıldı.

---

## 3. Backup CronJob NetworkPolicy Tarafından Engellendi

**Belirti:** Backup job logu:
```
pg_dump: error: connection to server at "postgres" port 5432 failed: Operation timed out
```

**Neden:** PostgreSQL NetworkPolicy'si sadece app pod'una izin veriyordu. Backup pod'unun label'ı tanımlı değildi.

**Çözüm:** `postgres-networkpolicy.yaml` içine backup pod label'ı eklendi:
```yaml
- from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: postgres
          app.kubernetes.io/component: backup
```

---

## 4. Backup Script Yanlış Başarı Mesajı Basıyordu

**Belirti:** `pg_dump` timeout almasına rağmen script başarılı mesajı yazdırıyordu.

**Neden:** Shell script'te hata kontrolü yoktu; `pg_dump` başarısız olsa bile sonraki `echo` çalışıyordu.

**Çözüm:** Script'e `set -eu` ve `pg_isready` kontrolü eklendi. Başarı mesajı yalnızca dump gerçekten tamamlandığında basılır.

---

## 5. Local Registry için Kind Network Ayarı

**Belirti:** Image push başarılı ama Kubernetes pod'u image'ı çekemiyor.

**Neden:** Kind node'u Docker container içinde çalışır. Host'taki `localhost:5001` ile kind node içindeki `localhost` aynı değildir.

**Çözüm:** `create-cluster-with-registry.ps1` ile registry container kind network'e bağlandı, node'lara `hosts.toml` config yazıldı ve `local-registry-hosting` ConfigMap oluşturuldu.

---

## 6. HPA Metrikleri `<unknown>` Gösteriyordu

**Belirti:**
```
TARGETS: cpu: <unknown>/70%
```

**Neden:** Cluster'da Metrics Server kurulu değildi. HPA CPU metriği okuyamıyordu.

**Çözüm:** Metrics Server kuruldu ve Kind ortamı için `--kubelet-insecure-tls` argümanı ile patchlendi. Sonrasında HPA gerçek CPU değerlerini okumaya başladı.

---

## 7. PostgreSQL Password Sync Sorunu

**Belirti:** Yeniden bootstrap sonrası app pod'ları `CrashLoopBackOff`'a düşüyor:
```
FATAL: password authentication failed for user "petclinic_app"
```

**Neden:** PostgreSQL `POSTGRES_PASSWORD_FILE`'ı yalnızca ilk init sırasında (PVC boşken) okur. Sonraki çalıştırmalarda PVC'de zaten veri vardır ve eski şifreyi kullanmaya devam eder. `init-secrets.ps1` yeni şifre ürettiğinde K8s Secret güncellenir ama PostgreSQL'in iç kataloğundaki şifre eski kalır.

**Çözüm:** `deploy-k8s.ps1` artık PostgreSQL ayağa kalktıktan sonra `ALTER USER` ile DB şifresini senkronlar ve app deployment'ı yeniden başlatır:
```powershell
kubectl exec postgres-0 -n $Namespace -- `
  psql -U $DbUser -d $DbName -c "ALTER USER $DbUser WITH PASSWORD '$DbPassword';"
kubectl rollout restart deployment/petclinic-app -n $Namespace
```

---

## 8. Pod Security Restricted Uyarıları

**Belirti:** Namespace'e Pod Security label eklenince uyarılar geldi:
```
would violate PodSecurity "restricted:latest"
```

**Neden:** Bazı workload'larda `seccompProfile`, `capabilities.drop`, `allowPrivilegeEscalation` gibi ayarlar eksikti.

**Çözüm:** Tüm workload'lar (Deployment, StatefulSet, CronJob) için securityContext sıkılaştırıldı. PostgreSQL'de `readOnlyRootFilesystem` bilinçli olarak eklenmedi çünkü PostgreSQL data dizinine yazma ihtiyacı duyar.

---

## 9. Jenkins Credential Yönetimi

**Belirti:** Pipeline deploy aşamasında secret dosyaları bulunamıyor.

**Neden:** Secret dosyaları `.gitignore` ile Git dışında tutulur — doğru bir güvenlik pratiği. Ancak Jenkins checkout sırasında bu dosyalar workspace'e gelmez.

**Çözüm:** Jenkins Credentials olarak `petclinic-postgres-db`, `petclinic-postgres-user` ve `petclinic-postgres-password` tanımlandı. Pipeline içinde `withCredentials` bloğuyla alınıp Kubernetes Secret oluşturuldu.

---

## 10. Trivy Scan ve Platform Setup Tasarım Kararları

**Trivy:** Security scan reporting modunda çalıştırılıyor — rapor üretir ama build'i fail ettirmez. Production'da policy'ye göre critical vulnerability'lerde build durdurulabilir.

**Platform Add-ons:** Ingress Controller ve Metrics Server cluster-level bileşenlerdir, her build'de tekrar kurulmaları gerekmez. Jenkinsfile'da `RUN_PLATFORM_SETUP` parametresi ile opsiyonel hale getirildi.
