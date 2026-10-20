# FORENSIC_REPORT.md

## Taller Docker — Semana 13

**Proyecto:** `eco-air-backend`
**Imagen:** `eco-air-backend:1.0.0`
**ID del estudiante inyectado:** `898780`
**Fecha de la sesión de auditoría:** 2026-10-20 16:35:32 → 16:40:46 (America/Bogota)
**Registro crudo asociado:** [`audit_session.log`](./audit_session.log) (952 líneas, cierre `CÓDIGO_SALIDA_ORDEN="0"`)

---

## 0. Entorno auditado

Salida exacta del preflight (ver `audit_session.log`, líneas 3-33):

```
user@eco-air-station:~/eco-air-backend$ date --iso-8601=seconds
2026-10-20T16:36:14-05:00

user@eco-air-station:~/eco-air-backend$ uname -a
Linux ubuntu 6.8.0-139-generic #139-Ubuntu SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux

user@eco-air-station:~/eco-air-backend$ docker version --format 'Client:{{.Client.Version}} Server:{{.Server.Version}}'
Client:29.9.0 Server:29.8.2

user@eco-air-station:~/eco-air-backend$ docker info --format 'Kernel={{.KernelVersion}} Storage={{.Driver}} Cgroup={{.CgroupVersion}}/{{.CgroupDriver}} CPUs={{.NCPU}} MemTotal={{.MemTotal}}'
Kernel=7.0.14-linuxkit Storage=overlayfs Cgroup=2/cgroupfs CPUs=4 MemTotal=1961537536

user@eco-air-station:~/eco-air-backend$ nproc
4

user@eco-air-station:~/eco-air-backend$ uptime
 16:36:15 up  4:29,  1 user,  load average: 6.38, 2.98, 3.05

user@eco-air-station:~/eco-air-backend$ cat /proc/loadavg
6.38 2.98 3.05 4/1688 247149
```

> **Dato crítico para interpretar el Reto 3:** el daemon corre sobre una VM con
> **4 vCPU y ~1.87 GiB de RAM (`MemTotal=1961537536`)** y **cgroups v2**. Además,
> en el momento de la auditoría el host presentaba una **carga (`load average`)
> de 6.38 sobre 4 CPU**, es decir, **el sistema estaba sobre-suscrito**
> (más procesos listos que núcleos disponibles). Como el arranque de la JVM es
> prácticamente monohilo (`-XX:TieredStopAtLevel=1`), los tiempos absolutos de
> arranque son sensibles a esa contención. Por eso la fila de **carga del host
> se registró junto a cada medición** del Reto 3.2 (`audit_session.log`,
> líneas 833-880), de modo que la evidencia sea trazable y comparable.

---

## 1. Tabla de identidad (obligatoria)

### 1.1 Hash / UUID de la imagen

```
$ docker inspect --format='{{.Id}}' eco-air-backend:1.0.0
sha256:624afe985bc234de83b6d13a7b2e6889d659d71d6d60d93e23afb44dd298c1d3
```

> El `Id` de una imagen construida con BuildKit incluye el *manifest list* con la
> atestación de procedencia, que lleva marca de tiempo; por eso **cada
> reconstrucción produce un UUID distinto aunque el contenido sea idéntico**. El
> UUID de arriba corresponde exactamente a la imagen auditada en esta sesión
> (aparece dos veces en el log: líneas 682 y 928, antes y después del estrés de
> cgroups, confirmando que la imagen no mutó durante la auditoría).

### 1.2 Firmas SHA-256 de las capas (`RootFS.Layers`)

```
$ docker inspect --format='{{json .RootFS.Layers}}' eco-air-backend:1.0.0
["sha256:74d97c428c51a828f9051a7a40a53ff1fc99e54fc30323ce36760701b0b7f711",
 "sha256:a152dfd2607b01e7c5b933b98da8c746ed0bd242e4f544ff3afd656fdfc7c7a1",
 "sha256:b9398a5bcfd34ada6c3760ac870b064bf54fb191a502393cbb6a3088f8c9be5b",
 "sha256:76b42b7b749e5cf63c4ef5fe61a878a5f508733d81f12305b29e6320007a49de",
 "sha256:6c0c03120c42828b5d975a2b84e53a9ca0ed58b0b0dab9b6c79f5516ddabce2c",
 "sha256:76a7bb53c5fe1c112145b66bd7601678ec05ec835d90e7aa64cd44601ab720ed",
 "sha256:be852191e454bbb91ad2144248847492e08a3d0b3645aa4725d9b2a79fd0de33",
 "sha256:3dc0171c77218aef32d7dc13a4d668f4551f56c37da940e950eab8ac323b12ef",
 "sha256:5db987849d1bc6486d0d293464dcf77b4b3cf977c2ebfb0ed97208f9f45d5a96",
 "sha256:24d141fb32fa16e252ec02dcd5a8b6855afb6c4e66436036d9db470551ab7d80"]
```

