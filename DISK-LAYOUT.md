# 磁盘布局文档

> 配套配置: `modules/storage.nix`（声明式挂载）
> 池管理: `scripts/disk-pool-mount.sh`（mergerfs + SnapRAID）
> 更新日期: 2026-05-09

## 物理盘总览

| 设备 | 大小 | 位置 | 用途 |
|------|------|------|------|
| nvme0n1 | 465G | 内置 NVMe | 系统盘（NixOS + Windows 双系统） |
| sda | 1.8T | 外置 HDD | POOL-B1 冷存储 |
| sdb | 1.8T | 内置 HDD | 主数据 + 游戏 + 备份 |
| sdc | 1.8T | 内置 HDD | POOL-D1 AI 数据 + PARITY 校验 |
| sdd | 3.6T | 内置 HDD | POOL-E1 池扩展 |

## 分区详情

### nvme0n1 — NVMe SSD (465G)

| 分区 | 标签 | 大小 | 文件系统 | UUID | 挂载点 | 说明 |
|------|------|------|---------|------|--------|------|
| p1 | SSD-WinExt | 22G | NTFS | 5E8C66368C6608BB | `/mnt/SSD-WinExt` | Windows 扩展分区 |
| p2 | ESP | 256M | vfat | FA67-631E | `/boot/efi`, `/mnt/win_efi` | NixOS EFI |
| p3 | SSD-WinReserved | 755M | NTFS | 0FE50EDB0FE50EDB | — | Windows 保留（不挂载） |
| p4 | SSD-Windows | 232G | NTFS | 0E8D03FB0E8D03FB | `/mnt/win_c` | Windows C: 盘（只读） |
| p5 | — | 256M | NTFS | 0C53021F0C53021F | — | 未知恢复分区（不挂载） |
| p6 | SSD-WinApps | 111G | NTFS | 04F0C4BEF0C4B6E8 | `/mnt/SSD-WinApps` | Windows 应用（只读） |
| p7 | — | 8.9G | NTFS | FC84D3BB84D3769C | — | WinRE（不挂载） |
| p8 | ESP_WIN | 512M | vfat | 2E0C-356B | — | Windows EFI（不挂载） |
| p9 | — | 90G | ext4 | 2d8662db-... | `/` | NixOS 根分区 |

### sda — 外置 HDD (1.8T)

| 分区 | 标签 | 大小 | 文件系统 | UUID | 挂载点 | 说明 |
|------|------|------|---------|------|--------|------|
| 1 | POOL-B1 | 1.8T | NTFS | B2BCF4DBBCF49B55 | `/mnt/pool-disks/POOL-B1` | 冷存储（未加入 mergerfs 池） |

### sdb — 内置 HDD (1.8T)

| 分区 | 标签 | 大小 | 文件系统 | UUID | 挂载点 | 说明 |
|------|------|------|---------|------|--------|------|
| 1 | — | 100M | vfat | 0F05-0E66 | — | 未知（可能 Windows 残留） |
| 2 | HDD1-Backup | 53G | NTFS | 0EF04734F0472177 | `/mnt/HDD1-Backup` | 系统备份 |
| 3 | HDD1-Games | 878G | NTFS | 1031167F1031167F | `/mnt/HDD1-Games` | Steam/游戏 |
| 4 | POOL-A1 | 932G | NTFS | C672D33272D32649 | `/mnt/data` | 主数据存储 |

### sdc — 内置 HDD (1.8T)

| 分区 | 标签 | 大小 | 文件系统 | UUID | 挂载点 | 说明 |
|------|------|------|---------|------|--------|------|
| 1 | POOL-D1 | 935G | ext4 | d2c36cb2-... | `/mnt/pool-disks/POOL-D1` | AI 数据 + 池成员 |
| 2 | PARITY-1 | 928G | NTFS | 5E98B61798B5EDA1 | — | SnapRAID 奇偶校验 |

### sdd — 内置 HDD (3.6T)

| 分区 | 标签 | 大小 | 文件系统 | UUID | 挂载点 | 说明 |
|------|------|------|---------|------|--------|------|
| 1 | POOL-E1 | 3.6T | NTFS | DE22F5F022F5CD91 | `/mnt/pool-disks/POOL-E1` | 池扩展成员 |

## 存储池配置

### MergerFS 池 `/mnt/pool`

合并: POOL-D1 + POOL-E1 → `/mnt/pool`
策略: `category.create=mfs`（新文件写入空间最多的盘）
管理: `disk-pool-mount.sh` 的 `merge_pool()` 函数

### SnapRAID

校验盘: PARITY-1 (`/mnt/pool-disks/PARITY-1`)
数据盘: POOL-D1, POOL-E1
定时: 每日 12:00 同步

## 恢复流程

在新机器上恢复此磁盘布局:

1. 按上表分区并打标签
2. `git clone git@github.com:mohdfaiz10101-cmyk/my-nixos.git /etc/nixos`
3. 检查 `hardware-configuration.nix` 中的 UUID 是否匹配
4. `sudo nixos-rebuild switch --flake /etc/nixos#charlie`
5. 验证: `mount | grep /mnt` 检查所有挂载点
