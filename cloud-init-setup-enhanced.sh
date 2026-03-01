#!/bin/bash
# 增强版 cloud-init 种子盒部署脚本
# 最终环境：qBittorrent 4.3.8 + libtorrent v1.2.14 + Vertex (host网络) + BBRx
# 所有输出记录到日志文件
exec > /root/cloud-init-setup.log 2>&1

# ============================================================
# [内嵌存档] 原始工具脚本，避免后续远程地址失效
# ============================================================
cat << 'EOF_NC_QB438_SCRIPT' > /root/NC_QB438_archived.sh
#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <user> <password> <port> <qb_up_port>"
    exit 1
fi

USER=$1
PASSWORD=$2
PORT=${3:-8080}
UP_PORT=${4:-23333}
RAM=$(free -m | awk '/^Mem:/{print $2}')
CACHE_SIZE=$((RAM / 8))
cd /root
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) -u $USER -p $PASSWORD -c $CACHE_SIZE -q 4.3.9 -l v1.2.20 -x
apt install -y curl htop vnstat
systemctl stop qbittorrent-nox@$USER
#systemctl disable qbittorrent-nox@$USER
systemARCH=$(uname -m)
if [[ $systemARCH == x86_64 ]]; then
    wget -O /usr/bin/qbittorrent-nox https://raw.githubusercontent.com/guowanghushifu/Seedbox-Components/refs/heads/main/Torrent%20Clients/qBittorrent/x86_64/qBittorrent-4.3.8%20-%20libtorrent-v1.2.14/qbittorrent-nox
elif [[ $systemARCH == aarch64 ]]; then
    wget -O /usr/bin/qbittorrent-nox https://raw.githubusercontent.com/guowanghushifu/Seedbox-Components/refs/heads/main/Torrent%20Clients/qBittorrent/ARM64/qBittorrent-4.3.8%20-%20libtorrent-v1.2.14/qbittorrent-nox
fi
chmod +x /usr/bin/qbittorrent-nox
sed -i "s/WebUI\\\\Port=[0-9]*/WebUI\\\\Port=$PORT/" /home/$USER/.config/qBittorrent/qBittorrent.conf
sed -i "s/Connection\\\\PortRangeMin=[0-9]*/Connection\\\\PortRangeMin=$UP_PORT/" /home/$USER/.config/qBittorrent/qBittorrent.conf
sed -i "/\\[Preferences\\]/a General\\\\Locale=zh" /home/$USER/.config/qBittorrent/qBittorrent.conf
sed -i "/\\[Preferences\\]/a Downloads\\\\PreAllocation=false" /home/$USER/.config/qBittorrent/qBittorrent.conf
sed -i "/\\[Preferences\\]/a WebUI\\\\CSRFProtection=false" /home/$USER/.config/qBittorrent/qBittorrent.conf
sed -i "s/disable_tso_/# disable_tso_/" /root/.boot-script.sh
echo "systemctl enable qbittorrent-nox@$USER" >> /root/BBRx.sh
echo "systemctl start qbittorrent-nox@$USER" >> /root/BBRx.sh
echo "shutdown -r +1" >> /root/BBRx.sh
tune2fs -m 1 $(df -h / | awk 'NR==2 {print $1}') 
echo "接下来将自动重启2次，流程预计5-10分钟..."
shutdown -r +1

EOF_NC_QB438_SCRIPT

cat << 'EOF_INSTALL_SCRIPT' > /root/Install_archived.sh
#!/bin/sh
tput sgr0; clear

## Load Seedbox Components
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/seedbox_installation.sh)
# Check if Seedbox Components is successfully loaded
if [ $? -ne 0 ]; then
	echo "Component ~Seedbox Components~ failed to load"
	echo "Check connection with GitHub"
	exit 1
fi