Firma del artefacto empaquetado dentro de la imagen:

```
$ docker run --rm --entrypoint sh eco-air-backend:1.0.0 -c 'sha256sum /app/eco-air-backend.jar; ls -l /app'
e41fd8864fef94019c75535249b74a0266fd258a7c6a9d6a04df7187b851346a  /app/eco-air-backend.jar
total 100304
-rw-r--r-- 1 sensor_user sensorgroup 49484478 Oct 20 21:02 eco-air-backend.jar
-r--r--r-- 1 sensor_user sensorgroup 53219328 Oct 20 21:03 eco-air-backend.jsa
```

> **Verificación de idempotencia:** las 10 firmas de capa de `RootFS.Layers` y el
> SHA-256 del `.jar` son **idénticos** a los de la corrida anterior
> (`e41fd886…`), pese a que el UUID de imagen cambió. Esto demuestra que el
> contenido es bit-a-bit reproducible y que la variación del `Id` proviene
> únicamente de la atestación temporal del *manifest list*.

### 1.3 Variable de entorno inyectada

```
$ docker exec eco_air_active env | grep OPERATOR_ID
OPERATOR_ID=898780

$ docker run --rm --entrypoint sh eco-air-backend:1.0.0 -c 'echo OPERATOR_ID=$OPERATOR_ID'
OPERATOR_ID=898780

$ docker image inspect --format='{{json .Config.Labels}}' eco-air-backend:1.0.0
{"org.opencontainers.image.description":"Procesamiento de alertas ambientales criticas",
 "org.opencontainers.image.title":"eco-air-backend",
 "org.opencontainers.image.version":"1.0.0",
 "student.id":"898780"}
```

### 1.4 Consumo final calibrado

```
$ docker stats --no-stream eco_air_active
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O    PIDS
ff291d57d049   eco_air_active   0.18%     155.8MiB / 192MiB   81.14%    4.15kB / 3.64kB   12.3kB / 0B   30
```

---

## 2. Reto 1 — Construcción multietapa con huella estricta

### 2.1 Comando de construcción ejecutado

```bash
docker build --build-arg STUDENT_ID="898780" -t eco-air-backend:1.0.0 .
```

### 2.2 Cumplimiento punto por punto del Dockerfile

| Restricción exigida | Implementación | Evidencia |
|---|---|---|
| Etapa 1 con `maven:3.9.6-eclipse-temurin-17-alpine` | `FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder` | `audit_session.log` L49 (Dockerfile íntegro L39-141) |
| Aislar el `pom.xml` antes de `src/` | `COPY pom.xml .` → `RUN mvn -B dependency:go-offline` → `COPY src ./src` | capas `CACHED [builder 4/6]`–`[builder 6/6]` (L334-336) |
| `ARG STUDENT_ID` | `ARG STUDENT_ID` en **ambas** etapas | `docker history` → `ARG STUDENT_ID=898780` (L667) y `RUN \|1 STUDENT_ID=898780 …` (L660, L661, L665) |
| Empaquetar omitiendo pruebas | `RUN mvn -B clean package -DskipTests` | capa `CACHED [builder 6/6]` (L336) |
| Etapa 2 con `eclipse-temurin:17-jre-alpine` | `FROM eclipse-temurin:17-jre-alpine` | `audit_session.log` L74 |
| Usuario `sensor_user` UID 10001, grupo `sensorgroup` | `addgroup -S -g 10001 sensorgroup && adduser -S -u 10001 -G sensorgroup -s /sbin/nologin -H sensor_user` | `docker exec ... id` → `uid=10001(sensor_user) gid=10001(sensorgroup)` (L751) |
| Copiar **solo** el `.jar` | `COPY --from=builder /build/target/eco-air-backend.jar /app/eco-air-backend.jar` | `ls -l /app` sólo muestra `.jar` + `.jsa` (L691-693) |
| `chown` de `/app` al usuario | `RUN chown -R sensor_user:sensorgroup /app` | `ls -la /app` → `drwxr-xr-x 1 sensor_user sensorgroup` (L782) |
| Variables ergonómicas de JVM | `ENV JAVA_OPTS=...` | `docker image inspect .Config.Env` (L651) |
| `ENV OPERATOR_ID=${STUDENT_ID}` | `ENV OPERATOR_ID=${STUDENT_ID}` | `env \| grep OPERATOR_ID` → `898780` (L755) |
| `USER sensor_user` antes del `ENTRYPOINT` | `USER sensor_user` + `ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/eco-air-backend.jar"]` | `docker history` L655-656: `USER` precede al `ENTRYPOINT` |

