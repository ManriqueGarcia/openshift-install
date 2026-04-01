# Guía paso a paso: Instalación OpenShift UPI en AWS con Dual-NIC

## Objetivo

Instalar un cluster OpenShift en AWS con infraestructura UPI donde cada nodo tiene
**dos interfaces de red en subredes distintas**, cada una con su propio gateway.
La interfaz primaria (`ens5`) se gestiona a través de un OVS bridge (`br-ex`)
controlado por OVN-Kubernetes; la secundaria (`ens6`) opera de forma independiente.

## Requisitos previos

- Cuenta AWS con permisos para crear VPC, EC2, IAM, Route53, ELB, S3
- Zona Route53 pública para el dominio base (ej. `sandbox948.opentlc.com`)
- Fichero `pull-secret.txt` de [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) en la raíz del repositorio
- Ansible instalado en la máquina local
- Perfil AWS configurado (`aws configure --profile demo`)

## Paso 1: Clonar el repositorio

```bash
git clone <url-del-repositorio> openshift-install
cd openshift-install
```

Estructura relevante:

```
openshift-install/
├── playbook.yml
├── pull-secret.txt
├── roles/ocp_upi_aws/
│   ├── defaults/main.yml
│   ├── files/terraform/
│   │   ├── network.tf       # VPC, subredes primarias y secundarias
│   │   ├── compute.tf       # instancias EC2 y ENIs
│   │   ├── security.tf      # security groups
│   │   ├── dns.tf
│   │   ├── load_balancers.tf
│   │   ├── s3.tf
│   │   ├── iam.tf
│   │   └── variables.tf
│   ├── templates/
│   │   ├── install-config.yaml.j2
│   │   ├── terraform.tfvars.j2
│   │   ├── nmstate-br-ex.yml.j2
│   │   └── 99-nmstate-br-ex.yaml.j2
│   └── tasks/main.yml
└── docs/
```

## Paso 2: Entender la topología de red

Con `enable_dual_nic=true` se crean dos conjuntos de subredes privadas:

```
VPC 10.0.0.0/16
│
├── 10.0.10-12.0/24   Públicas (bootstrap, NAT GWs)
│
├── 10.0.20-22.0/24   Privadas primarias ─── ens5 → br-ex (métrica 48)
│                      Una por AZ, gateway 10.0.2x.1
│
└── 10.0.30-32.0/24   Privadas secundarias ── ens6 (métrica 101)
                       Una por AZ, gateway 10.0.3x.1
```

Cada nodo EC2 queda con dos rutas default:

```
default via 10.0.20.1 dev br-ex  metric 48    ← primaria (OVN-K)
default via 10.0.30.1 dev ens6   metric 100   ← secundaria
```

## Paso 3: Revisar la configuración por defecto

Abrir `roles/ocp_upi_aws/defaults/main.yml` y verificar los valores:

```yaml
enable_dual_nic: false          # se activa desde la línea de comandos
vpc_cidr: "10.0.0.0/16"        # debe ser /16 para tener espacio
```

La variable `enable_dual_nic` controla condicionalmente:
- La creación de subredes secundarias en Terraform
- La creación de ENIs secundarios
- La inyección de MachineConfigs NMState

## Paso 4: Ejecutar la instalación

Un solo comando lanza el proceso completo:

```bash
ansible-playbook playbook.yml \
  -e "cluster_name=mi-cluster" \
  -e "ocp_version=4.18" \
  -e "base_domain=ejemplo.com" \
  -e "aws_region=eu-west-1" \
  -e "aws_profile=demo" \
  -e "enable_dual_nic=true"
```

### Lo que hace el playbook automáticamente

El playbook ejecuta 13 fases secuenciales:

**Fase 1-5: Validaciones**
- Resuelve la versión OCP y la AMI de RHCOS para la región
- Valida credenciales AWS y zona Route53
- Detecta recursos huérfanos (IAM, ELB, DNS) que pudieran causar conflictos

**Fase 6-7: Preparación**
- Crea directorios de trabajo
- Descarga binarios: `openshift-install`, `oc`, `terraform`

**Fase 8: SSH**
- Genera un par de claves Ed25519 para acceso a los nodos

