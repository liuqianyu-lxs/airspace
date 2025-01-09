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
        ./crypto-config/ordererOrganizations/unsp.example.com/msp/tlscacerts/tlsca.unsp.example.com-cert.pem \
        ./crypto-config/ordererOrganizations/airline1.example.com/msp/tlscacerts/tlsca.airline1.example.com-cert.pem \
        ./crypto-config/ordererOrganizations/airline2.example.com/msp/tlscacerts/tlsca.airline2.example.com-cert.pem \
        ./crypto-config/ordererOrganizations/airline3.example.com/msp/tlscacerts/tlsca.airline3.example.com-cert.pem \
        ./crypto-config/ordererOrganizations/airline4.example.com/msp/tlscacerts/tlsca.airline4.example.com-cert.pem \
        ./crypto-config/peerOrganizations/unsp.example.com/msp/tlscacerts/tlsca.unsp.example.com-cert.pem \
        ./crypto-config/peerOrganizations/airline1.example.com/msp/tlscacerts/tlsca.airline1.example.com-cert.pem \
        ./crypto-config/peerOrganizations/airline2.example.com/msp/tlscacerts/tlsca.airline2.example.com-cert.pem \
        ./crypto-config/peerOrganizations/airline3.example.com/msp/tlscacerts/tlsca.airline3.example.com-cert.pem \
        ./crypto-config/peerOrganizations/airline4.example.com/msp/tlscacerts/tlsca.airline4.example.com-cert.pem \
        >> ./crypto-config/all-orderer-tlscacerts.pem

    if [ $? -ne 0 ]; then
        errorln "合并 Orderer CA 文件失败！"
    fi
    echo -e "${GREEN}合并完成，路径: ./crypto-config/all-orderer-tlscacerts.pem${NC}"
}



# 生成证书
function generateCertificates() {
    echo -e "${GREEN}生成证书材料...${NC}"
    cryptogen generate --config=./crypto-config.yaml
    if [ $? -ne 0 ]; then
        errorln "证书生成失败"
    fi
    mergeOrdererCACerts
    verifyCertificates
    	
    # 验证TLS证书是否生成
    if [ ! -f "crypto-config/peerOrganizations/unsp.example.com/peers/peer0.unsp.example.com/tls/server.crt" ]; then
        errorln "TLS证书未找到"
    fi
}
function verifyCertificates() {
    i=1
    for org in unsp airline1 airline2 airline3 airline4; do
        echo "验证 ${org} 的证书..."
        
        # 定义证书路径
        CERT_PATH="./crypto-config/ordererOrganizations/${org}.example.com/orderers/orderer${i}.${org}.example.com/tls"
        
        # 检查文件是否存在
        if [ ! -f "${CERT_PATH}/server.key" ] || [ ! -f "${CERT_PATH}/server.crt" ]; then
            echo "错误: ${org} 的证书文件不存在"
            continue
        fi

        # 检查证书格式
        echo "检查证书格式..."
        openssl x509 -in "${CERT_PATH}/server.crt" -text -noout | grep "Public Key Algorithm"
        
        # 获取证书模数
        CERT_MD=$(openssl x509 -in "${CERT_PATH}/server.crt" -modulus -noout)
        
        # 尝试获取私钥模数（区分不同类型的私钥）
        if openssl rsa -in "${CERT_PATH}/server.key" -noout 2>/dev/null; then
            KEY_MD=$(openssl rsa -in "${CERT_PATH}/server.key" -modulus -noout)
        else
            # 如果不是RSA密钥，尝试EC密钥
            KEY_MD=$(openssl ec -in "${CERT_PATH}/server.key" -modulus -noout 2>/dev/null)
        fi
        
        # 比较模数
        if [ "$CERT_MD" = "$KEY_MD" ]; then
            echo "${org} 的证书和私钥匹配"
        else
            echo "${org} 的证书和私钥不匹配"
        fi
        
        i=$((i+1))
    done
}

