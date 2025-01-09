# Hyperledger Fabric 空域管理区块链网络

## 项目概述

此项目基于 Hyperledger Fabric 构建，旨在实现空域资源的可信管理，包括空域操作意图的分配与预留、使用率监控及违规行为的记录。主要特点包括：

- **网络架构**：由一个 UNSP 节点和 4 个航司节点组成，每个节点具有独立的 Peer 和 Orderer。
- **通信方式**：基于 TLS 安全通信，所有节点支持加密传输和身份验证。
- **共识机制**：采用 Raft 共识，UNSP 节点为初始 Leader。
- **隐私保护**：
---

## 网络架构

- **Orderer 节点**：
  - 1 个 UNSP Orderer：`orderer1.unsp.example.com`
  - 4 个航司 Orderer：分别由 `airline1` 至 `airline4` 负责。
- **Peer 节点**：
  - 每个组织包含 1 个 Peer 节点：`peer0.unsp.example.com`、`peer0.airline1.example.com` 等。

---

## 配置文件说明

- `crypto-config.yaml`：定义网络的组织结构及节点信息。
- `configtx.yaml`：配置通道策略和 Orderer 的共识机制。
- `docker-compose.yaml`：定义 Docker 容器的服务配置。
- `start-network.sh`：包含启动和管理网络的核心脚本。

---

## 网络启动指南

### 1. 环境准备

确保安装以下工具：
- Docker 和 Docker Compose
- Hyperledger Fabric 二进制文件（版本 `2.5.0`，工具命名为 `latest`）

### 2. 拉取 Fabric 镜像

```bash
docker pull hyperledger/fabric-peer:latest
docker pull hyperledger/fabric-orderer:latest
docker pull hyperledger/fabric-tools:latest
3. 启动网络
运行以下命令以启动网络：

bash
复制代码
chmod +x ./start-network.sh
./start-network.sh up
4. 安装链码
编辑 install-chaincode.sh 文件以指定链码路径，然后运行以下命令安装链码：

bash
复制代码
chmod +x ./install-chaincode.sh
./install-chaincode.sh
功能概述
创世区块：genesis.block 文件生成并初始化区块链网络。
通道配置：默认通道名称为 airspacechannel。
隐私查询：航司节点只能查询单个空域单位的状态，且不暴露具体占用方。
停止网络
要关闭并清理网络环境，请运行：

bash
复制代码
./start-network.sh down
