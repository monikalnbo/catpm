# 如何把包发布到远程源（GitHub 即源）

catpm 的远程源不需要专门服务器：任何能按固定 URL 提供 `index.json` 和
`.cpkg` 文件的地方都是一个合法源。GitHub 仓库天然满足。三步：

## 1. 打包

在包目录（有 `catpm.json` + `index.catc`）：

```bash
catpm pack          # 产出 dist/<name>-<version>.cpkg
```

## 2. 发布（更新仓库里的 registry/）

```bash
catpm publish registry/            # 本地 registry 目录：复制 .cpkg + 更新 index.json
git add registry/ && git commit -m "publish <name>@<ver>" && git push
```

`publish` 把 `.cpkg` 复制到 `registry/<name>/` 并把版本、sha256、deps 合并进
`registry/index.json`。提交推送后全世界即可使用。

## 3. 使用（远程 URL 源）

```bash
export CATPM_REGISTRY=https://raw.githubusercontent.com/<user>/catpm/main/registry
catpm add <name>[@spec]
```

catpm 会下载 `index.json`、按说明符解析、下载所选 `.cpkg`、校验 sha256、
解包进 `deps/`。缓存放在 `.catpm-cache/`。