# 生成创世区块和通道配置
function generateGenesisBlock() {
    echo -e "${GREEN}生成创世区块和通道配置...${NC}"
    configtxgen -profile OrdererGenesis -channelID $CHANNEL_NAME -outputBlock ./channel-artifacts/genesis.block
    if [ $? -ne 0 ]; then
        errorln "创世区块生成失败"
    fi

    configtxgen -profile airspacechannel -outputBlock ./channel-artifacts/channel.block -channelID $CHANNEL_NAME
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

CLI_CONTAINERS=(
    "cli-unsp"
    "cli-airline1"
    "cli-airline2"
    "cli-airline3"
    "cli-airline4"
)

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
        orderer1.unsp.example.com\
        orderer2.airline1.example.com\
        orderer3.airline2.example.com\
        orderer4.airline3.example.com\
        orderer5.airline4.example.com\
        
    if [ $? -ne 0 ]; then
        errorln "Orderer 节点启动失败"
    fi

    echo "等待 Orderer 节点完全启动..."
    sleep 5
    
    # 检查 orderer 容器是否正在运行
    if ! docker ps | grep -q "orderer1.unsp.example.com"; then
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
    docker-compose up -d \
        cli-unsp \
        cli-airline1 \
        cli-airline2 \
        cli-airline3 \
        cli-airline4

    if [ $? -ne 0 ]; then
        errorln "CLI 容器启动失败"
    fi
    
    echo "等待 CLI 容器启动..."
    sleep 5
    
    # 验证所有容器都在运行
    local REQUIRED_CONTAINERS=(
        "orderer1.unsp.example.com"
        "peer0.unsp.example.com"
        "peer0.airline1.example.com"
        "peer0.airline2.example.com"
        "peer0.airline3.example.com"
        "peer0.airline4.example.com"
        "${CLI_CONTAINERS[@]}"
    )
    
    for CONTAINER in "${REQUIRED_CONTAINERS[@]}"; do
        if ! docker ps | grep -q ${CONTAINER}; then
            errorln "容器 ${CONTAINER} 未正常运行"
        fi
    done
    
    successln "网络启动完成！"
}

ORDERER_LIST=(
    "orderer1.unsp.example.com:7050"
    "orderer2.airline1.example.com:8050"
    "orderer3.airline2.example.com:9050"
    "orderer4.airline3.example.com:10050"
    "orderer5.airline4.example.com:11050"
)