## Load loading animation
source <(wget -qO- https://raw.githubusercontent.com/Silejonu/bash_loading_animations/main/bash_loading_animations.sh)
# Check if bash loading animation is successfully loaded
if [ $? -ne 0 ]; then
	fail "Component ~Bash loading animation~ failed to load"
	fail_exit "Check connection with GitHub"
fi
# Run BLA::stop_loading_animation if the script is interrupted
trap BLA::stop_loading_animation SIGINT

## Install function
install_() {
info_2 "$2"
BLA::start_loading_animation "${BLA_classic[@]}"
$1 1> /dev/null 2> $3
if [ $? -ne 0 ]; then
	fail_3 "FAIL" 
else
	info_3 "Successful"
	export $4=1
fi
BLA::stop_loading_animation
}

## Installation environment Check
info "Checking Installation Environment"
# Check Root Privilege
if [ $(id -u) -ne 0 ]; then 
    fail_exit "This script needs root permission to run"
fi

# Linux Distro Version check
if [ -f /etc/os-release ]; then
	. /etc/os-release
	OS=$NAME
	VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
	. /etc/lsb-release
	OS=$DISTRIB_ID
	VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
	OS=Debian
	VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
	OS=SuSe
elif [ -f /etc/redhat-release ]; then
	OS=Redhat
else
	OS=$(uname -s)
	VER=$(uname -r)
fi

if [[ ! "$OS" =~ "Debian" ]] && [[ ! "$OS" =~ "Ubuntu" ]]; then	#Only Debian and Ubuntu are supported
	fail "$OS $VER is not supported"
	info "Only Debian 10+ and Ubuntu 20.04+ are supported"
	exit 1
fi

if [[ "$OS" =~ "Debian" ]]; then	#Debian 10+ are supported
	if [[ ! "$VER" =~ "10" ]] && [[ ! "$VER" =~ "11" ]] && [[ ! "$VER" =~ "12" ]]; then
		fail "$OS $VER is not supported"
		info "Only Debian 10+ are supported"
		exit 1
	fi
fi

if [[ "$OS" =~ "Ubuntu" ]]; then #Ubuntu 20.04+ are supported
	if [[ ! "$VER" =~ "20" ]] && [[ ! "$VER" =~ "22" ]] && [[ ! "$VER" =~ "23" ]]; then
		fail "$OS $VER is not supported"
		info "Only Ubuntu 20.04+ is supported"
		exit 1
	fi
fi

## Read input arguments
while getopts "u:p:c:q:l:rbvx3oh" opt; do
  case ${opt} in
	u ) # process option username
		username=${OPTARG}
		;;
	p ) # process option password
		password=${OPTARG}
		;;
	c ) # process option cache
		cache=${OPTARG}
		#Check if cache is a number
		while true
		do
			if ! [[ "$cache" =~ ^[0-9]+$ ]]; then
				warn "Cache must be a number"
				need_input "Please enter a cache size (in MB):"
				read cache
			else
				break
			fi
		done
		#Converting the cache to qBittorrent's unit (MiB)
		qb_cache=$cache
		;;
	q ) # process option cache
		qb_install=1
		qb_ver=("qBittorrent-${OPTARG}")
		;;
	l ) # process option libtorrent
		lib_ver=("libtorrent-${OPTARG}")
		#Check if qBittorrent version is specified
		if [ -z "$qb_ver" ]; then
			warn "You must choose a qBittorrent version for your libtorrent install"
			qb_ver_choose
		fi
		;;
	r ) # process option autoremove
		autoremove_install=1
		;;
	b ) # process option autobrr
		autobrr_install=1
		;;
	v ) # process option vertex
		vertex_install=1
		;;
	x ) # process option bbr
		unset bbrv3_install
		bbrx_install=1	  
		;;
	3 ) # process option bbr
		unset bbrx_install
		bbrv3_install=1
		;;
	o ) # process option port
		if [[ -n "$qb_install" ]]; then
			need_input "Please enter qBittorrent port:"
			read qb_port
			while true
			do
				if ! [[ "$qb_port" =~ ^[0-9]+$ ]]; then
					warn "Port must be a number"
					need_input "Please enter qBittorrent port:"
					read qb_port
				else
					break
				fi
			done
			need_input "Please enter qBittorrent incoming port:"
			read qb_incoming_port
			while true
			do
				if ! [[ "$qb_incoming_port" =~ ^[0-9]+$ ]]; then
						warn "Port must be a number"
						need_input "Please enter qBittorrent incoming port:"
						read qb_incoming_port
				else
					break
				fi
			done
		fi
		if [[ -n "$autobrr_install" ]]; then
			need_input "Please enter autobrr port:"
			read autobrr_port
			while true
			do
				if ! [[ "$autobrr_port" =~ ^[0-9]+$ ]]; then
					warn "Port must be a number"
					need_input "Please enter autobrr port:"
					read autobrr_port
				else
					break
				fi
			done
		fi
		if [[ -n "$vertex_install" ]]; then
			need_input "Please enter vertex port:"
			read vertex_port
			while true
			do
				if ! [[ "$vertex_port" =~ ^[0-9]+$ ]]; then
					warn "Port must be a number"
					need_input "Please enter vertex port:"
					read vertex_port
				else
					break
				fi
			done
		fi
		;;
	h ) # process option help
		info "Help:"
		info "Usage: ./Install.sh -u <username> -p <password> -c <Cache Size(unit:MiB)> -q <qBittorrent version> -l <libtorrent version> -b -v -r -3 -x -p"
		info "Example: ./Install.sh -u jerry048 -p 1LDw39VOgors -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3"
		source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Torrent%20Clients/qBittorrent/qBittorrent_install.sh)
		seperator
		info "Options:"
		need_input "1. -u : Username"
		need_input "2. -p : Password"
		need_input "3. -c : Cache Size for qBittorrent (unit:MiB)"
		echo -e "\n"
		need_input "4. -q : qBittorrent version"
		need_input "Available qBittorrent versions:"
		tput sgr0; tput setaf 7; tput dim; history -p "${qb_ver_list[@]}"; tput sgr0
		echo -e "\n"
		need_input "5. -l : libtorrent version"
		need_input "Available qBittorrent versions:"
		tput sgr0; tput setaf 7; tput dim; history -p "${lib_ver_list[@]}"; tput sgr0
		echo -e "\n"
		need_input "6. -r : Install autoremove-torrents"
		need_input "7. -b : Install autobrr"
		need_input "8. -v : Install vertex"
		need_input "9. -x : Install BBRx"
		need_input "10. -3 : Install BBRv3"
		need_input "11. -p : Specify ports for qBittorrent, autobrr and vertex"
		need_input "12. -h : Display help message"
		exit 0
		;;
	\? ) 
		info "Help:"
		info_2 "Usage: ./Install.sh -u <username> -p <password> -c <Cache Size(unit:MiB)> -q <qBittorrent version> -l <libtorrent version> -b -v -r -3 -x -p"
		info_2 "Example ./Install.sh -u jerry048 -p 1LDw39VOgors -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3"
		exit 1
		;;
	esac