### 2.3 Cómo se logró el desacoplamiento real de capas

El build reporta `CACHED` en la capa de dependencias porque el `pom.xml` no cambió:

```
 => CACHED [builder 4/6] RUN mvn -B dependency:go-offline                  0.0s
 => CACHED [builder 5/6] COPY src ./src                                    0.0s
 => CACHED [builder 6/6] RUN mvn -B clean package -DskipTests              0.0s
 => CACHED [stage-1 4/6] COPY --from=builder /build/target/eco-air-backen  0.0s
 => CACHED [stage-1 5/6] RUN set -eux;     java -XX:ArchiveClassesAtExit=  0.0s
 => CACHED [stage-1 6/6] RUN chown -R sensor_user:sensorgroup /app         0.0s
```

Al modificar **solo** un archivo de `src/`, las capas de descarga del árbol de
dependencias Maven se reutilizan y el build salta directamente a compilar. La
etapa `builder` (≈ 600 MB con el repositorio Maven) **no se exporta**:
la imagen final sólo arrastra el JRE y el `.jar`, lo que se comprueba en el
`docker history` (la primera capa de nuestra autoría pesa `49.5MB` = el `.jar`).

---

## 3. Reto 2 — Auditoría forense

### 3.1 Desacoplamiento de capas

```
$ docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
SIZE      CREATED BY
0B        ENTRYPOINT ["sh" "-c" "exec java $JAVA_OPTS …
0B        USER sensor_user
0B        EXPOSE [8080/tcp]
0B        ENV OPERATOR_ID=898780
0B        ENV JAVA_OPTS=-XX:+UseContainerSupport -XX:M…
103MB     RUN |1 STUDENT_ID=898780 /bin/sh -c chown -R…
53.3MB    RUN |1 STUDENT_ID=898780 /bin/sh -c set -eux…
0B        ENV CDS_ARCHIVE=/app/eco-air-backend.jsa
49.5MB    COPY /build/target/eco-air-backend.jar /app/…
8.19kB    WORKDIR /app
32.8kB    RUN |1 STUDENT_ID=898780 /bin/sh -c addgroup…
0B        LABEL org.opencontainers.image.title=eco-air…
0B        ARG STUDENT_ID=898780
0B        ENTRYPOINT ["/__cacert_entrypoint.sh"]
12.3kB    COPY --chmod=755 entrypoint.sh /__cacert_ent…
12.3kB    RUN /bin/sh -c set -eux;     echo "Verifying…
141MB     RUN /bin/sh -c set -eux;     ARCH="$(apk --p…
0B        ENV JAVA_VERSION=jdk-17.0.20.1+1
44MB      RUN /bin/sh -c set -eux;     apk add --no-ca…
0B        ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_AL…
0B        ENV PATH=/opt/java/openjdk/bin:/usr/local/sb…
0B        ENV JAVA_HOME=/opt/java/openjdk
0B        CMD ["/bin/sh"]
9.08MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /…
```

**Lectura forense**

1. **El `ARG STUDENT_ID=898780` es visible en el historial** y `RUN |1
   STUDENT_ID=898780 /bin/sh -c ...` demuestra que el valor se propagó a los pasos
   de la etapa 2. La construcción quedó “sellada” con el ID del estudiante.
2. Las capas de `0B` (la mayoría: `ENV`, `USER`, `LABEL`, `ARG`, `ENTRYPOINT`)
   son **solo metadatos**, no almacenan bytes. El ID del estudiante **no añade
   peso** a la imagen: queda como etiqueta y variable de entorno.
3. `49.5MB COPY /build/target/eco-air-backend.jar` confirma que **de la etapa
   `builder` sólo se copió el artefacto**: no hay `src/`, ni `pom.xml`, ni el
   repositorio `~/.m2` (que en la etapa builder pesa cientos de MB).
4. La capa `141MB` corresponde a la descarga del JRE (`ARCH=...apk`) y la de
   `44MB` a los paquetes `apk` del sistema. Son el piso inevitable del runtime.
5. La capa `53.3MB` es el archivo AppCDS (`eco-air-backend.jsa`) generado en
   tiempo de build; la capa `103MB` es el `chown -R` del directorio `/app`
   (reescribe la capa del jar, ya que `chown` materializa una capa nueva).
