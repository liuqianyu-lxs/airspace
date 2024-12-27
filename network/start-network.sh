#!/bin/bash

# 输出颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 设置环境变量
export FABRIC_CFG_PATH=${PWD}
export CHANNEL_NAME="airspacechannel"

# 输出当前环境变量
echo "FABRIC_CFG_PATH is set to: ${FABRIC_CFG_PATH}"
echo "CHANNEL_NAME is set to: ${CHANNEL_NAME}"

# 错误处理函数
function errorln() {
    echo -e "${RED}错误: $1${NC}"
    exit 1
}

function successln() {
    echo -e "${GREEN}成功: $1${NC}"
}

# 清理环境
function cleanup() {
    echo -e "${GREEN}正在清理环境...${NC}"
    docker-compose down
    docker rm -f $(docker ps -aq)
    docker volume prune -f
    rm -rf crypto-config/*
    rm -rf channel-artifacts/*
}

# 创建必要目录
function createDirectories() {
    echo -e "${GREEN}创建必要的目录...${NC}"
    mkdir -p channel-artifacts
    mkdir -p crypto-config
}

# 合并所有 Orderer CA 文件
function mergeOrdererCACerts() {
    echo -e "${GREEN}合并所有 Orderer 的 CA 证书...${NC}"
    cat \
        ./crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer.unsp.example.com/tls/ca.crt \
        ./crypto-config/ordererOrganizations/airline1.example.com/orderers/orderer.airline1.example.com/tls/ca.crt \
        ./crypto-config/ordererOrganizations/airline2.example.com/orderers/orderer.airline2.example.com/tls/ca.crt \
        ./crypto-config/ordererOrganizations/airline3.example.com/orderers/orderer.airline3.example.com/tls/ca.crt \
        ./crypto-config/ordererOrganizations/airline4.example.com/orderers/orderer.airline4.example.com/tls/ca.crt \
        > ./crypto-config/ordererOrganizations/all-orderer-tlscacerts.pem

    if [ $? -ne 0 ]; then
        errorln "合并 Orderer CA 文件失败！"
    fi
    echo -e "${GREEN}合并完成，路径: ./crypto-config/ordererOrganizations/all-orderer-tlscacerts.pem${NC}"
}

# 生成证书
function generateCertificates() {
    echo -e "${GREEN}生成证书材料...${NC}"
    cryptogen generate --config=./crypto-config.yaml
    if [ $? -ne 0 ]; then
        errorln "证书生成失败"
    fi
    mergeOrdererCACerts
    	
    # 验证TLS证书是否生成
    if [ ! -f "crypto-config/peerOrganizations/unsp.example.com/peers/peer0.unsp.example.com/tls/server.crt" ]; then
        errorln "TLS证书未找到"
    fi
}

# 生成创世区块和通道配置
function generateGenesisBlock() {
    echo -e "${GREEN}生成创世区块和通道配置...${NC}"
    configtxgen -profile OrdererGenesis -channelID airspacechannel -outputBlock ./channel-artifacts/genesis.block
    if [ $? -ne 0 ]; then
        errorln "创世区块生成失败"
    fi

    configtxgen -profile airspacechannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
    if [ $? -ne 0 ]; then
        errorln "通道配置生成失败"
    fi

    # 生成锚节点更新文件
    echo -e "${GREEN}生成锚节点更新文件...${NC}"
    configtxgen -profile airspacechannel -outputAnchorPeersUpdate ./channel-artifacts/UNSPMSPanchors.tx -channelID $CHANNEL_NAME -asOrg UNSPMSP
    configtxgen -profile airspacechannel -outputAnchorPeersUpdate ./channel-artifacts/Airline1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Airline1MSP
    configtxgen -profile airspacechannel -outputAnchorPeersUpdate ./channel-artifacts/Airline2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Airline2MSP
    configtxgen -profile airspacechannel -outputAnchorPeersUpdate ./channel-artifacts/Airline3MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Airline3MSP
    configtxgen -profile airspacechannel -outputAnchorPeersUpdate ./channel-artifacts/Airline4MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Airline4MSP
}

# 启动网络
function startNetwork() {
    echo -e "${GREEN}启动网络...${NC}"
    
    # 检查必要的镜像
    echo "检查必要的 Docker 镜像..."
    local REQUIRED_IMAGES=(
        "hyperledger/fabric-orderer:latest"
        "hyperledger/fabric-peer:latest"
        "hyperledger/fabric-tools:latest"
    )
    
    for IMG in "${REQUIRED_IMAGES[@]}"; do
        if ! docker images | grep -q ${IMG%:*}; then
            echo -e "${BLUE}拉取镜像 ${IMG}...${NC}"
            docker pull ${IMG} || errorln "无法拉取镜像 ${IMG}"
        fi
    done
    
    # 分步启动容器并检查
    echo "启动 Orderer 节点..."
    docker-compose up -d \
        orderer.unsp.example.com\
        orderer.airline1.example.com\
        orderer.airline2.example.com\
        orderer.airline3.example.com\
        orderer.airline4.example.com\
        
    if [ $? -ne 0 ]; then
        errorln "Orderer 节点启动失败"
    fi

    echo "等待 Orderer 节点完全启动..."
    sleep 5
    
    # 检查 orderer 容器是否正在运行
    if ! docker ps | grep -q "orderer.unsp.example.com"; then
        errorln "Orderer 容器未正常运行"
    fi
    
    echo "启动 Peer 节点..."
    docker-compose up -d \
        peer0.unsp.example.com \
        peer0.airline1.example.com \
        peer0.airline2.example.com \
        peer0.airline3.example.com \
        peer0.airline4.example.com
    
    if [ $? -ne 0 ]; then
        errorln "Peer 节点启动失败"
    fi
    
    echo "等待 Peer 节点启动..."
    sleep 5
    
    echo "启动 CLI 容器..."
    docker-compose up -d cli
    if [ $? -ne 0 ]; then
        errorln "CLI 容器启动失败"
    fi
    
    echo "等待 CLI 容器启动..."
    sleep 5
    
    # 验证所有容器都在运行
    local REQUIRED_CONTAINERS=(
        "orderer.unsp.example.com"
        "peer0.unsp.example.com"
        "peer0.airline1.example.com"
        "peer0.airline2.example.com"
        "peer0.airline3.example.com"
        "peer0.airline4.example.com"
        "cli"
    )
    
    for CONTAINER in "${REQUIRED_CONTAINERS[@]}"; do
        if ! docker ps | grep -q ${CONTAINER}; then
            errorln "容器 ${CONTAINER} 未正常运行"
        fi
    done
    
    successln "网络启动完成！"
}

ORDERER_LIST=(
    "orderer.unsp.example.com:7050"
    "orderer.airline1.example.com:8050"
    "orderer.airline2.example.com:9050"
    "orderer.airline3.example.com:10050"
    "orderer.airline4.example.com:11050"
)

# 创建通道
function createChannel() {
    echo -e "${GREEN}开始创建通道...${NC}"
    
    # 第一步：生成通道配置区块
    echo "生成通道交易文件..."
    configtxgen -profile airspacechannel \
        -channelID ${CHANNEL_NAME} \
        -outputBlock ./channel-artifacts/${CHANNEL_NAME}.block
    if [ $? -ne 0 ]; then
        errorln "通道交易文件生成失败"
        return 1
    fi

    # 第二步：使用Channel Participation API让所有orderer加入通道
    echo "让所有orderer节点加入通道..."
    
    local ORDERER_ORGS=("unsp" "airline1" "airline2" "airline3" "airline4")
    local ORDERER_PORTS=("7053" "8053" "9053" "10053" "11053")
    
    # 设置环境变量增加请求大小限制
    export ORDERER_GENERAL_MAXREQUESTSIZE=100000000
    export ORDERER_GENERAL_MAXMESSAGESIZE=100000000

    for i in "${!ORDERER_ORGS[@]}"; do
        ORG=${ORDERER_ORGS[$i]}
        PORT=${ORDERER_PORTS[$i]}
        
        echo "正在让 orderer.${ORG}.example.com 加入通道..."
        
        # 设置重试机制
        MAX_RETRY=1
        DELAY=5
        COUNTER=1
        
        while [ $COUNTER -le $MAX_RETRY ]; do
            echo "尝试 $COUNTER of $MAX_RETRY"
            
            # 首先检查证书文件是否存在
            docker exec cli ls "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/ca.crt" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                errorln "证书文件不存在，请检查路径"
                return 1
            fi

            # 尝试加入通道
            docker exec \
                -e ORDERER_GENERAL_MAXREQUESTSIZE=100000000 \
                -e ORDERER_GENERAL_MAXMESSAGESIZE=100000000 \
                cli osnadmin channel join \
                --channelID ${CHANNEL_NAME} \
                --config-block ./channel-artifacts/${CHANNEL_NAME}.block \
                -o orderer.${ORG}.example.com:${PORT} \
                --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/ca.crt" \
                --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.crt" \
                --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.key"

            if [ $? -eq 0 ]; then
                break
            fi           
           # 如果失败，检查是否已经加入通道
            CHANNEL_LIST=$(docker exec \
                cli osnadmin channel list \
                -o orderer.${ORG}.example.com:${PORT} \
                --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/ca.crt" \
                --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.crt" \
                --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.key")

            if [[ $CHANNEL_LIST == *"${CHANNEL_NAME}"* ]]; then
                echo "orderer.${ORG}.example.com 已经加入通道"
                break
            fi

            if [ $COUNTER -eq $MAX_RETRY ]; then
                errorln "orderer.${ORG}.example.com 加入通道失败"
                return 1
            fi

            echo "等待 $DELAY 秒后重试..."
            sleep $DELAY
            let COUNTER=COUNTER+1
        done
        
        # 增加等待时间确保orderer节点完全就绪
        sleep 5
        
        echo "验证 orderer.${ORG}.example.com 的通道状态..."
        docker exec \
            cli osnadmin channel list \
            -o orderer.${ORG}.example.com:${PORT} \
            --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/ca.crt" \
            --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.crt" \
            --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer.${ORG}.example.com/tls/server.key"
    done

    successln "通道创建成功"
    return 0
}

# 节点加入通道
function joinChannel() {
    PEER_NAME=$1
    PEER_PORT=$2
    MSP_ID=$3
    
    # 从PEER_NAME中提取组织名
    ORG_NAME=${PEER_NAME#peer0.}
    ORG_NAME=${ORG_NAME%.example.com}
    echo -e "${GREEN}正在将 ${PEER_NAME} 加入通道...${NC}"
    
    # 确保使用正确的证书路径
    CORE_PEER_TLS_ROOTCERT_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}.example.com/peers/${PEER_NAME}/tls/ca.crt"
    CORE_PEER_MSPCONFIGPATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}.example.com/users/Admin@${ORG_NAME}.example.com/msp"
    CORE_PEER_TLS_CERT_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}.example.com/peers/${PEER_NAME}/tls/server.crt"
    CORE_PEER_TLS_KEY_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}.example.com/peers/${PEER_NAME}/tls/server.key"
    
    # 添加重试机制
    MAX_RETRY=1
    DELAY=1
    COUNTER=1
    
    while [ $COUNTER -le $MAX_RETRY ]; do
        echo "尝试 $COUNTER of $MAX_RETRY"
        
        # 验证证书文件是否存在
        docker exec cli ls -l ${CORE_PEER_TLS_ROOTCERT_FILE}
        if [ $? -ne 0 ]; then
            echo "警告: TLS证书文件不存在: ${CORE_PEER_TLS_ROOTCERT_FILE}"
        fi
        
        docker exec \
            -e CORE_PEER_TLS_ENABLED=true \
            -e CORE_PEER_ADDRESS="${PEER_NAME}:${PEER_PORT}" \
            -e CORE_PEER_LOCALMSPID="${MSP_ID}" \
            -e CORE_PEER_TLS_ROOTCERT_FILE="${CORE_PEER_TLS_ROOTCERT_FILE}" \
            -e CORE_PEER_MSPCONFIGPATH="${CORE_PEER_MSPCONFIGPATH}" \
            -e CORE_PEER_TLS_CERT_FILE="${CORE_PEER_TLS_CERT_FILE}" \
            -e CORE_PEER_TLS_KEY_FILE="${CORE_PEER_TLS_KEY_FILE}" \
            -w /opt/gopath/src/github.com/hyperledger/fabric/peer \
            cli peer channel join \
                -b ./channel-artifacts/${CHANNEL_NAME}.block\
                --tls=ture \
                --cafile "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/all-orderer-tlscacerts.pem"
                
        if [ $? -eq 0 ]; then
            successln "${PEER_NAME} 成功加入通道"
            return 0
        fi

        echo "等待 $DELAY 秒后重试..."
        sleep $DELAY
        let COUNTER=COUNTER+1
    done

    errorln "${PEER_NAME} 加入通道失败"
    return 1
}

# 更新锚节点
function updateAnchorPeers() {
    PEER_NAME=$1
    MSP_ID=$2
    ANCHOR_TX_FILE=$3

    echo -e "${GREEN}更新 ${PEER_NAME} 的锚节点配置...${NC}"
    docker exec \
        -e CORE_PEER_LOCALMSPID="${MSP_ID}" \
        -e CORE_PEER_ADDRESS="${PEER_NAME}:7051" \
        -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${PEER_NAME#peer0.}/peers/${PEER_NAME}/tls/ca.crt \
        cli peer channel update \
            -o orderer.unsp.example.com:7050 \
            -c ${CHANNEL_NAME} \
            -f ./channel-artifacts/${ANCHOR_TX_FILE} \
            --tls \
            --cafile "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/all-orderer-tlscacerts.pem"

    if [ $? -ne 0 ]; then
        errorln "${PEER_NAME} 锚节点更新失败"
    else
        successln "${PEER_NAME} 锚节点更新成功"
    fi
}

# 网络部署函数
function networkUp() {
    cleanup
    createDirectories
    generateCertificates
    generateGenesisBlock
    startNetwork
    createChannel

    # 所有节点加入通道
    joinChannel peer0.unsp.example.com 7051 UNSPMSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/unsp.example.com/peers/peer0.unsp.example.com/tls/ca.crt
    joinChannel peer0.airline1.example.com 8051 Airline1MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline1.example.com/peers/peer0.airline1.example.com/tls/ca.crt
    joinChannel peer0.airline2.example.com 9051 Airline2MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline2.example.com/peers/peer0.airline2.example.com/tls/ca.crt
    joinChannel peer0.airline3.example.com 10051 Airline3MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline3.example.com/peers/peer0.airline3.example.com/tls/ca.crt
    joinChannel peer0.airline4.example.com 11051 Airline4MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline4.example.com/peers/peer0.airline4.example.com/tls/ca.crt

    # 更新所有组织的锚节点
    updateAnchorPeers peer0.unsp.example.com UNSPMSP UNSPMSPanchors.tx
    updateAnchorPeers peer0.airline1.example.com Airline1MSP Airline1MSPanchors.tx
    updateAnchorPeers peer0.airline2.example.com Airline2MSP Airline2MSPanchors.tx
    updateAnchorPeers peer0.airline3.example.com Airline3MSP Airline3MSPanchors.tx
    updateAnchorPeers peer0.airline4.example.com Airline4MSP Airline4MSPanchors.tx

    successln "网络部署完成！"
}

# 脚本入口
if [ "$1" = "up" ]; then
    networkUp
elif [ "$1" = "down" ]; then
    cleanup
else
    echo "用法: $0 [up|down]"
    exit 1
fi