**Fase 9: Manifiestos e Ignition** (aquí interviene dual-NIC)
1. Genera `install-config.yaml` desde template
2. Ejecuta `openshift-install create manifests`
3. Parchea ControlPlaneMachineSet a `Inactive` (necesario en UPI)
4. **Si `enable_dual_nic=true`:**
   - Renderiza `nmstate-br-ex.yml` con la configuración NMState
   - Lo codifica en base64
   - Inyecta un `MachineConfig` en `openshift/99-nmstate-br-ex.yaml`
     que deposita el fichero en `/etc/nmstate/openshift/cluster.yml`
     en cada nodo (master y worker)
5. Ejecuta `openshift-install create ignition-configs`

**Fase 10: Terraform**
1. Copia los `.tf` al directorio de trabajo
2. Genera `terraform.tfvars` (incluye `enable_dual_nic = true`)
3. `terraform init` → `plan` → `apply`
4. Terraform crea:
   - VPC con subredes públicas, privadas primarias y **secundarias**
   - Instancias EC2 (bootstrap, 3 masters, 3 workers)
   - **ENIs secundarios** en las subredes `10.0.3x.0/24`, asociados con `device_index=1`
   - Security groups con reglas internas (all traffic entre master/worker)
   - Load balancers, DNS, S3, IAM

**Fase 11-13: Bootstrap e instalación**
- Espera el bootstrap (45 min timeout)
- Aprueba CSRs de workers
- Espera la instalación completa
- Muestra credenciales de acceso

## Paso 5: Qué ocurre en los nodos durante el arranque

### Masters (flujo con NMState)

1. La instancia EC2 arranca con dos ENIs:
   - `ens5` (device_index=0) en `10.0.2x.0/24`
   - `ens6` (device_index=1) en `10.0.3x.0/24`
2. Ignition escribe el fichero NMState en `/etc/nmstate/openshift/cluster.yml`
3. El servicio `machine-config-daemon-firstboot` procesa los MachineConfigs,
   aplica la configuración NMState, crea el marcador `/etc/nmstate/openshift/applied`,
   y reinicia el nodo (rpm-ostree rebase)
4. Tras el reboot, el servicio `ovs-configuration.service` (`configure-ovs.sh`):
   - Si **no** existe `/etc/nmstate/openshift/applied`: crea `br-ex` con `ens5`
     como uplink usando la configuración por defecto de OVN-K
   - Si **existe** el marcador: salta la configuración (asume que ya fue aplicada)
5. OVN-Kubernetes añade patch ports entre `br-ex` y `br-int`
6. kubelet arranca y el nodo se registra en el cluster

### Workers

Los workers descargan su ignition completo del Machine Config Server (MCS)
en los masters. Siguen el mismo flujo, pero sin el paso de firstboot rebase
(ya arrancan con la imagen correcta), por lo que normalmente no tienen
el problema del marcador `applied`.

## Paso 6: Verificación post-instalación

### Verificar la configuración de red en todos los nodos

```bash
export KUBECONFIG=clusters/mi-cluster/4.18/eu-west-1/ocp/auth/kubeconfig

for NODE in $(oc get nodes -o name); do
  echo "=== $NODE ==="
  oc debug $NODE -- chroot /host bash -c '
    echo "Interfaces:"
    ip -o -4 addr show | grep -E "ens[56]|br-ex" | awk "{print \"  \"\$2\" \"\$4}"
    echo "Rutas default:"
    ip route show default | sed "s/^/  /"
    echo "OVS bridge:"
    ovs-vsctl list-ports br-ex 2>/dev/null | sed "s/^/  /"
  ' 2>/dev/null
  echo ""
done
```

Salida esperada por nodo:

```
Interfaces:
  br-ex 10.0.20.73/24
  ens6 10.0.30.9/24
Rutas default:
  default via 10.0.20.1 dev br-ex proto dhcp src 10.0.20.73 metric 48
  default via 10.0.30.1 dev ens6 proto dhcp src 10.0.30.9 metric 100
OVS bridge:
  ens5
  patch-br-ex_<hostname>-to-br-int
```

### Verificar que los operadores están sanos

```bash
oc get co | awk 'NR==1 || ($3!="True" || $5=="True")'
```

Si no devuelve filas (aparte de la cabecera), todo está correcto.

### Verificar que las interfaces persisten tras un reboot

