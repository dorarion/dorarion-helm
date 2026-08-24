# Kubernetes + Helm + Dorarion

简易集群安装指南

> **目标：** 使用公开的 OCI Helm Chart 安装 Dorarion，连接外部 PostgreSQL
> 数据库，创建所需的 Kubernetes Secret 和第一个管理员账户，然后验证应用。

- 请在已配置为访问目标 Kubernetes 集群的终端中运行所有命令。
- 本指南使用 Docker Hub 上的 Helm Chart `kimc1992/dorarion` 版本 `0.0.1`。
- Dorarion 需要 Kubernetes 1.28 或更高版本以及 Helm 3。
- 此 Chart 不安装 PostgreSQL；请先准备数据库和备份。
- 另有 [PDF 版本](pdf/dorarion-kubernetes-helm-install-zh-cn.pdf)。

## 1. 检查 Kubernetes 和 Helm

在创建任何资源之前，确认 `kubectl` 指向正确的集群：

```bash
kubectl config current-context
kubectl cluster-info
kubectl version
helm version
```

如果 context 指向错误的集群，请不要继续。Kubernetes 服务端版本必须至少为 1.28。

## 2. 检查已发布的 Chart

直接从 Docker Hub 查看 Chart 信息：

```bash
helm show chart oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.1
```

预期的 Chart 元数据如下：

- Chart：`dorarion`
- Chart 版本：`0.0.1`
- 应用版本：`0.0.1`
- 应用镜像：`kimc1992/dorarion-core:0.0.1`

## 3. 准备 PostgreSQL

创建一个空的 PostgreSQL 数据库和 Dorarion 专用用户。该用户必须能够连接，
创建和修改表、索引及约束，并运行 Dorarion 数据库迁移。

请根据数据库服务商的要求在连接 URL 中加入 TLS 参数。典型 URL 格式如下：

```text
postgres://USER:PASSWORD@HOST:5432/DB_NAME
```

每次升级 Dorarion 前都要备份数据库，并在隔离环境中测试恢复。Helm Chart
不会管理或备份 PostgreSQL。

### 可选：运行简单的 PostgreSQL Pod

如果还没有 PostgreSQL，可以使用本仓库提供的单节点
[PostgreSQL 示例](../examples/postgresql.yaml)。它会创建一个 10 Gi 持久卷声明、
一个 PostgreSQL Deployment 和一个内部 ClusterIP Service。

> **此示例仅用于学习和小型测试安装。** 它不具备高可用性，不配置 TLS，
> 也不创建备份。生产环境请使用托管数据库或持续维护的 PostgreSQL Operator。

创建 namespace 和随机 PostgreSQL 密码：

```bash
kubectl create namespace dorarion --dry-run=client -o yaml | kubectl apply -f -

POSTGRES_PASSWORD="$(openssl rand -hex 32)"

kubectl -n dorarion create secret generic dorarion-postgresql \
  --from-literal=POSTGRES_DB=dorarion \
  --from-literal=POSTGRES_USER=dorarion \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
```

直接从 GitHub 部署 PostgreSQL，并等待其就绪：

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/dorarion/dorarion-helm/master/examples/postgresql.yaml

kubectl -n dorarion rollout status deployment/dorarion-postgresql \
  --timeout=5m
kubectl -n dorarion get pod,service,persistentvolumeclaim \
  -l app.kubernetes.io/name=dorarion-postgresql
```

如果创建 PostgreSQL 后打开了新终端，可在不显示密码的情况下将其恢复到变量：

```bash
POSTGRES_PASSWORD="$(kubectl -n dorarion get secret dorarion-postgresql \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"
```

使用此示例时，设置下一节所需的数据库 URL：

```bash
DATABASE_URL="postgres://dorarion:${POSTGRES_PASSWORD}@dorarion-postgresql.dorarion.svc.cluster.local:5432/dorarion"
```

## 4. 创建 namespace 和 Secret

数据库迁移作为 pre-install hook 运行，因此必须在 `helm install` 之前创建 Secret。

创建 namespace：

```bash
kubectl create namespace dorarion --dry-run=client -o yaml | kubectl apply -f -
```

生成应用密钥并创建 Kubernetes Secret。如果使用了 PostgreSQL 示例，
`DATABASE_URL` 已经设置。使用外部数据库时，请先替换并运行：

```bash
DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DB_NAME'
```

然后创建应用 Secret：

```bash
: "${DATABASE_URL:?Set DATABASE_URL before continuing}"
JWT_SECRET="$(openssl rand -hex 48)"
SECRET_ENCRYPTION_KEY="$(openssl rand -base64 32)"

kubectl -n dorarion create secret generic dorarion-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=SECRET_ENCRYPTION_KEY="$SECRET_ENCRYPTION_KEY"

unset DATABASE_URL POSTGRES_PASSWORD JWT_SECRET SECRET_ENCRYPTION_KEY
```

> **请妥善保护这些值。** 不要提交到 Git、写入 Helm values，或发布到聊天、
> 截图和工单中。请将 `SECRET_ENCRYPTION_KEY` 另外备份到密码管理器或密钥
> 管理系统。丢失此密钥后，直接存储在 Dorarion 中的集成凭据将无法恢复。

仅检查 Secret 的键名，不显示其值：

```bash
kubectl -n dorarion describe secret dorarion-secrets
```

必须包含 `DATABASE_URL`、`JWT_SECRET` 和 `SECRET_ENCRYPTION_KEY`。

## 5. 安装 Dorarion 并创建第一个管理员

选择用户和 CI Runner 实际可访问的 HTTPS 地址。仅在首次安装时启用管理员
bootstrap：

```bash
helm upgrade --install dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.1 \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.username=admin \
  --set bootstrapAdmin.email=admin@example.com \
  --wait \
  --timeout 15m