function createChannel() {
    echo -e "${GREEN}开始创建通道...${NC}"

    # 第一步：生成通道交易文件
    echo "生成通道交易文件..."
    configtxgen -profile airspacechannel \
        -channelID ${CHANNEL_NAME} \
        -outputBlock ./channel-artifacts/${CHANNEL_NAME}.block
    if [ $? -ne 0 ]; then
        errorln "通道交易文件生成失败"
        return 1
    fi

    # 第二步：使用选定的 Orderer 节点创建通道
    echo "使用 orderer1.unsp.example.com 创建通道..."
    docker exec \
        -e ORDERER_GENERAL_MAXREQUESTSIZE=100000000 \
        -e ORDERER_GENERAL_MAXMESSAGESIZE=100000000 \
        cli-unsp osnadmin channel join \
        --channelID ${CHANNEL_NAME} \
        --config-block ./channel-artifacts/${CHANNEL_NAME}.block\
        -o orderer1.unsp.example.com:7053 \
        --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/ca.crt" \
        --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/server.crt" \
        --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/server.key"

    if [ $? -ne 0 ]; then
        errorln "通道创建失败"
        return 1
    fi

               # 如果失败，检查是否已经加入通道
    CHANNEL_LIST=$(docker exec \
        cli-unsp osnadmin channel list \
        -o orderer1.unsp.example.com:7053\
        --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/ca.crt" \
        --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/server.crt" \
        --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/unsp.example.com/orderers/orderer1.unsp.example.com/tls/server.key")

    if [[ $CHANNEL_LIST == *"${CHANNEL_NAME}"* ]]; then
        echo "orderer1.unsp.example.com 已经加入通道"
        return 0
    fi

    if [ $COUNTER -eq $MAX_RETRY ]; then
        errorln "orderer1.unsp.example.com 加入通道失败"
        return 1
    fi


    successln "通道创建成功"
    return 0
}
#orderer节点加入通道
function joinOrderersToChannel() {
    echo -e "${GREEN}让所有 Orderer 节点加入通道...${NC}"

    local ORDERER_ORGS=("airline1" "airline2" "airline3" "airline4")
    local ORDERER_PORTS=("8053" "9053" "10053" "11053")

    for i in "${!ORDERER_ORGS[@]}"; do
        ORG=${ORDERER_ORGS[$i]}
        PORT=${ORDERER_PORTS[$i]}
        # 使用对应的CLI容器
        CLI_CONTAINER="cli-${ORG}"

        echo "正在让 orderer$((i+2)).${ORG} 加入通道..."
        docker exec \
            -e ORDERER_GENERAL_MAXREQUESTSIZE=100000000 \
            -e ORDERER_GENERAL_MAXMESSAGESIZE=100000000 \
            ${CLI_CONTAINER} osnadmin channel join \
            --channelID ${CHANNEL_NAME} \
            --config-block ./channel-artifacts/${CHANNEL_NAME}.block \
            -o orderer$((i+2)).${ORG}.example.com:${PORT} \
            --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer$((i+2)).${ORG}.example.com/tls/ca.crt" \
            --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer$((i+2)).${ORG}.example.com/tls/server.crt" \
            --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${ORG}.example.com/orderers/orderer$((i+2)).${ORG}.example.com/tls/server.key"

        if [ $? -ne 0 ]; then
            errorln "orderer$((i+2)).${ORG} 加入通道失败"
            return 1
        fi
    done

    successln "所有 Orderer 节点已成功加入通道"
}


# 节点加入通道
function joinChannel() {
    PEER_NAME=$1
    PEER_PORT=$2
    MSP_ID=$3
    
    # 从PEER_NAME中提取组织名
    ORG_NAME=${PEER_NAME#peer0.}
    CLI_CONTAINER="cli-${ORG_NAME%.example.com}"
    echo -e "${GREEN}正在使用 ${CLI_CONTAINER}将 ${PEER_NAME} 加入通道...${NC}"
    
    # 确保使用正确的证书路径
    CORE_PEER_TLS_ROOTCERT_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}/tls/ca.crt"
    CORE_PEER_MSPCONFIGPATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}/users/Admin@${ORG_NAME}/msp"
    CORE_PEER_TLS_CERT_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}/tls/server.crt"
    CORE_PEER_TLS_KEY_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}/tls/server.key"
    
    # 添加重试机制
    MAX_RETRY=1
    DELAY=1
    COUNTER=1
    
    while [ $COUNTER -le $MAX_RETRY ]; do
        echo "尝试 $COUNTER of $MAX_RETRY"
        
        # 验证证书文件是否存在
        docker exec ${CLI_CONTAINER} ls -l ${CORE_PEER_TLS_ROOTCERT_FILE}
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
            ${CLI_CONTAINER}  peer channel join \
                -b ./channel-artifacts/${CHANNEL_NAME}.block\
                --tls=true \
                --cafile "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/all-orderer-tlscacerts.pem"
                
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
    PEER_PORT=$4

    ORG_NAME=${PEER_NAME#peer0.}
    ORG_NAME=${ORG_NAME%.example.com}

    CLI_CONTAINER="cli-${ORG_NAME}"

    # 检查锚节点配置文件是否存在
    if [ ! -f "./channel-artifacts/${ANCHOR_TX_FILE}" ]; then
        echo "${RED}错误: 锚节点配置文件 ${ANCHOR_TX_FILE} 不存在${NC}"
        return 1
    fi

    # 检查节点是否已加入通道
    docker exec \
        -e CORE_PEER_LOCALMSPID="${MSP_ID}" \
        -e CORE_PEER_ADDRESS="${PEER_NAME}:${PEER_PORT}" \
        -e CORE_PEER_TLS_ENABLED="true" \
        -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${PEER_NAME#peer0.}/peers/${PEER_NAME}/tls/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${PEER_NAME#peer0.}/users/Admin@${PEER_NAME#peer0.}/msp \
        ${CLI_CONTAINER} peer channel list | grep -q "${CHANNEL_NAME}"
    
    if [ $? -ne 0 ]; then
        echo "${RED}错误: ${PEER_NAME} 未加入通道 ${CHANNEL_NAME}${NC}"
        return 1
    fi

    # 直接使用全局定义的 ORDERER_LIST
    for ORDERER in "${ORDERER_LIST[@]}"; do
        echo -e "${GREEN}通过 ${ORDERER} 更新 ${PEER_NAME} 的锚节点配置...${NC}"
        
        # 获取orderer的域名部分（去掉端口）
        ORDERER_HOST=$(echo $ORDERER | cut -d: -f1)
        
        docker exec \
            -e CORE_PEER_LOCALMSPID="${MSP_ID}" \
            -e CORE_PEER_ADDRESS="${PEER_NAME}:${PEER_PORT}" \
            -e CORE_PEER_TLS_ENABLED="true" \
            -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${PEER_NAME#peer0.}/peers/${PEER_NAME}/tls/ca.crt \
            -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/${PEER_NAME#peer0.}/users/Admin@${PEER_NAME#peer0.}/msp \
            ${CLI_CONTAINER} peer channel update \
                -o ${ORDERER} \
                -c ${CHANNEL_NAME} \
                -f ./channel-artifacts/${ANCHOR_TX_FILE} \
                --tls \
                --cafile "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/all-orderer-tlscacerts.pem" \
                --ordererTLSHostnameOverride ${ORDERER_HOST}

        if [ $? -eq 0 ]; then
            echo "${GREEN}${PEER_NAME} 通过 ${ORDERER} 锚节点更新成功${NC}"
            return 0
        else
            echo "${YELLOW}通过 ${ORDERER} 更新失败，尝试下一个orderer节点...${NC}"
        fi
    done
    
    echo "${RED}错误: ${PEER_NAME} 锚节点更新失败 - 所有orderer节点都尝试失败${NC}"
    return 1
}

# 移除通道函数
function removeChannel() {
    echo -e "${GREEN}开始从所有 Orderer 节点移除通道 ${CHANNEL_NAME}...${NC}"

    # 定义 Orderer 节点信息数组
    declare -a ORDERERS=(
        "unsp orderer1.unsp.example.com 7053 cli-unsp"
        "airline1 orderer2.airline1.example.com 8053 cli-airline1"
        "airline2 orderer3.airline2.example.com 9053 cli-airline2"
        "airline3 orderer4.airline3.example.com 10053 cli-airline3"
        "airline4 orderer5.airline4.example.com 11053 cli-airline4"
    )

    # 遍历所有 Orderer 节点
    for orderer_info in "${ORDERERS[@]}"; do
        # 解析 Orderer 信息
        read -r org orderer port cli_container <<< "$orderer_info"
        
        echo -e "${BLUE}正在从 ${orderer}:${port} 移除通道...${NC}"

        # 执行通道移除操作
        docker exec \
            ${cli_container} osnadmin channel remove \
            --channelID ${CHANNEL_NAME} \
            -o ${orderer}:${port} \
            --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/ca.crt" \
            --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/server.crt" \
            --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/server.key"

        # 检查命令执行结果
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}成功从 ${orderer}:${port} 移除通道 ${CHANNEL_NAME}${NC}"
        else
            echo -e "${YELLOW}警告: 无法从 ${orderer}:${port} 移除通道，可能该节点未加入通道${NC}"
            continue
        fi

        # 验证通道是否已从该 Orderer 节点移除
        CHANNEL_LIST=$(docker exec \
            ${cli_container} osnadmin channel list \
            -o ${orderer}:${port} \
            --ca-file "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/ca.crt" \
            --client-cert "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/server.crt" \
            --client-key "/opt/gopath/src/github.com/hyperledger/fabric/orderer/crypto-config/ordererOrganizations/${org}.example.com/orderers/${orderer}/tls/server.key")
        
        if [[ $CHANNEL_LIST == *"${CHANNEL_NAME}"* ]]; then
            errorln "通道 ${CHANNEL_NAME} 验证失败，仍然存在于 ${orderer}:${port}"
            return 1
        fi
    done

    # 清理通道相关文件
    echo -e "${BLUE}清理通道配置文件...${NC}"
    rm -f ./channel-artifacts/${CHANNEL_NAME}.block

    successln "通道 ${CHANNEL_NAME} 已成功从所有 Orderer 节点移除"
    return 0
}

# 网络部署函数
function networkUp() {
    cleanup
    createDirectories
    generateCertificates
    generateGenesisBlock
    startNetwork
    createChannel
    joinOrderersToChannel

    # 所有节点加入通道
    joinChannel peer0.unsp.example.com 7051 UNSPMSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/unsp.example.com/peers/peer0.unsp.example.com/tls/ca.crt
    joinChannel peer0.airline1.example.com 8051 Airline1MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline1.example.com/peers/peer0.airline1.example.com/tls/ca.crt
    joinChannel peer0.airline2.example.com 9051 Airline2MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline2.example.com/peers/peer0.airline2.example.com/tls/ca.crt
    joinChannel peer0.airline3.example.com 10051 Airline3MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline3.example.com/peers/peer0.airline3.example.com/tls/ca.crt
    joinChannel peer0.airline4.example.com 11051 Airline4MSP /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto-config/peerOrganizations/airline4.example.com/peers/peer0.airline4.example.com/tls/ca.crt

    # 更新所有组织的锚节点
    updateAnchorPeers peer0.unsp.example.com UNSPMSP UNSPMSPanchors.tx 7051
    updateAnchorPeers peer0.airline1.example.com Airline1MSP Airline1MSPanchors.tx 8051
    updateAnchorPeers peer0.airline2.example.com Airline2MSP Airline2MSPanchors.tx 9051
    updateAnchorPeers peer0.airline3.example.com Airline3MSP Airline3MSPanchors.tx 10051
    updateAnchorPeers peer0.airline4.example.com Airline4MSP Airline4MSPanchors.tx 11051

    successln "网络部署完成！"
}

# 脚本入口
if [ "$1" = "up" ]; then
    networkUp
elif [ "$1" = "down" ]; then
    removeChannel
    cleanup
else
    echo "用法: $0 [up|down]"
    exit 1
fi