6. El orden final del historial (de arriba hacia abajo = de lo más nuevo a lo
   más antiguo) muestra `USER sensor_user` **inmediatamente antes** del
   `ENTRYPOINT`, que es el orden requerido para que el proceso nazca sin
   privilegios.

### 3.2 Aislamiento de privilegios del proceso

```
$ docker run -d --name eco_air_active -p 8080:8080 eco-air-backend:1.0.0
487301a25b85260887e5b5e93d53ef27240583f38cc55aae999aec54837ee118

$ sleep 12

$ docker top eco_air_active -o pid,user,comm
PID                 USER                COMMAND
653                 10001               java

$ docker exec eco_air_active ps -o pid,user,comm
PID   USER     COMMAND
    1 sensor_u java
   29 sensor_u ps

$ docker exec eco_air_active id
uid=10001(sensor_user) gid=10001(sensorgroup) groups=10001(sensorgroup)
```

**Evidencia solicitada (el comando `java` NO corre como root):**

| Observación | Resultado | Interpretación |
|---|---|---|
| `docker top -o user` | **`10001`** | El kernel reporta el UID numérico porque `10001` no existe en el `/etc/passwd` del **host**; lo importante es que **no es `0` (root)**. |
| `ps` interno del contenedor | **`sensor_u` (sensor_user)** | Dentro del contenedor el UID 10001 sí resuelve al nombre `sensor_user`. |
| `COMMAND` | **`java`** | El `ENTRYPOINT` usa `exec`, por lo que el `sh` se reemplaza y **`java` es PID 1** (no un `sh` huérfano). |
| `id` | `uid=10001(sensor_user) gid=10001(sensorgroup)` | El proceso corre con usuario/grupo sin privilegios y **sin grupos suplementarios** (ni `root`, ni `wheel`, ni `docker`). |

Consecuencia operativa: si un atacante lograra ejecución de código dentro de la
JVM, heredaría un UID sin permisos sobre el sistema de archivos del host.

### 3.3 Test de penetración: inmutabilidad de runtime

```
$ docker exec eco_air_active touch /etc/crontab_fake
touch: cannot touch '/etc/crontab_fake': Permission denied
[exit=1]

$ docker exec eco_air_active ls -l /etc/crontab_fake
ls: cannot access '/etc/crontab_fake': No such file or directory
[exit=2]
```

**Análisis**

* `/etc` pertenece a `root:root` con permisos `755`; el proceso corre con
  `uid=10001(sensor_user)`, por lo que la escritura es **denegada por el núcleo
  (`EPERM`)** y el comando retorna código de salida `1`.
* La verificación posterior (`ls`) devuelve `No such file or directory`
  (código `2`): **el archivo malicioso nunca se creó**. No hay persistencia
  posible (por ejemplo vía `crontab`) desde dentro del contenedor.
* El vector de “escalada por escritura en rutas del sistema” queda **cerrado por
  diseño**: usuario sin privilegios + ausencia de `sudo`/`setuid` + root
  filesystem no escribible por UID 10001.

### 3.4 Auditoría de artefactos de desarrollo

```
$ docker exec eco_air_active which mvn
[exit=1]

$ docker exec eco_air_active find / -name "*.java" 2>/dev/null
[exit=1]

$ docker exec eco_air_active ls -la /app
total 100312
drwxr-xr-x 1 sensor_user sensorgroup     4096 Oct 20 21:03 .
drwxr-xr-x 1 root        root            4096 Oct 20 21:36 ..
-rw-r--r-- 1 sensor_user sensorgroup 49484478 Oct 20 21:02 eco-air-backend.jar
-r--r--r-- 1 sensor_user sensorgroup 53219328 Oct 20 21:03 eco-air-backend.jsa
```

**Análisis**

| Salida | Explicación |
|---|---|
| `which mvn` → **vacío, `exit=1`** | **No existe Maven en la imagen de runtime.** El toolchain de compilación quedó confinado a la etapa `builder`, que no se exporta. |
| `find / -name "*.java"` → **vacío, `exit=1`** | **No hay una sola fuente `.java` en todo el contenedor.** El código compilado vive dentro del `.jar` (bytecode). |
| `ls -la /app` | Sólo dos artefactos: el ejecutable `.jar` y el archivo de clases compartidas `.jsa` (AppCDS). Ninguno de los dos es código fuente legible. |