```

该地址必须可被用户、GitLab Runner 以及向 Dorarion 发送报告或 webhook 的
系统访问。生产环境应使用 HTTPS。

安装按以下顺序进行：

1. 运行阻塞式数据库 migration Job；
2. 创建 Dorarion Deployment 和 Service；
3. 等待应用就绪；
4. 运行首个管理员 bootstrap Job。

## 6. 保存管理员密码

bootstrap Job 只输出一次生成的密码。查看日志：

```bash
kubectl -n dorarion logs job/dorarion-bootstrap-admin
```

立即将密码保存到密码管理器。然后删除 Job，避免可读取 namespace 的用户从
日志中获取凭据：

```bash
kubectl -n dorarion delete job dorarion-bootstrap-admin
```

不要在此数据库上再次启用 `bootstrapAdmin`。如果登录账户已经存在，Dorarion
会拒绝再次 bootstrap，但升级时仍应明确禁用它。

## 7. 检查安装

检查 Helm Release 和 Kubernetes 工作负载：

```bash
helm status dorarion --namespace dorarion
kubectl -n dorarion get deployment,pods,service,jobs
kubectl -n dorarion rollout status deployment/dorarion
```

如果迁移失败，请检查保留的 Job 和日志：

```bash
kubectl -n dorarion get jobs
kubectl -n dorarion logs job/dorarion-migrate
```

常见原因包括 `DATABASE_URL` 错误、到 PostgreSQL 的网络访问被阻止、Secret
键缺失或数据库权限不足。

## 8. 在本机打开 Dorarion

无需 Ingress 即可进行快速检查，只需转发 ClusterIP Service：

```bash
kubectl -n dorarion port-forward service/dorarion 3000:80
```

保持该终端打开，然后访问：

<http://127.0.0.1:3000/login>

使用 `admin` 或 `admin@example.com` 以及第 6 步保存的密码登录。在另一个终端
检查 readiness：

```bash
curl --fail http://127.0.0.1:3000/health/ready
```

## 9. 配置 Ingress

必须已经部署 Ingress Controller 并配置 DNS。创建不含密钥的本地 values 文件
`values.local.yaml`：

```yaml
publicUrl: https://dorarion.example.com

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: dorarion.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dorarion-tls
      hosts:
        - dorarion.example.com
```

在不启用管理员 bootstrap 的情况下应用：

```bash
helm upgrade dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.1 \
  --namespace dorarion \
  --reuse-values \
  --set bootstrapAdmin.enabled=false \
  --values values.local.yaml \
  --wait \
  --timeout 15m
```

请根据 Ingress Controller 或证书管理器的方式配置 TLS Secret。不要将 TLS
私钥写入 values 文件。

## 10. 升级 Dorarion

升级前请执行以下操作：

1. 备份 PostgreSQL 并验证备份能够恢复；
2. 备份准确的 `SECRET_ENCRYPTION_KEY` 及其密钥引用；
3. 阅读 Release Notes 和迁移兼容性策略；
4. 选择新的不可变 Chart 和应用版本。

保持管理员 bootstrap 禁用并升级：

```bash
helm upgrade dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version NEW_CHART_VERSION \
  --namespace dorarion \
  --reuse-values \
  --set bootstrapAdmin.enabled=false \
  --wait \
  --timeout 15m
```

pre-upgrade migration 会向前修改数据库。回滚 Helm Release 不会撤销数据库迁移。

## 11. 卸载范围

删除 Helm Release：

```bash
helm uninstall dorarion --namespace dorarion
```

这不会删除外部 PostgreSQL 数据库或手动创建的 `dorarion-secrets` Secret。
如果以后可能重新安装或恢复，请保留两者。只有在确定要删除 namespace 中所有
剩余资源时，才删除该 namespace。

如果部署了 PostgreSQL 示例，其资源也独立于 Helm Release。使用常见 `Delete`
reclaim policy 的 StorageClass 时，删除持久卷声明也会删除数据库：

```bash
kubectl -n dorarion delete deployment,service dorarion-postgresql
kubectl -n dorarion delete persistentvolumeclaim dorarion-postgresql
kubectl -n dorarion delete secret dorarion-postgresql
```

除非确定要销毁示例数据库并已取得所需备份，否则不要执行持久卷声明删除命令。

## 快速回顾

- 已检查 Kubernetes context 和版本。
- 已检查 Docker Hub 上发布的 OCI Chart。
- 已准备外部 PostgreSQL 数据库和备份。
- 或者仅为测试部署了单节点 PostgreSQL 示例。
- 已创建 namespace 和必需的 Kubernetes Secret。
- 仅在首次安装时启用 bootstrap 并安装 Dorarion。
- 已保存生成的管理员密码并删除 bootstrap Job。
- 已验证 Deployment、readiness 和浏览器访问。
- 后续升级保持 bootstrap 禁用。

## 官方参考资料

- [Dorarion Helm 源代码](https://github.com/dorarion/dorarion-helm)
- [Docker Hub 上的 Dorarion Chart](https://hub.docker.com/repository/docker/kimc1992/dorarion/general)
- [安装 Helm](https://helm.sh/docs/intro/install/)
- [Helm OCI Registry](https://helm.sh/docs/topics/registries/)
- [安装 kubectl](https://kubernetes.io/docs/tasks/tools/)
