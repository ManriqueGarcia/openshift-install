# Configuración Dual-NIC para OpenShift UPI en AWS

## Descripción

Esta configuración despliega instancias EC2 con **dos interfaces de red (ENIs)** en **subredes diferentes**, cada una con su propio gateway:

| Interfaz | Función | Subred | Métrica | Descripción |
|----------|---------|--------|---------|-------------|
| `ens5` (primaria) | OVS Bridge `br-ex` | `10.0.2x.0/24` | 48 | Interfaz principal gestionada por OVN-Kubernetes |
| `ens6` (secundaria) | Ethernet independiente | `10.0.3x.0/24` | 101 | Interfaz secundaria con DHCP propio |

En instancias AWS Nitro (familia m5, c5, r5, etc.), los nombres de las interfaces son **deterministas** basados en el slot PCI del ENI:
- `device_index = 0` → `ens5`
- `device_index = 1` → `ens6`

Estos nombres **no cambian tras reinicios**, incluso con OVN-Kubernetes activo.

## Arquitectura de red

```
VPC 10.0.0.0/16
│
├── Subredes públicas (bootstrap)
│   └── 10.0.10-12.0/24
│
├── Subredes privadas primarias (ens5 → br-ex)
│   ├── 10.0.20.0/24 (AZ-a) ── gw 10.0.20.1
│   ├── 10.0.21.0/24 (AZ-b) ── gw 10.0.21.1
│   └── 10.0.22.0/24 (AZ-c) ── gw 10.0.22.1
│
└── Subredes privadas secundarias (ens6)
    ├── 10.0.30.0/24 (AZ-a) ── gw 10.0.30.1
    ├── 10.0.31.0/24 (AZ-b) ── gw 10.0.31.1
    └── 10.0.32.0/24 (AZ-c) ── gw 10.0.32.1
```

## Ficheros implicados

```
roles/ocp_upi_aws/
├── defaults/main.yml                          # enable_dual_nic: false
├── files/terraform/
│   ├── variables.tf                           # variable "enable_dual_nic"
│   ├── network.tf                             # subredes secundarias
│   ├── compute.tf                             # ENIs secundarios
│   └── security.tf                            # reglas internas entre SGs
├── templates/
│   ├── terraform.tfvars.j2                    # paso de variable a Terraform
│   ├── nmstate-br-ex.yml.j2                   # configuración NMState
│   └── 99-nmstate-br-ex.yaml.j2              # MachineConfig wrapper
└── tasks/main.yml                             # tareas de inyección
```

## 1. Activación

Para activar dual-NIC, pasar `enable_dual_nic=true` al ejecutar el playbook:

```bash
ansible-playbook playbook.yml \
  -e "cluster_name=demo-418" \
  -e "ocp_version=4.18" \
  -e "base_domain=example.com" \
  -e "aws_region=eu-west-1" \
  -e "aws_profile=demo" \
  -e "enable_dual_nic=true"
```

## 2. Cambios en Terraform

### 2.1 Variable de control (`variables.tf`)

```terraform
variable "enable_dual_nic" { default = false }
```

### 2.2 Subredes secundarias (`network.tf`)

Se crean 3 subredes privadas adicionales en un rango CIDR diferente (`10.0.3x.0/24`), una por AZ. Comparten las tablas de rutas privadas existentes (acceso a internet vía NAT Gateway):

```terraform
resource "aws_subnet" "secondary_private_subnets" {
  count              = var.enable_dual_nic ? 3 : 0
  vpc_id             = aws_vpc.ocp_vpc.id
  cidr_block         = "10.0.${30 + count.index}.0/24"
  availability_zone  = local.az_names[count.index]

  tags = {
    Name = "${var.cluster_name}-secondary-${local.az_names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table_association" "secondary_private_assoc" {
  count          = var.enable_dual_nic ? 3 : 0
  subnet_id      = aws_subnet.secondary_private_subnets[count.index].id
  route_table_id = aws_route_table.private_rts[count.index].id
}
```

### 2.3 ENIs secundarios (`compute.tf`)

Se crean ENIs independientes en las subredes secundarias y se asocian a las instancias con `device_index = 1` (que corresponde a `ens6` en instancias Nitro):

```terraform
resource "aws_network_interface" "master_secondary" {
  count           = var.enable_dual_nic ? 3 : 0
  subnet_id       = aws_subnet.secondary_private_subnets[count.index].id
  security_groups = [aws_security_group.master_sg.id]

  tags = {
    Name = "${var.cluster_name}-master-${count.index}-ens6"
  }
}

resource "aws_network_interface_attachment" "master_secondary" {
  count                = var.enable_dual_nic ? 3 : 0
  instance_id          = aws_instance.master[count.index].id
  network_interface_id = aws_network_interface.master_secondary[count.index].id
  device_index         = 1
}
```

Lo mismo para los workers usando `aws_security_group.worker_sg.id`.

### 2.4 Security Groups (`security.tf`)

Es **imprescindible** que existan reglas de comunicación interna bidireccional entre `master_sg` y `worker_sg` permitiendo todo el tráfico (protocolo `-1`):

```terraform
resource "aws_security_group_rule" "internal_master_to_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.master_sg.id
  security_group_id        = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "internal_worker_to_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker_sg.id
  security_group_id        = aws_security_group.master_sg.id
}

resource "aws_security_group_rule" "internal_master_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.master_sg.id
  security_group_id        = aws_security_group.worker_sg.id
}

resource "aws_security_group_rule" "internal_worker_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker_sg.id
  security_group_id        = aws_security_group.worker_sg.id
}
```