**Impacto de seguridad:** un atacante que consiguiera shell dentro del contenedor
no encuentra compilador, ni código fuente, ni `pom.xml` para reconstruir o
manipular el artefacto. La superficie de fuga de propiedad intelectual y de
“recompilación con backdoor” queda eliminada.

---

## 4. Reto 3 — Calibración de cgroups y captura del asesino OOM

### 4.1 Inducción del colapso por memoria (48 MB)

```
$ docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
8ca9d8a73f144f11c3da604496875d8d716e401e8ebc47a34ddcc02c1a614441

$ sleep 10
$ docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
Status: running | ExitCode: 0 | OOMKilled: false        <-- aún agonizando a los 10 s

$ docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
Status: exited | ExitCode: 137 | OOMKilled: true        <-- deceso efectivo

$ docker inspect eco_air_crash --format='MemoryLimit={{.HostConfig.Memory}} bytes'
MemoryLimit=50331648 bytes
```

El log del contenedor demuestra **hasta dónde alcanzó a arrancar antes de morir**
(se cortó justo al inicializar JPA/Hibernate):

```
$ docker logs --timestamps --tail 20 eco_air_crash
2026-10-20T21:37:09.628Z  INFO ... com.ecoair.EcoAirApplication : Starting EcoAirApplication v1.0.0 using Java 17.0.20.1 with PID 1 (/app/eco-air-backend.jar started by sensor_user in /app)
2026-10-20T21:37:14.769Z  INFO ... .s.d.r.c.RepositoryConfigurationDelegate : Bootstrapping Spring Data JPA repositories in DEFAULT mode.
2026-10-20T21:37:15.367Z  INFO ... .s.d.r.c.RepositoryConfigurationDelegate : Finished Spring Data repository scanning in 489 ms. Found 1 JPA repository interface.
   <-- el kernel envía SIGKILL aquí (no hay más logs)
```

**Análisis del resultado**

| Campo | Valor | Significado |
|---|---|---|
| `State.Status` | `exited` | El contenedor **no** está vivo. |
| `State.ExitCode` | `137` | `128 + 9` = el proceso recibió **`SIGKILL` (señal 9)**. |
| `State.OOMKilled` | `true` | Bandera que el daemon pone **únicamente** cuando el **OOM killer del kernel** mató al proceso por exceder el límite de *cgroup*. |
| `HostConfig.Memory` | `50331648` | 48 × 1024 × 1024 = 48 MiB, exactamente el límite impuesto por `-m 48m`. |

> Detalle forense: a los 10 segundos del `docker run` el contenedor **seguía en
> estado `running` con `OOMKilled=false`**. Eso es coherente: la JVM aún no
> había tocado el techo del *cgroup* durante el arranque. La sesión esperó al
> deceso efectivo (hasta 12 × 5 s) y recién ahí se capturó
> `ExitCode=137 / OOMKilled=true`. Este es el comportamiento real del OOM killer:
> **no mata antes de que el RSS supere el límite**.

**Cadena causal (resumen):**

```
Spring Boot + Hibernate + Tomcat reservan metaspace, heap, code cache,
hilos y estructuras de GC
        ↓
el RSS del cgroup supera los 48 MiB (el log se corta en el escaneo de repositorios JPA)
        ↓
cgroup v2 dispara memory.oom.group → el kernel envía SIGKILL al "mayor consumidor"
        ↓
el proceso java muere con la señal 9  →  ExitCode = 128 + 9 = 137
        ↓
el daemon marca OOMKilled = true
```

Con `-XX:MaxRAMPercentage=75.0` la JVM ya se dimensiona contra el límite del
*cgroup* (y no contra la RAM del host): el heap máximo habría sido ~36 MiB,
insuficiente para arrancar Spring Boot con Hibernate (que necesita del orden de
140 MiB).

### 4.2 Calibración del límite operativo mínimo

Barrido iterativo (`audit_session.log`, líneas 828-880). En cada iteración se
registra la **carga del host**, se espera el log de arranque y se lee el consumo
en caliente con `docker stats --no-stream`:

