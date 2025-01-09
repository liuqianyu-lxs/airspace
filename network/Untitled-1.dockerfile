docker exec \
    -e CHANNEL_NAME="airspacechannel" \
    cli osnadmin channel remove \
    --channelID airspacechannel \
    -o ${ORDERER} \
    --ca-file ${CA_FILE} \
    --client-cert ${CLIENT_CERT} \
    --client-key ${CLIENT_KEY}



    #a安装必要的依赖

    # 安装curl
sudo apt-get update
sudo apt-get install curl

# 安装docker和docker-compose
sudo apt-get install docker.io docker-compose

# 确保当前用户在docker组中
sudo usermod -aG docker $USER
# 注意：添加用户到docker组后需要重新登录才能生效

# 安装golang (需要1.20或更高版本)
wget https://go.dev/dl/go1.20.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.20.linux-amd64.tar.gz

# 设置GO环境变量
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc

2.下载fabric和fabric-samples

# 创建工作目录
mkdir -p $HOME/fabric
cd $HOME/fabric

# 下载fabric bootstrap脚本
curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/bootstrap.sh > bootstrap.sh
chmod +x bootstrap.sh

# 下载fabric-samples和二进制文件
# 2.5.4 是示例版本，您可以根据需要更改
./bootstrap.sh 2.5.4 1.5.7

# 验证安装
cryptogen version
configtxgen version

3.