done

# System Update & Dependencies Install
info "Start System Update & Dependencies Install"
update

## Install Seedbox Environment
tput sgr0; clear
info "Start Installing Seedbox Environment"
echo -e "\n"


# qBittorrent
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Torrent%20Clients/qBittorrent/qBittorrent_install.sh)
# Check if qBittorrent install is successfully loaded
if [ $? -ne 0 ]; then
	fail_exit "Component ~qBittorrent install~ failed to load"
fi

if [[ ! -z "$qb_install" ]]; then
	## Check if all the required arguments are specified
	#Check if username is specified
	if [ -z "$username" ]; then
		warn "Username is not specified"
		need_input "Please enter a username:"
		read username
	fi
	#Check if password is specified
	if [ -z "$password" ]; then
		warn "Password is not specified"
		need_input "Please enter a password:"
		read password
	fi
	## Create user if it does not exist
	if ! id -u $username > /dev/null 2>&1; then
		useradd -m -s /bin/bash $username
		# Check if the user is created successfully
		if [ $? -ne 0 ]; then
			warn "Failed to create user $username"
			return 1
		fi
	fi
	chown -R $username:$username /home/$username
	#Check if cache is specified
	if [ -z "$cache" ]; then
		warn "Cache is not specified"
		need_input "Please enter a cache size (in MB):"
		read cache
		#Check if cache is a number
		while true
		do
			if ! [[ "$cache" =~ ^[0-9]+$ ]]; then
				warn "Cache must be a number"
				need_input "Please enter a cache size (in MB):"
				read cache
			else
				break
			fi
		done
		qb_cache=$cache
	fi
	#Check if qBittorrent version is specified
	if [ -z "$qb_ver" ]; then
		warn "qBittorrent version is not specified"
		qb_ver_check
	fi
	#Check if libtorrent version is specified
	if [ -z "$lib_ver" ]; then
		warn "libtorrent version is not specified"
		lib_ver_check
	fi
	#Check if qBittorrent port is specified
	if [ -z "$qb_port" ]; then
		qb_port=8080
	fi
	#Check if qBittorrent incoming port is specified
	if [ -z "$qb_incoming_port" ]; then
		qb_incoming_port=45000
	fi

	## qBittorrent & libtorrent compatibility check
	qb_install_check

	## qBittorrent install
	install_ "install_qBittorrent_ $username $password $qb_ver $lib_ver $qb_cache $qb_port $qb_incoming_port" "Installing qBittorrent" "/tmp/qb_error" qb_install_success