| `-m` | Límite real (bytes) | carga host (1-5-15) | ¿Arrancó? | Tiempo de arranque | MEM USAGE / LIMIT | MEM % | Veredicto |
|---|---|---|---|---|---|---|---|
| `48m` | 50 331 648 | — (no medida en esa sección) | **No** | — | — | — | **OOMKilled (137)** |
| `96m` | 100 663 296 | 7.13 / 3.85 / 3.35 | Sí | **29.084 s** | 95.89MiB / 96MiB | **99.89 %** | ❌ incumple SLA (<15 s) y sin margen |
| `128m` | 134 217 728 | 5.86 / 3.95 / 3.40 | Sí | **15.797 s** | 127.9MiB / 128MiB | **99.91 %** | ❌ incumple SLA y **sin margen** |
| `144m` | 150 994 944 | 5.39 / 3.97 / 3.42 | Sí | 14.958 s | 140MiB / 144MiB | **97.25 %** | ⚠️ cumple por 0.04 s, **sin margen real** |
| **`160m`** | 167 772 160 | 6.09 / 4.24 / 3.52 | Sí | **13.998 s** | 140.2MiB / 160MiB | **87.61 %** | ✅ **umbral mínimo exacto** |
| `176m` | 184 549 376 | 5.48 / 4.25 / 3.55 | Sí | 14.158 s | 141.2MiB / 176MiB | 80.25 % | ✅ cumple |
| `192m` | 201 326 592 | 5.88 / 4.44 / 3.63 | Sí | 13.659 s | 141.5MiB / 192MiB | 73.70 % | ✅ **límite consolidado** |
| `256m` | 268 435 456 | 5.62 / 4.47 / 3.66 | Sí | 13.816 s | 146.1MiB / 256MiB | 57.07 % | ✅ holgado (desperdicia ~60 MB) |

Salida literal de una iteración representativa (la del umbral):

```
-------------------------------- LIMITE -m 160m --------------------------------
    carga_host(loadavg1-5-15)=6.09 4.24 3.52
>> tiempo_hasta_log_started=14s (vacio = no arranco dentro de la ventana)
>> Status: running | ExitCode: 0 | OOMKilled: false | MemoryLimit: 167772160 bytes
Started EcoAirApplication in 13.998 seconds
3264422f7b81   eco_air_cal   0.20%     140.2MiB / 160MiB   87.61%    872B / 126B   0B / 0B     30
```

**Nota metodológica sobre la carga del host.** El tiempo de arranque (`Started
EcoAirApplication in X seconds`, medido por la propia JVM) es monohilo y, por
tanto, muy sensible a la contención de CPU. En esta sesión el host estaba
**sobre-suscrito** (**load average 6.38 sobre 4 vCPU**, con picos de 7.13 en la
primera iteración). Esto se observa en la tabla: la fila de `96m` se midió con
`load=7.13` y arrancó en **29.084 s**, y `128m` con `load=5.86` en **15.797 s**
(apenas por encima del SLA). A partir de `160m` —ya con `load≈6` estabilizado y
sin la presión de memoria del cgroup— el arranque se mantiene en **~14 s**. Las
medidas son reproducibles dentro de la misma sesión y **la columna de memoria es
completamente independiente de la carga**: es la que define el umbral.

**Conclusión de la calibración**

* **Umbral mínimo exacto con las tres condiciones simultáneas = `160m`.**
  Es el primer valor donde (1) el contenedor arranca, (2) arranca en **13.998 s
  < 15 s** y (3) el consumo se estabiliza con un margen real (**87.61 %**, es
  decir ~20 MB libres para picos; por debajo de 160m el `MEM %` salta a 97-99 %
  y cualquier ráfaga provocaría `OOMKilled`).
* `128m` y `144m` **sí arrancan**, pero dejan el consumo en **99.91 % / 97.25 %**:
  un pico de ráfaga de métricas de los sensores provocaría `OOMKilled`
  instantáneo → **no son operativamente viables**.
* `96m` demuestra que existe un punto donde el contenedor **vive pero degradado**
  (heap comprimido → GC constante → 29 s de arranque).

### 4.3 Consolidación del límite calibrado

Por seguridad operativa se consolidó **`192m`** (margen ~20 % frente al umbral
mínimo de `160m`) para absorber las “ráfagas continuas de métricas” descritas en
el caso:

```
$ docker run -d --name eco_air_active -m 192m -p 8080:8080 eco-air-backend:1.0.0
ff291d57d049ee7c3f2a287097f7c76fe5bca02a9dde136478504c1ae954ee70

$ sleep 16

$ docker logs --timestamps eco_air_active | grep 'Started EcoAirApplication'
2026-10-20T21:40:38.525976072Z 2026-10-20T21:40:38.525Z  INFO 1 --- [eco-air-backend] [           main] com.ecoair.EcoAirApplication : Started EcoAirApplication in 13.565 seconds (process running for 14.9)
```

`Started EcoAirApplication in 13.565 seconds` → **13.565 s < 15 s ✅**

Tabla resultante de `docker stats` (consigna: % CPU, MEM USAGE / LIMIT y MEM %):

