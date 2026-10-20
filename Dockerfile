# =============================================================================
#  eco-air-backend  ::  Imagen de produccion multietapa
#  Objetivo: artefacto ligero, ejecucion sin privilegios y cuotas de hardware.
# =============================================================================

# -----------------------------------------------------------------------------
#  ETAPA 1 (builder): compilacion con el toolchain completo de Maven.
#  Esta etapa NUNCA llega a produccion: aporta unicamente el .jar final.
# -----------------------------------------------------------------------------
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

# Identificador del estudiante inyectado en tiempo de construccion.
ARG STUDENT_ID

LABEL stage="builder" \
      student.id="${STUDENT_ID}"

WORKDIR /build

# (1) Aislamiento del POM: al copiar SOLO el pom.xml, la capa de dependencias
#     queda cacheada y se reutiliza mientras el pom.xml no cambie.
COPY pom.xml .

# (2) Descarga anticipada de dependencias en modo batch para preservar cache
#     entre builds de codigo fuente.
RUN mvn -B dependency:go-offline

# (3) Transferencia del codigo fuente y empaquetado omitiendo pruebas.
COPY src ./src
RUN mvn -B clean package -DskipTests

# -----------------------------------------------------------------------------
#  ETAPA 2 (runtime): JRE minimo, usuario sin privilegios y cuotas declaradas.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine

# El ARG debe redeclararse en esta etapa para poder inyectarlo en el ENV final.
ARG STUDENT_ID

LABEL org.opencontainers.image.title="eco-air-backend" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.description="Procesamiento de alertas ambientales criticas" \
      student.id="${STUDENT_ID}"

# Usuario y grupo de sistema SIN privilegios (UID 10001 / grupo sensorgroup).
RUN addgroup -S -g 10001 sensorgroup \
 && adduser  -S -u 10001 -G sensorgroup -s /sbin/nologin -H sensor_user

WORKDIR /app

# Copia UNICAMENTE del artefacto resultante desde la etapa builder.
COPY --from=builder /build/target/eco-air-backend.jar /app/eco-air-backend.jar

# (4) AppCDS (Class Data Sharing): se entrena el cargador de clases DENTRO de
#     la propia imagen, de modo que en runtime las clases de Spring/Hibernate
#     se mapeen desde disco en vez de parsearse y verificarse en cada arranque.
#     Es lo que permite cumplir el SLA de arranque (< 15 s) en una caja lenta.
ENV CDS_ARCHIVE=/app/eco-air-backend.jsa
RUN set -eux; \
    java -XX:ArchiveClassesAtExit="${CDS_ARCHIVE}" \
         -XX:TieredStopAtLevel=1 \
         -XX:+UseSerialGC \
         -Dspring.context.exit=onRefresh \
         -jar /app/eco-air-backend.jar; \
    test -s "${CDS_ARCHIVE}"; \
    ls -lh /app

# La titularidad del directorio de trabajo pasa al usuario sin privilegios.
RUN chown -R sensor_user:sensorgroup /app

# (5) Variables de entorno ergonomicas para la JVM en contenedor:
#     - UseContainerSupport + MaxRAMPercentage: la JVM deriva el heap del
#       limite de cgroups en lugar del total del host. Asi NUNCA acapara la
#       RAM de la estacion meteorologica aunque el host tenga mucha memoria.
#     - InitialRAMPercentage: reserva temprana controlada.
#     - TieredStopAtLevel=1 + SerialGC: en una estacion remota con 1-2 vCPU el
#       JIT C2 y el GC paralelo cuestan mas de lo que aportan; se recorta el
#       tiempo de arranque sin perder funcionalidad.
#     - SharedArchiveFile: consume el archivo AppCDS generado arriba.
#     - HeapDumpOnOutOfMemoryError: trazabilidad forense ante asfixia de memoria.
ENV JAVA_OPTS="-XX:+UseContainerSupport \
-XX:MaxRAMPercentage=75.0 \
-XX:InitialRAMPercentage=25.0 \
-XX:TieredStopAtLevel=1 \
-XX:+UseSerialGC \
-XX:SharedArchiveFile=/app/eco-air-backend.jsa \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/tmp/eco-air-oom.hprof \
-Djava.security.egd=file:/dev/./urandom \
-Dspring.output.ansi.enabled=NEVER"

# (6) Trazabilidad del operador que construyo la imagen.
ENV OPERATOR_ID=${STUDENT_ID}

EXPOSE 8080

# (7) Descenso de privilegios ANTES del ENTRYPOINT.
USER sensor_user

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/eco-air-backend.jar"]