fi

# autobrr Install
if [[ ! -z "$autobrr_install" ]]; then
	install_ install_autobrr_ "Installing autobrr" "/tmp/autobrr_error" autobrr_install_success
fi

# vertex Install
if [[ ! -z "$vertex_install" ]]; then
	install_ install_vertex_ "Installing vertex" "/tmp/vertex_error" vertex_install_success
fi

# autoremove-torrents Install
if [[ ! -z "$autoremove_install" ]]; then
	install_ install_autoremove-torrents_ "Installing autoremove-torrents" "/tmp/autoremove_error" autoremove_install_success
fi

seperator

## Tunning
info "Start Doing System Tunning"
install_ tuned_ "Installing tuned" "/tmp/tuned_error" tuned_success
install_ set_txqueuelen_ "Setting txqueuelen" "/tmp/txqueuelen_error" txqueuelen_success
install_ set_file_open_limit_ "Setting File Open Limit" "/tmp/file_open_limit_error" file_open_limit_success

# Check for Virtual Environment since some of the tunning might not work on virtual machine
systemd-detect-virt > /dev/null
if [ $? -eq 0 ]; then
	warn "Virtualization is detected, skipping some of the tunning"
	install_ disable_tso_ "Disabling TSO" "/tmp/tso_error" tso_success
else
	install_ set_disk_scheduler_ "Setting Disk Scheduler" "/tmp/disk_scheduler_error" disk_scheduler_success
	install_ set_ring_buffer_ "Setting Ring Buffer" "/tmp/ring_buffer_error" ring_buffer_success
fi
install_ set_initial_congestion_window_ "Setting Initial Congestion Window" "/tmp/initial_congestion_window_error" initial_congestion_window_success
install_ kernel_settings_ "Setting Kernel Settings" "/tmp/kernel_settings_error" kernel_settings_success



# BBRx
if [[ ! -z "$bbrx_install" ]]; then
	# Check if Tweaked BBR is already installed
	if [[ ! -z "$(lsmod | grep bbrx)" ]]; then
		warn echo "Tweaked BBR is already installed"
	else
		install_ install_bbrx_ "Installing BBRx" "/tmp/bbrx_error" bbrx_install_success
	fi
fi

# BBRv3
if [[ ! -z "$bbrv3_install" ]]; then
	install_ install_bbrv3_ "Installing BBRv3" "/tmp/bbrv3_error" bbrv3_install_success
fi

## Configue Boot Script
info "Start Configuing Boot Script"
touch /root/.boot-script.sh && chmod +x /root/.boot-script.sh
cat << EOF > /root/.boot-script.sh
#!/bin/bash
sleep 120s
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/seedbox_installation.sh)
# Check if Seedbox Components is successfully loaded
if [ \$? -ne 0 ]; then
	exit 1
fi
set_txqueuelen_
# Check for Virtual Environment since some of the tunning might not work on virtual machine
systemd-detect-virt > /dev/null
if [ \$? -eq 0 ]; then
	disable_tso_
else
	set_disk_scheduler_
	set_ring_buffer_
fi
set_initial_congestion_window_
EOF
# Configure the script to run during system startup
cat << EOF > /etc/systemd/system/boot-script.service
[Unit]
Description=boot-script
After=network.target

[Service]
Type=simple
ExecStart=/root/.boot-script.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable boot-script.service