```
$ docker stats --no-stream eco_air_active
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O   PIDS
ff291d57d049   eco_air_active   0.34%     141.6MiB / 192MiB   73.73%    1.17kB / 126B   0B / 0B     30
```

| Indicador | Valor |
|---|---|
| **% CPU** | `0.34 %` (contenedor en reposo tras completar el arranque) |
| **MEM USAGE / LIMIT** | `141.6MiB / 192MiB` |
| **MEM %** | `73.73 %` |

Verificación funcional de que el proceso está realmente operativo (no sólo “vivo”):

```
$ curl -s ... http://localhost:8080/actuator/health
health (cold, dispara lazy-init): HTTP 200 en 1.086267s
health (warm): HTTP 200 en 0.014392s

$ curl -s http://localhost:8080/actuator/health
{"status":"UP","components":{"db":{"status":"UP","details":{"database":"H2",...}},"diskSpace":{"status":"UP",...},"ping":{"status":"UP"}}}

$ curl -s -X POST -H 'Content-Type: application/json' -d '{"stationId":"WS-01","pollutant":"PM2.5","concentration":412.7,"severity":"CRITICAL"}' http://localhost:8080/api/alerts
{"id":1,"stationId":"WS-01","pollutant":"PM2.5","concentration":412.7,"severity":"CRITICAL","detectedAt":"2026-10-20T21:40:43.398955957Z"}
```

### 4.4 Cómo se consiguió un arranque < 15 s en una caja de 4 vCPU / 1.87 GiB

El arranque de Spring Boot + Hibernate en este entorno tiene un costo dominado
por **carga y verificación de clases + JIT**. Se atacó por dos vías, sin tocar la
lógica de negocio:

1. **Ergonomía de JVM** (`ENV JAVA_OPTS`, etapa 2 del Dockerfile):
   * `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0` → la JVM deriva el heap
     del **límite de cgroups**, nunca de la RAM del host.
   * `-XX:TieredStopAtLevel=1` → desactiva el compilador JIT C2 (irrelevante en un
     arranque corto) y reduce drásticamente el trabajo de compilación inicial.
   * `-XX:+UseSerialGC` → evita arrancar hilos de GC paralelo en una caja de 4
     vCPU compartidas.
2. **AppCDS (Class Data Sharing) generado en tiempo de build**:
   la propia imagen “entrena” el cargador de clases con un arranque controlado
   (`-Dspring.context.exit=onRefresh`) y persiste el resultado en
   `/app/eco-air-backend.jsa` (≈53 MB). En runtime la JVM **mapea ese archivo** en
   lugar de parsear y verificar las ~10 000 clases de Spring/Hibernate. Se
   verificó que el mapeo ocurre realmente:

   ```
   [0.051s][info][cds] Opened archive /app/eco-air-backend.jsa.
   [0.071s][info][cds] Mapped static  region #0 at base 0x... (ReadWrite)
   [0.071s][info][cds] Mapped static  region #1 at base 0x... (ReadOnly)
   ```

   *Trade-off documentado:* el archivo `.jsa` añade ~53 MB al tamaño de la imagen.
   Se acepta porque el SLA de arranque es un requisito explícito del taller y
   porque la imagen builder descartada (≈ 600 MB con el repositorio Maven) es
   muchísimo mayor.

---

## 5. Justificación técnica global del diseño

| Decisión | Por qué |
|---|---|
| **Multi-stage** | El toolchain de compilación (`maven`, JDK, `~/.m2`) no debe viajar a producción: reduce tamaño, superficie de ataque y elimina la posibilidad de recompilar dentro del contenedor. |
| **`COPY pom.xml` → `go-offline` → `COPY src`** | Convierte la descarga de dependencias en una capa cacheable; los builds por cambio de código bajan de minutos a segundos. |
| **`mvn -DskipTests`** | El pipeline de pruebas unitarias pertenece al CI, no al empaquetado de la imagen; evita arrastrar `surefire` y sus dependencias. |
| **JRE Alpine en vez de JDK Debian** | `eclipse-temurin:17-jre-alpine` pesa una fracción del JDK y no incluye `javac`, `jshell` ni `jlink`. |
| **`sensor_user` (UID 10001) + `USER` antes del `ENTRYPOINT`** | Principio de mínimo privilegio: un compromiso de la aplicación no otorga permisos de root ni siquiera dentro del contenedor. |
| **`chown -R sensor_user:sensorgroup /app`** | El usuario sin privilegios debe ser titular del directorio de trabajo para que la JVM pueda escribir (dumps, archivos temporales de Tomcat). |
| **`-XX:MaxRAMPercentage` en lugar de `-Xmx` fijo** | La cuota se expresa **una sola vez** (`-m` en el `docker run`/orquestador) y la JVM se adapta sola. Evita tener el límite duplicado y desincronizado. |
| **`OPERATOR_ID` desde `ARG STUDENT_ID`** | Trazabilidad de construcción: cada imagen queda “firmada” con el ID del estudiante que la generó, exigible en la auditoría. |
| **AppCDS** | Convierte trabajo de arranque (parseo/verificación de clases) en un *mmap* de disco; imprescindible para cumplir el SLA en hardware modesto. |
| **`-m 192m`** | Umbral mínimo real `160m` + margen para las ráfagas de métricas descritas en el caso; evita el `OOMKilled` que el propio taller exige provocar a 48 MB. |