> **Nota**: Sin estas reglas, etcd no puede formar quorum, kube-apiserver no arranca y el cluster queda inoperativo.

## 3. Configuración NMState

### 3.1 Fichero NMState (`nmstate-br-ex.yml.j2`)

Define la topología de red dentro del nodo RHCOS. Se inyecta en `/etc/nmstate/openshift/cluster.yml` y el servicio `configure-ovs.sh` lo aplica durante el arranque:

```yaml
interfaces:
  # OVS Bridge usando ens5 como puerto
  - name: br-ex
    type: ovs-bridge
    state: up
    bridge:
      options:
        stp:
          enabled: false
      port:
        - name: ens5

  # ens5 como puerto del bridge (sin IP propia)
  - name: ens5
    type: ethernet
    state: up
    ipv4:
      enabled: false
    ipv6:
      enabled: false

  # br-ex como interfaz OVS interna (lleva la IP y el gateway)
  - name: br-ex
    type: ovs-interface
    state: up
    ipv4:
      enabled: true
      dhcp: true
      auto-gateway: true
      auto-routes: true
      auto-route-table-id: 0
      auto-route-metric: 48       # Prioridad ALTA (métrica baja gana)
    ipv6:
      enabled: true
      dhcp: true
      autoconf: true
      auto-gateway: true
      auto-routes: true
      auto-route-table-id: 0
      auto-route-metric: 48

  # ens6 como interfaz secundaria independiente
  - name: ens6
    type: ethernet
    state: up
    ipv4:
      enabled: true
      dhcp: true
      auto-gateway: true
      auto-routes: true
      auto-route-table-id: 0
      auto-route-metric: 101      # Prioridad BAJA (métrica alta pierde)
    ipv6:
      enabled: true
      dhcp: true
      autoconf: true
      auto-gateway: true
      auto-routes: true
      auto-route-table-id: 0
      auto-route-metric: 101
```

### 3.2 MachineConfig wrapper (`99-nmstate-br-ex.yaml.j2`)

Inyecta el fichero NMState como un `MachineConfig` para ambos roles (`master` y `worker`). El contenido se codifica en base64:

```yaml
{% for role in ['master', 'worker'] %}
---
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: {{ role }}
  name: 99-{{ role }}-nmstate-br-ex
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/nmstate/openshift/cluster.yml
          mode: 0644
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,{{ nmstate_config_b64 }}
{% endfor %}
```

## 4. Integración en el playbook

Las tareas se ejecutan **antes** de `openshift-install create ignition-configs`, condicionadas a `enable_dual_nic`:

```yaml
- name: Generar fichero NMState para OVS bridge
  ansible.builtin.template:
    src: nmstate-br-ex.yml.j2
    dest: "{{ install_dir }}/ocp/nmstate-br-ex.yml"
  when: enable_dual_nic | default(false) | bool

- name: Codificar NMState config en base64
  ansible.builtin.slurp:
    src: "{{ install_dir }}/ocp/nmstate-br-ex.yml"
  register: nmstate_config_raw
  when: enable_dual_nic | default(false) | bool

- name: Registrar NMState base64
  ansible.builtin.set_fact:
    nmstate_config_b64: "{{ nmstate_config_raw.content }}"
  when: enable_dual_nic | default(false) | bool

- name: Inyectar MachineConfig NMState para OVS bridge
  ansible.builtin.template:
    src: 99-nmstate-br-ex.yaml.j2
    dest: "{{ install_dir }}/ocp/openshift/99-nmstate-br-ex.yaml"
  when: enable_dual_nic | default(false) | bool
```

El orden en el playbook es:

1. `openshift-install create manifests`
2. **Inyectar MachineConfig NMState** (este paso)
3. `openshift-install create ignition-configs`
4. `terraform apply`

## 5. Resultado esperado

Tras la instalación y en cada reinicio, cada nodo tendrá:

```
$ ip route show default
default via 10.0.20.1 dev br-ex proto dhcp src 10.0.20.73 metric 48
default via 10.0.30.1 dev ens6 proto dhcp src 10.0.30.9 metric 100

$ sudo ovs-vsctl list-ports br-ex
ens5
patch-br-ex_<hostname>-to-br-int
```

- `br-ex` (via `ens5`): ruta principal con métrica 48, gestionada por OVN-Kubernetes
- `ens6`: ruta secundaria con métrica 100-101, independiente en su propia subred

## 6. Verificación post-instalación

```bash
# Comprobar interfaces y rutas en un nodo
oc debug node/<node-name> -- chroot /host bash -c '
  echo "=== Interfaces ==="
  ip -o -4 addr show | grep -E "ens[56]|br-ex"
  echo "=== Rutas ==="
  ip route show default
  echo "=== OVS ==="
  ovs-vsctl list-ports br-ex
'
```

## 7. Notas importantes

### Naming determinista en AWS Nitro

Las instancias de la familia Nitro (m5, c5, r5, i3, etc.) asignan nombres de interfaz basados en el slot PCI del ENI, no por orden de detección. `device_index=0` siempre será `ens5` y `device_index=1` siempre será `ens6`, independientemente de reinicios.

### Subredes diferentes obligatorias

Cada ENI **debe** estar en una subred diferente para que cada interfaz tenga su propio gateway. Si ambos ENIs están en la misma subred, comparten gateway y la prueba de segmentación de red no es válida.

### Security Groups

Las reglas internas de comunicación entre `master_sg` y `worker_sg` (all traffic, protocol `-1`) son **críticas**. Sin ellas, etcd no forma quorum y el cluster no arranca. Verificar siempre que estas reglas existen en AWS después del `terraform apply`.