seperator

## Finalizing the install
info "Seedbox Installation Complete"
publicip=$(curl -s https://ipinfo.io/ip)

# Display Username and Password
# qBittorrent
if [[ ! -z "$qb_install_success" ]]; then
	info "qBittorrent installed"
	boring_text "qBittorrent WebUI: http://$publicip:$qb_port"
	boring_text "qBittorrent Username: $username"
	boring_text "qBittorrent Password: $password"
	echo -e "\n"
fi
# autoremove-torrents
if [[ ! -z "$autoremove_install_success" ]]; then
	info "autoremove-torrents installed"
	boring_text "Config at /home/$username/.config.yml"
	boring_text "Please read https://autoremove-torrents.readthedocs.io/en/latest/config.html for configuration"
	echo -e "\n"
fi
# autobrr
if [[ ! -z "$autobrr_install_success" ]]; then
	info "autobrr installed"
	boring_text "autobrr WebUI: http://$publicip:$autobrr_port"
	echo -e "\n"
fi
# vertex
if [[ ! -z "$vertex_install_success" ]]; then
	info "vertex installed"
	boring_text "vertex WebUI: http://$publicip:$vertex_port"
	boring_text "vertex Username: $username"
	boring_text "vertex Password: $password"
	echo -e "\n"
fi
# BBR
if [[ ! -z "$bbrx_install_success" ]]; then
	info "BBRx successfully installed, please reboot for it to take effect"
fi

if [[ ! -z "$bbrv3_install_success" ]]; then
	info "BBRv3 successfully installed, please reboot for it to take effect"
fi

exit 0


EOF_INSTALL_SCRIPT
chmod +x /root/Install_archived.sh /root/NC_QB438_archived.sh


# ============================================================
# 全局变量（使用前请修改以下配置）
# ============================================================
# qBittorrent 用户名和密码
USER="admin"
PASSWORD="adminadmin"
# qBittorrent WebUI 端口和 BT 端口
PORT=8080
UP_PORT=23333
# Vertex 备份恢复（可选，留空则跳过）
# 部署时填入私有仓库 URL 和 GitHub Token（不要提交到公开仓库）
VERTEX_BACKUP_URL=""      # 如：https://raw.githubusercontent.com/<用户>/<仓库>/main/Vertex-backups.tar.gz
GITHUB_TOKEN=""           # GitHub Personal Access Token（repo 权限）

QB_CONF="/home/${USER}/.config/qBittorrent/qBittorrent.conf"

# ============================================================
# 工具函数：带重试的下载（最多尝试 3 次，每次间隔 5 秒）
# ============================================================
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "  -> 下载尝试 ${attempt}/${max_attempts}: ${url}"
        if wget -O "$output" "$url"; then
            echo "  -> 下载成功"
            return 0
        fi
        echo "  -> 下载失败，${attempt < max_attempts:+等待 5 秒后重试...}"
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "  !! 下载失败（已重试 ${max_attempts} 次）: ${url}"
    return 1
}

# ============================================================
# [1/6] 获取机器内存，动态计算 qB 缓存
# ============================================================
echo "=== [1/6] 获取机器内存，动态计算 qB 缓存 ==="
RAM=$(free -m | awk '/^Mem:/{print $2}')
CACHE_SIZE=$((RAM / 8))
echo "  -> 总内存: ${RAM}MB，分配缓存: ${CACHE_SIZE}MB"

cd /root

# ============================================================
# [2/6] 部署 Jerry048 主框架、Vertex 以及 BBRx 优化
# ============================================================
echo "=== [2/6] 部署 Jerry048 主框架、Vertex 以及 BBRx 优化 ==="
echo "  -> 注意：框架使用 qB 4.3.9 + lt v1.2.20 初始化环境，第3步会替换为目标内核"

INSTALL_SCRIPT="/root/Install_archived.sh"
bash "$INSTALL_SCRIPT" -u ${USER} -p ${PASSWORD} -c ${CACHE_SIZE} -q 4.3.9 -l v1.2.20 -v -x
FRAMEWORK_OK=$?
if [ $FRAMEWORK_OK -ne 0 ]; then
    echo "  !! 警告：框架安装返回非零状态码 ${FRAMEWORK_OK}，继续执行后续步骤..."