---

## 6. Guía de reproducción

### 6.1 Cómo se generó el `audit_session.log`

El log **no es un archivo escrito a mano**: es el transcript crudo que produce
`script(1)` al ejecutar el motor de auditoría. Desde la raíz del proyecto:

```bash
cd eco-air-backend
script -e -c "bash /tmp/audit_session.sh" audit_session.log
```

`-e` propaga el código de salida del hijo (por eso el log cierra con
`[CÓDIGO_SALIDA_ORDEN="0"]`). El script borra los contenedores previos, construye
la imagen y ejecuta los tres retos de forma secuencial y no interactiva.

### 6.2 Comandos del taller (uno a uno)

```bash
# 1) Construir (STUDENT_ID = ID real del estudiante)
docker build --build-arg STUDENT_ID="898780" -t eco-air-backend:1.0.0 .

# 2) Reto 2 — auditoría forense
docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
docker run -d --name eco_air_active -p 8080:8080 eco-air-backend:1.0.0
docker top eco_air_active -o pid,user,comm
docker exec eco_air_active touch /etc/crontab_fake
docker exec eco_air_active which mvn
docker exec eco_air_active find / -name "*.java" 2>/dev/null

# 3) Reto 3 — cgroups
docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
sleep 10
docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
docker rm -f eco_air_active
docker run -d --name eco_air_active -m 192m -p 8080:8080 eco-air-backend:1.0.0
sleep 16
docker logs --timestamps eco_air_active | grep "Started EcoAirApplication"
docker stats --no-stream eco_air_active
```

> **Nota sobre el `STUDENT_ID`:** el valor `898780` es el usado en esta sesión de
> auditoría. El `ARG` forma parte de la configuración de la imagen, por lo que
> **cualquier cambio de ID exige reconstruir** y **regenerar toda la evidencia**
> (UUID de imagen y firmas de capas cambian).

---

## 7. Índice de evidencias

| # | Evidencia | Ubicación en `audit_session.log` |
|---|---|---|
| 1 | Preflight del entorno (kernel, storage, cgroups, CPU, RAM, **carga**) | líneas 3-33 |
| 2 | `Dockerfile` íntegro (L39-141) y `.dockerignore` (L142-184) | líneas 39-184 |
| 3 | Build multietapa con `--build-arg` y capas `CACHED` | líneas 186-635 |
| 4 | Labels / ENV / ENTRYPOINT con `STUDENT_ID` | líneas 637-692 |
| 5 | UUID de la imagen (`docker inspect --format='{{.Id}}'`) | líneas 681-683 |
| 6 | Firmas SHA-256 de las capas (`RootFS.Layers`) | líneas 685-687 |
| 7 | SHA-256 del `.jar` dentro de la imagen | líneas 689-693 |
| 8 | Desacoplamiento de capas (`docker history --human`) | líneas 696-726 |
| 9 | Proceso sin privilegios (`docker top`, `ps`, `id`) | líneas 728-757 |
| 10 | Test de penetración (`touch /etc/crontab_fake` → denegado) | líneas 759-768 |
| 11 | Ausencia de artefactos de desarrollo (`which mvn`, `find *.java`) | líneas 770-786 |
| 12 | `OOMKilled` a 48 MB (`ExitCode 137`, `OOMKilled true`) + log truncado | líneas 788-826 |
| 13 | Calibración iterativa 96m→256m con **carga del host** y `docker stats` | líneas 828-880 |
| 14 | Consolidación a 192m + `Started ... in 13.565 seconds` | líneas 882-904 |
| 15 | Prueba funcional HTTP (health + POST/GET de alertas) | líneas 906-921 |
| 16 | Tabla de identidad final (`OPERATOR_ID`, `id`, `stats`) | líneas 924-947 |
