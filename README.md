# OpenShift UPI en AWS con Ansible y Terraform

Automatización para desplegar clusters OpenShift (UPI) en AWS usando Ansible como orquestador y Terraform para aprovisionar la infraestructura.

## Requisitos previos

- **Ansible** >= 2.14
- **Terraform** >= 1.5
- **AWS CLI** v2 configurado con un perfil válido
- **Python 3** con el módulo `json`
- Colección Ansible `community.crypto`:
  ```bash
  ansible-galaxy collection install community.crypto
  ```
- Una **zona Route53 pública** ya creada para el dominio base
- Un **pull secret** de Red Hat descargado desde [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret), guardado como `pull-secret.txt` en la raíz del proyecto

## Versiones de OpenShift soportadas

| Versión | Release completa |
|---------|-----------------|
| 4.16    | 4.16.32         |
| 4.17    | 4.17.50         |
| 4.18    | 4.18.34         |
| 4.19    | 4.19.24         |
| 4.20    | 4.20.15         |
| 4.21    | 4.21.4          |

Se pueden añadir nuevas versiones editando `ocp_versions` en `roles/ocp_upi_aws/defaults/main.yml`.

## Uso

### Desplegar un cluster

```bash
ansible-playbook playbook.yml \
  -e cluster_name=mi-cluster \
  -e base_domain=mi-dominio.com \
  -e ocp_version=4.16 \
  -e aws_region=eu-west-1 \
  -e aws_profile=mi-perfil
```

### Parámetros

| Parámetro       | Obligatorio | Default        | Descripción                                      |
|-----------------|-------------|----------------|--------------------------------------------------|
| `cluster_name`  | Sí          | `ocp-cluster`  | Nombre del cluster (usado en recursos AWS)        |
| `base_domain`   | Sí          | `example.com`  | Dominio base (debe existir como zona en Route53)  |
| `ocp_version`   | No          | `4.16`         | Versión mayor de OpenShift                        |
| `ocp_version_full` | No       | (auto)         | Release específica (ej: `4.16.20`). Si no se indica, usa la última configurada |
| `aws_region`    | No          | `eu-west-1`    | Región AWS donde desplegar                        |
| `aws_profile`   | No          | (vacío)        | Perfil de AWS CLI a usar                          |
| `vpc_cidr`      | No          | `10.0.0.0/16`  | CIDR de la VPC                                    |
| `force_destroy`  | No          | `false`        | Forzar destrucción de infraestructura existente   |

### Usar una release específica

Por defecto se usa la última release configurada para cada versión mayor. Para instalar una release concreta, pasa `ocp_version_full`:

```bash
ansible-playbook playbook.yml \
  -e cluster_name=mi-cluster \
  -e base_domain=mi-dominio.com \
  -e ocp_version=4.16 \
  -e ocp_version_full=4.16.20 \
  -e aws_region=eu-west-1 \
  -e aws_profile=mi-perfil
```

> **Nota:** Es necesario seguir indicando `ocp_version` (versión mayor) porque se usa para obtener la AMI de RHCOS y para organizar los directorios de binarios y clusters.

### Ejemplo: dos clusters en paralelo

```bash
# Cluster OCP 4.16 en Irlanda
ansible-playbook playbook.yml \
  -e cluster_name=demo-416 \
  -e base_domain=sandbox.example.com \
  -e ocp_version=4.16 \
  -e aws_region=eu-west-1 \
  -e aws_profile=demo

# Cluster OCP 4.20 en Frankfurt
ansible-playbook playbook.yml \
  -e cluster_name=demo-420 \
  -e base_domain=sandbox.example.com \
  -e ocp_version=4.20 \
  -e aws_region=eu-central-1 \
  -e aws_profile=demo
```

## Acceso al cluster

Al finalizar la instalación, el playbook muestra las credenciales y URLs de acceso. También puedes configurar tu terminal manualmente:

```bash
export KUBECONFIG=clusters/<cluster_name>/<version>/<region>/ocp/auth/kubeconfig
export PATH=$(pwd)/bin/<version>:$PATH

oc get nodes
oc get co
```

## Estructura del proyecto

```
.
├── playbook.yml                          # Playbook principal
├── pull-secret.txt                       # Pull secret de Red Hat (NO versionado)
└── roles/
    └── ocp_upi_aws/
        ├── defaults/main.yml             # Variables por defecto
        ├── tasks/main.yml                # Tareas del rol (13 fases)
        ├── templates/
        │   ├── install-config.yaml.j2    # Template de install-config
        │   └── terraform.tfvars.j2       # Template de variables Terraform
        └── files/terraform/
            ├── variables.tf              # Variables y provider AWS
            ├── network.tf                # VPC, subnets, NAT, S3 endpoint
            ├── security.tf               # Security groups
            ├── iam.tf                    # Roles, policies, instance profiles
            ├── s3.tf                     # Bucket S3 para ignition
            ├── load_balancers.tf         # NLBs (API, Ingress)
            ├── dns.tf                    # Registros Route53
            └── compute.tf               # Instancias EC2 (bootstrap, masters, workers)
```

## Fases de la instalación

1. **Resolución de versión y AMI** - Obtiene la versión completa y la AMI de RHCOS para la región
2. **Validación de credenciales AWS** - Verifica identidad y región habilitada
3. **Protección contra conflictos** - Detecta metadata y terraform state existentes
4. **Detección de recursos huérfanos** - Busca IAM roles/policies y ELBv2 residuales
5. **Validación de Route53** - Verifica zona DNS y detecta registros existentes
6. **Creación de directorios** - Prepara estructura y guarda metadata
7. **Descarga de binarios** - `openshift-install` y `oc` para la versión solicitada
8. **Generación de SSH key** - Clave ED25519 para acceso a nodos
9. **Generación de configs** - install-config, manifests, ignition
10. **Terraform** - Provisiona toda la infraestructura AWS
11. **Bootstrap** - Espera a que el bootstrap complete (hasta 45 min)
12. **Aprobación de CSRs** - Aprueba certificados de workers automáticamente
13. **Finalización** - Espera a install-complete y muestra resumen con credenciales

## Infraestructura creada

- 1 VPC con 3 subnets públicas y 3 privadas
- 3 NAT Gateways (uno por AZ)
- VPC Gateway Endpoint para S3
- 3 NLBs (API externa, API interna, Ingress)
- Security groups para masters y workers
- IAM roles/policies con sufijos únicos para evitar colisiones
- S3 bucket para configs de ignition
- Registros DNS en Route53 (api, api-int, *.apps)
- 1 instancia bootstrap (m5.2xlarge, 120GB gp3)
- 3 instancias master (m5.2xlarge, 120GB gp3)
- 3 instancias worker (m5.large, 120GB gp3)

## Destrucción

Para destruir un cluster, usa terraform directamente:

```bash
cd clusters/<cluster_name>/<version>/<region>/terraform
AWS_PROFILE=<perfil> terraform destroy -auto-approve
```

> **Nota:** Los recursos creados dinámicamente por OpenShift (ELBs clásicos del Cloud Controller Manager, security groups de tipo `k8s-elb-*`) no están gestionados por Terraform y deben eliminarse manualmente antes de destruir la VPC.