else
    echo "  -> 框架安装完成"
fi

# ============================================================
# [3/6] 环境组件增强与高性能内核植入
# ============================================================
echo "=== [3/6] 环境组件增强与 qBittorrent 高性能内核植入 ==="

# 安装基础工具（带重试）
echo "  -> 安装基础工具..."
for i in 1 2 3; do
    apt update && apt install -y curl htop vnstat && break
    echo "  -> apt 安装失败，第 ${i} 次重试..."
    sleep 3
done

# 停止 qB 服务并等待配置落盘
echo "  -> 停止 qBittorrent 服务..."
systemctl stop qbittorrent-nox@${USER} 2>/dev/null || true
sleep 3
echo "  -> 已等待 3 秒，确保配置落盘"

# 根据架构下载对应的高性能内核
systemARCH=$(uname -m)
echo "  -> 检测到系统架构: ${systemARCH}"

QB_URL=""
if [[ $systemARCH == "x86_64" ]]; then
    QB_URL="https://raw.githubusercontent.com/guowanghushifu/Seedbox-Components/refs/heads/main/Torrent%20Clients/qBittorrent/x86_64/qBittorrent-4.3.8%20-%20libtorrent-v1.2.14/qbittorrent-nox"
elif [[ $systemARCH == "aarch64" ]]; then
    QB_URL="https://raw.githubusercontent.com/guowanghushifu/Seedbox-Components/refs/heads/main/Torrent%20Clients/qBittorrent/ARM64/qBittorrent-4.3.8%20-%20libtorrent-v1.2.14/qbittorrent-nox"
else
    echo "  !! 警告：不支持的架构 ${systemARCH}，跳过内核替换"
fi

if [[ -n "$QB_URL" ]]; then
    # 备份原版二进制
    if [ -f /usr/bin/qbittorrent-nox ]; then
        cp /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox.bak
        echo "  -> 已备份原版二进制到 /usr/bin/qbittorrent-nox.bak"
    fi

    if download_with_retry "$QB_URL" /usr/bin/qbittorrent-nox; then
        chmod +x /usr/bin/qbittorrent-nox
        echo "  -> 高性能内核植入完成 (qB 4.3.8 + lt v1.2.14)"
    else
        # 下载失败，恢复备份
        if [ -f /usr/bin/qbittorrent-nox.bak ]; then
            mv /usr/bin/qbittorrent-nox.bak /usr/bin/qbittorrent-nox
            echo "  !! 内核下载失败，已恢复原版二进制"
        else
            echo "  !! 内核下载失败，且无备份可恢复"
        fi
    fi
fi

# 修改 qBittorrent 配置
echo "  -> 修改 qBittorrent 配置..."
if [ -f "$QB_CONF" ]; then
    sed -i "s/WebUI\\\\Port=[0-9]*/WebUI\\\\Port=$PORT/" "$QB_CONF"
    sed -i "s/Connection\\\\PortRangeMin=[0-9]*/Connection\\\\PortRangeMin=$UP_PORT/" "$QB_CONF"
    grep -q "General\\\\Locale" "$QB_CONF" || sed -i "/\\[Preferences\\]/a General\\\\Locale=zh" "$QB_CONF"
    grep -q "Downloads\\\\PreAllocation" "$QB_CONF" || sed -i "/\\[Preferences\\]/a Downloads\\\\PreAllocation=false" "$QB_CONF"
    grep -q "WebUI\\\\CSRFProtection" "$QB_CONF" || sed -i "/\\[Preferences\\]/a WebUI\\\\CSRFProtection=false" "$QB_CONF"
    echo "  -> 配置修改完成: WebUI端口=${PORT}, BT端口=${UP_PORT}, 语言=中文"
else
    echo "  !! 警告：配置文件不存在: ${QB_CONF}"
fi

# 修复开机网卡优化报错（只注释未被注释的行）
if [ -f /root/.boot-script.sh ]; then
    sed -i '/^[^#]*disable_tso_/s/^/# /' /root/.boot-script.sh
    echo "  -> 已修复 .boot-script.sh 中的 disable_tso_ 问题"
fi