```bash
# Reiniciar un nodo
oc debug node/<node-name> -- chroot /host systemctl reboot

# Esperar ~3 minutos y verificar
oc debug node/<node-name> -- chroot /host bash -c '
  ip route show default
  ovs-vsctl list-ports br-ex
'
```

Las interfaces `ens5` y `ens6` mantienen su asignación tras el reinicio.
En instancias AWS Nitro, el naming es determinista por slot PCI.

## Paso 7: Destruir el cluster

```bash
cd clusters/mi-cluster/4.18/eu-west-1/terraform

# Primero, eliminar el ELB creado por el operador de Ingress (si existe)
# ya que no está gestionado por Terraform
aws elb describe-load-balancers --query \
  "LoadBalancerDescriptions[?VPCId=='$(terraform output -raw vpc_id)'].LoadBalancerName" \
  --output text --profile demo --region eu-west-1 | \
  xargs -I{} aws elb delete-load-balancer --load-balancer-name {} \
  --profile demo --region eu-west-1

# Destruir la infraestructura
terraform destroy -auto-approve
```

## Resumen de ficheros modificados para dual-NIC

| Fichero | Cambio |
|---------|--------|
| `defaults/main.yml` | Variable `enable_dual_nic: false` |
| `variables.tf` | Variable `enable_dual_nic` |
| `terraform.tfvars.j2` | Paso de `enable_dual_nic` a Terraform |
| `network.tf` | Subredes secundarias `10.0.3x.0/24` (condicional) |
| `compute.tf` | ENIs secundarios en subredes secundarias (condicional) |
| `security.tf` | Reglas internas all-traffic entre master_sg y worker_sg |
| `nmstate-br-ex.yml.j2` | Configuración NMState: br-ex + ens6 |
| `99-nmstate-br-ex.yaml.j2` | MachineConfig que inyecta el NMState |
| `tasks/main.yml` | Tareas de renderizado e inyección (condicional) |

## Troubleshooting

### Los masters no se unen al cluster (kubelet inactive)

**Causa**: El fichero `/etc/nmstate/openshift/applied` existe pero la configuración
NMState no persistió tras el reboot de firstboot. El servicio `configure-ovs.sh`
lo ve y salta la configuración de `br-ex`.

**Solución** (SSH al master vía bootstrap):
```bash
sudo rm -f /etc/nmstate/openshift/applied
sudo systemctl restart ovs-configuration
```

### etcd no forma quorum (timeout entre masters)

**Causa**: Las reglas de security group que permiten todo el tráfico interno
entre `master_sg` y `worker_sg` no se aplicaron (state drift de Terraform).

**Verificación**:
```bash
aws ec2 describe-security-groups --group-ids <master-sg-id> \
  --query 'SecurityGroups[0].IpPermissions' --output json
```

Si solo aparecen reglas para puertos 22, 6443 y 22623, faltan las reglas internas.

**Solución**:
```bash
MASTER_SG=sg-xxx
WORKER_SG=sg-yyy

aws ec2 authorize-security-group-ingress --group-id $MASTER_SG --protocol -1 --source-group $MASTER_SG
aws ec2 authorize-security-group-ingress --group-id $MASTER_SG --protocol -1 --source-group $WORKER_SG
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol -1 --source-group $MASTER_SG
aws ec2 authorize-security-group-ingress --group-id $WORKER_SG --protocol -1 --source-group $WORKER_SG
```

### Workers atascados en "Ignition (fetch)" con Internal Server Error

**Causa**: El MCS en el bootstrap rechaza servir configuración a workers
(`refusing to serve bootstrap configuration to pool "worker"`). Los workers
deben obtener su configuración del MCS en los masters, pero el NLB sigue
enrutando al bootstrap.

**Solución**: Eliminar el bootstrap del target group del MCS (puerto 22623):
```bash
aws elbv2 deregister-targets --target-group-arn <mcs-tg-arn> \
  --targets Id=<bootstrap-ip>,Port=22623
```

### DNS *.apps no resuelve o devuelve connection refused

**Causa**: El registro `*.apps` apunta al NLB de Terraform, pero el ingress
operator crea su propio Classic ELB con `LoadBalancerService`.

**Solución**: Actualizar el registro DNS para apuntar al ELB del operador:
```bash
# Obtener el hostname del ELB del operador
oc get svc -n openshift-ingress router-default \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Actualizar Route53 con ese hostname
```
