# Dependencias del operador RHOAI 3.3 en OpenShift 4.20

**Fecha:** 2026-03-09
**Cluster:** demo-420 (OCP 4.20.15, eu-central-1)
**Topologia:** 3 masters + 3 workers

---

## Estado ANTES de instalar RHOAI

| Recurso | Cantidad |
|---------|----------|
| Subscriptions | 0 |
| CSVs | 1 (packageserver, incluido en OLM) |
| InstallPlans | 0 |
| Operadores adicionales | Ninguno |

El cluster estaba completamente limpio, sin ningún operador adicional instalado.

---

## Estado DESPUES de instalar RHOAI 3.3

### Subscriptions creadas

| Namespace | Operador | Paquete | Canal | Versión | Origen |
|-----------|----------|---------|-------|---------|--------|
| redhat-ods-operator | rhods-operator | rhods-operator | stable-3.3 | 3.3.0 | Instalado manualmente |
| openshift-operators | servicemeshoperator3 | servicemeshoperator3 | stable | 3.1.0 | **Dependencia automatica** |

### CSVs instalados

| Operador | Version | Estado |
|----------|---------|--------|
| Red Hat OpenShift AI (rhods-operator) | 3.3.0 | Succeeded |
| Red Hat OpenShift Service Mesh 3 (servicemeshoperator3) | 3.1.0 | Succeeded |
| Package Server (packageserver) | 0.0.1-snapshot | Succeeded (ya existia) |

### Namespaces creados por RHOAI

| Namespace | Proposito |
|-----------|-----------|
| redhat-ods-operator | Operador RHOAI |
| redhat-ods-applications | Aplicaciones gestionadas por RHOAI |
| redhat-ods-monitoring | Monitorizacion de RHOAI |

### Pods desplegados

| Namespace | Pod | Estado |
|-----------|-----|--------|
| redhat-ods-operator | rhods-operator (x3 replicas) | Running |
| openshift-operators | servicemesh-operator3 (x1) | Running |

---

## Dependencia detectada: Red Hat OpenShift Service Mesh 3

RHOAI 3.3 instala automaticamente **Red Hat OpenShift Service Mesh 3** (v3.1.0) como dependencia.

- **Paquete:** servicemeshoperator3
- **Canal:** stable
- **Version instalada:** 3.1.0 (pinned via startingCSV)
- **InstallPlan:** Aprobacion Manual (no se actualiza automaticamente)
- **Upgrade pendiente:** v3.2.2 (no aprobado, requiere intervencion manual)

### CRDs aportados por Service Mesh 3

Service Mesh 3 registra CRDs de Istio/Sail que RHOAI utiliza internamente para el servicio de inferencia (KServe):

| Grupo | CRDs |
|-------|------|
| extensions.istio.io | WasmPlugin |
| networking.istio.io | DestinationRule, EnvoyFilter, Gateway, ProxyConfig, ServiceEntry, Sidecar, VirtualService, WorkloadEntry, WorkloadGroup |
| security.istio.io | AuthorizationPolicy, PeerAuthentication, RequestAuthentication |
| telemetry.istio.io | Telemetry |
| sailoperator.io | Istio, IstioCNI, IstioRevision, IstioRevisionTag, ZTunnel |

---

## CRDs aportados por RHOAI 3.3

| CRD | Kind | Descripcion |
|-----|------|-------------|
| datascienceclusters.datasciencecluster.opendatahub.io | DataScienceCluster | Recurso principal para configurar el cluster de AI/ML |
| dscinitializations.dscinitialization.opendatahub.io | DSCInitialization | Inicializacion del entorno |
| dashboards.components.platform.opendatahub.io | Dashboard | Consola web de RHOAI |
| workbenches.components.platform.opendatahub.io | Workbenches | Jupyter Notebooks |
| datasciencepipelines.components.platform.opendatahub.io | DataSciencePipelines | Pipelines de ML |
| kserves.components.platform.opendatahub.io | Kserve | Servicio de inferencia |
| modelregistries.components.platform.opendatahub.io | ModelRegistry | Registro de modelos |
| modelsasservices.components.platform.opendatahub.io | ModelsAsService | Modelos como servicio |
| modelcontrollers.components.platform.opendatahub.io | ModelController | Controlador de modelos |
| rays.components.platform.opendatahub.io | Ray | Integracion con Ray |
| kueues.components.platform.opendatahub.io | Kueue | Gestion de colas de trabajo |
| trainers.components.platform.opendatahub.io | Trainer | Entrenamiento de modelos |
| trainingoperators.components.platform.opendatahub.io | TrainingOperator | Operador de entrenamiento |
| trustyais.components.platform.opendatahub.io | TrustyAI | Explicabilidad de modelos |
| feastoperators.components.platform.opendatahub.io | FeastOperator | Feature store |
| mlflowoperators.components.platform.opendatahub.io | MLflowOperator | Tracking de experimentos |
| llamastackoperators.components.platform.opendatahub.io | LlamaStackOperator | Integracion con LlamaStack |
| hardwareprofiles.infrastructure.opendatahub.io | HardwareProfile | Perfiles de hardware (GPU, etc.) |
| auths.services.platform.opendatahub.io | Auth | Autenticacion |
| gatewayconfigs.services.platform.opendatahub.io | GatewayConfig | Configuracion de gateways |
| monitorings.services.platform.opendatahub.io | Monitoring | Monitorizacion |
| featuretrackers.features.opendatahub.io | FeatureTracker | Tracking interno de features |

---

## Resumen

```
Operadores ANTES:  0
Operadores DESPUES: 2
  - rhods-operator 3.3.0           (instalado manualmente)
  - servicemeshoperator3 v3.1.0    (dependencia automatica)

Namespaces nuevos: 3
  - redhat-ods-operator
  - redhat-ods-applications
  - redhat-ods-monitoring

CRDs nuevos: ~60 (22 de RHOAI + ~37 de Service Mesh/Istio)
```

**Conclusion:** RHOAI 3.3 tiene una unica dependencia de operador externo: **Red Hat OpenShift Service Mesh 3** (basado en Istio/Sail). Esta dependencia se instala automaticamente por OLM al crear la suscripcion de RHOAI, sin necesidad de intervencion manual.