# ============================================================
# [4/6] 强化系统储备池：1% 安全冗余隔离分配
# ============================================================
echo "=== [4/6] 强化系统储备池：1% 安全冗余隔离分配 ==="
ROOT_DEV=$(df -h / | awk 'NR==2 {print $1}')
tune2fs -m 1 "$ROOT_DEV"
echo "  -> 已将 ${ROOT_DEV} 预留块设置为 1%"

# ============================================================
# [5/6] Vertex Docker Host 网络穿透重建
# ============================================================
echo "=== [5/6] Vertex Docker Host 网络穿透重建 ==="
echo "  -> 停止并移除旧 Vertex 容器..."
docker stop vertex 2>/dev/null || true
docker rm -f vertex 2>/dev/null || true

# 恢复 Vertex 备份（可选）
if [ -n "$VERTEX_BACKUP_URL" ] && [ -n "$GITHUB_TOKEN" ]; then
    VERTEX_BACKUP="/root/Vertex-backups.tar.gz"
    echo "  -> 下载 Vertex 备份文件..."
    if wget --header="Authorization: token $GITHUB_TOKEN" -O "$VERTEX_BACKUP" "$VERTEX_BACKUP_URL"; then
        tar -xzf "$VERTEX_BACKUP" -C /root/
        rm -f "$VERTEX_BACKUP"
        echo "  -> Vertex 备份恢复完成"
    else
        echo "  !! 备份下载失败，将以默认配置启动"
    fi
else
    echo "  -> 未配置备份恢复，将以默认配置启动"
fi

echo "  -> 以 host 网络模式重建 Vertex..."
if docker run -d \
    --name vertex \
    --restart unless-stopped \
    --network host \
    --privileged \
    -v /root/vertex:/vertex \
    -e TZ=Asia/Shanghai \
    lswl/vertex:stable; then
    echo "  -> Vertex 重建成功 (host 网络模式 + privileged)"
else
    echo "  !! Vertex 重建失败，请手动检查"
fi

# ============================================================
# [6/6] 收尾自启与重启清理
# ============================================================
echo "=== [6/6] 收尾自启与重启清理 ==="
systemctl enable qbittorrent-nox@${USER}
systemctl start qbittorrent-nox@${USER}
echo "  -> qBittorrent 服务已启用并启动"

# 宿主机定时清理（容器内无法执行这些命令）
echo "  -> 配置宿主机 crontab..."
(crontab -l 2>/dev/null | grep -v 'apt clean\|journalctl.*vacuum\|system-cleanup\|fstrim'; cat <<'CRON_EOF'
# 每天凌晨4点 SSD TRIM
0 4 * * * /sbin/fstrim -av >> /var/log/fstrim.log 2>&1
# 每周日凌晨3点清理系统缓存
0 3 * * 0 apt clean && journalctl --vacuum-size=10M && truncate -s 0 /var/log/btmp
CRON_EOF
) | crontab -
echo "  -> 宿主机 crontab 配置完成"


# 验证服务状态
sleep 2
if systemctl is-active --quiet qbittorrent-nox@${USER}; then
    echo "  -> ✅ qBittorrent 服务运行中"
else
    echo "  -> ⚠️ qBittorrent 服务未正常启动，请检查日志"
fi

if docker ps --format '{{.Names}}' | grep -q "^vertex$"; then
    echo "  -> ✅ Vertex 容器运行中"
else
    echo "  -> ⚠️ Vertex 容器未正常运行，请检查 Docker"
fi

# 取消可能存在的底层或历史遗留重启计划
shutdown -c 2>/dev/null || true
# 全部完成，发起安全重启
echo "  -> 部署完成，1 分钟后安全重启..."
shutdown -r +1

echo "============================================"
echo "  部署摘要"
echo "============================================"
echo "  用户:         ${USER}"
echo "  WebUI 端口:   ${PORT}"
echo "  BT 端口:      ${UP_PORT}"
echo "  缓存大小:     ${CACHE_SIZE}MB"
echo "  内核版本:     qBittorrent 4.3.8 + libtorrent v1.2.14"
echo "  Vertex:       host 网络模式"
echo "  日志文件:     /root/cloud-init-setup.log"
echo "============================================"
