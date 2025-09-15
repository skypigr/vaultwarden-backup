# Vaultwarden Backup with GPG Encryption — 设计文档

## 1. 项目背景

`vaultwarden-backup` 是一个社区开源项目，用于备份 Vaultwarden（Bitwarden 的轻量级服务端）数据，并通过 Rclone 上传到云端存储（Google Drive、OneDrive 等）。

现有功能包括：

* 数据目录打包（zip 或 tar）
* 上传到云端 Rclone remote
* Cron 定时执行备份
* 可选 ZIP 密码保护

**缺陷/改进需求：**

* 原始备份文件在上传前未加密（除非使用 ZIP 密码）
* 为了提高安全性，需要支持 **GPG 公钥加密**，实现端到端加密，确保备份文件在云端存储中安全。

---

## 2. 设计目标

1. 在现有备份流程中增加 **GPG 公钥加密**支持
2. 支持环境变量配置公钥及接收者
3. 保持现有 **Cron 定时备份**功能不受影响
4. 保持 Rclone 上传功能兼容原有 remote
5. 设计可扩展，便于其他加密方式或签名方案加入

---

## 3. 数据流设计

```
Vaultwarden 数据目录 (/data)
        │
        ▼
    打包为 backup.tar.gz
        │
        ▼
    GPG 加密 -> backup.tar.gz.gpg
        │
        ▼
    Rclone 上传 -> VaultwardenBackup:backup/
```

* 数据目录 `/data` 由 Vaultwarden 容器 volume 挂载
* 生成的加密备份文件存放在临时目录 `/backup`
* Rclone 上传使用 `.gpg` 文件，原始备份可选择保留或删除

---

## 4. 系统组件设计

| 组件                    | 功能                                         |
| --------------------- | ------------------------------------------ |
| Vaultwarden 容器        | 提供密码管理服务，数据存储在 Docker volume 中             |
| Vaultwarden-backup 容器 | 负责打包、加密、上传备份                               |
| backup.sh (入口脚本)      | 备份逻辑，包括打包、GPG 加密、Rclone 上传                 |
| Rclone                | 上传文件到远程云端 storage（Google Drive、OneDrive 等） |
| Cron                  | 定时调用 backup.sh，保证定期备份                      |
| GPG                   | 公钥加密，确保数据在传输及云端存储中的安全                      |

---

## 5. Docker 镜像设计

### 5.1 基础镜像

* 使用官方 `ttionya/vaultwarden-backup:latest`
* 安装 `gpg` 命令行工具

### 5.2 Dockerfile 增加 GPG

```dockerfile
FROM ttionya/vaultwarden-backup:latest

# 安装 GPG
RUN apt-get update && apt-get install -y gnupg

# 入口脚本无需改变，只需修改 backup.sh 增加加密步骤
```

### 5.3 卷挂载

* Vaultwarden 数据卷：`vw_data:/data`
* 临时备份目录：`./backup:/backup`
* Rclone 配置卷：`vaultwarden-rclone-data:/config/rclone`

---

## 6. 环境变量设计

| 变量                   | 说明               | 示例                   |
| -------------------- | ---------------- | -------------------- |
| `DATA_DIR`           | Vaultwarden 数据目录 | `/data`              |
| `RCLONE_REMOTE_NAME` | Rclone 远程名称      | `VaultwardenBackup`  |
| `CRON_SCHEDULE`      | Cron 定时表达式       | `0 2 * * *`          |
| `GPG_PUBLIC_KEY`     | GPG 公钥路径或内容      | `/backup/pubkey.asc` |
| `GPG_RECIPIENT`      | 加密接收者邮箱/ID       | `backup@example.com` |
| `GPG_PASSPHRASE`     | 可选，解锁私钥用         | `******`             |
| `KEEP_LOCAL_BACKUP`  | 是否保留本地未加密备份      | `false`              |

---

## 7. 备份脚本修改方案

### 7.1 现有流程

1. 打包 Vaultwarden 数据为 `backup.tar.gz`
2. 上传至 Rclone remote
3. 可选 ZIP 密码保护

### 7.2 新增 GPG 加密步骤

```bash
# 原始备份文件路径
BACKUP_FILE="/backup/backup.tar.gz"

# 加密后的文件路径
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"

# GPG 加密
gpg --yes --batch --trust-model always \
    --recipient "$GPG_RECIPIENT" \
    --output "$ENCRYPTED_FILE" \
    --encrypt "$BACKUP_FILE"

# 可选：删除原始未加密文件
if [ "$KEEP_LOCAL_BACKUP" != "true" ]; then
    rm -f "$BACKUP_FILE"
fi

# 上传加密文件
rclone copy "$ENCRYPTED_FILE" "$RCLONE_REMOTE_NAME:backup/"
```

* 脚本兼容原有 Cron 调度
* 支持多接收者加密（`--recipient "user1@example.com" --recipient "user2@example.com"`）

---

## 8. Docker Compose 示例

```yaml
version: "3.9"

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - vw_data:/data
    environment:
      - WEBSOCKET_ENABLED=true
    networks:
      - happy-services

  vaultwarden-backup:
    build: ./vaultwarden-backup-gpg
    container_name: vaultwarden_backup
    restart: unless-stopped
    volumes:
      - vw_data:/data
      - vaultwarden-rclone-data:/config/rclone
      - ./backup:/backup
    environment:
      - DATA_DIR=/data
      - RCLONE_REMOTE_NAME=VaultwardenBackup
      - CRON_SCHEDULE="0 2 * * *"
      - GPG_RECIPIENT=backup@example.com
      - GPG_PUBLIC_KEY=/backup/pubkey.asc
      - KEEP_LOCAL_BACKUP=false
    networks:
      - happy-services

networks:
  happy-services:
    external: true

volumes:
  vw_data:
  vaultwarden-rclone-data:
```

---

## 9. 安全注意事项

1. **GPG 公钥管理**

   * 不要在 Dockerfile 中直接写明公钥内容
   * 可挂载外部公钥文件或通过 Secret 管理
2. **Rclone 配置**

   * 避免使用内部 client\_id/client\_secret，建议自建 OAuth 应用
3. **本地备份**

   * 默认删除未加密文件，避免敏感数据泄露
4. **Cron 日志**

   * 记录加密及上传日志，方便排查问题

---

## 10. 测试与验证

1. 手动运行备份脚本，确认生成 `.gpg` 文件
2. 使用 `gpg --decrypt` 验证备份文件可解密
3. 上传至 Rclone remote 并检查文件完整性
4. Cron 定时测试，确认自动加密上传成功

---

## 11. 后续可扩展功能

1. **备份文件签名**（GPG 签名）
2. **多云同步**（Rclone 支持多个 remote）
3. **增量备份**（只备份变化数据）
4. **加密日志存储**（提升审计能力）


