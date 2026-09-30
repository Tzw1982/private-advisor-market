# private-advisor-market

**私人顾问团 · 人才市场** —— 专家包（`.expert`）的公开仓库后端。

客户端从本仓库的 `catalog/index.json` 拉取专家索引，从 GitHub Release 下载 `.expert` 包，
经过 10 步安全校验后安装到「我的专家」。

---

## 仓库结构

```
private-advisor-market/
├── catalog/index.json        # 市场索引（由 scripts/build_index.dart 生成，勿手改）
├── schemas/                  # JSON Schema：manifest / expert / index
├── packages-src/             # 专家包源码（**贡献者只改这里**）
│   └── <slug>/
│       ├── manifest.json     # 包清单（哈希由 seal 脚本回填）
│       ├── expert.json       # 专家定义（市场展示信息）
│       ├── agents/main.md    # 系统提示词
│       ├── avatars/expert.png
│       └── README.md
├── scripts/
│   ├── package_utils.dart    # 共享校验逻辑
│   ├── seal.dart             # 回填 sha256 / files[]
│   ├── validate.dart         # 校验全部包
│   └── build_index.dart      # 生成 catalog/index.json
└── .github/workflows/validate.yml
```

---

## 如何贡献一个专家（UGC）

1. **Fork** 本仓库。
2. 在 `packages-src/` 下新建目录 `<your-expert-slug>`（小写字母 + 连字符）。
3. 按下面的模板写 4 个文件（头像可选）。
4. 本地跑通：
   ```bash
   dart pub get
   dart run scripts/seal.dart       # 回填哈希
   dart run scripts/validate.dart   # 自检
   ```
5. **提 PR**。CI 会自动校验；维护者 review 后合并。
6. 合并后 CI 自动重建 `catalog/index.json`，所有客户端下次刷新即可见。

---

## manifest.json 模板

```json
{
  "schemaVersion": 1,
  "packageId": "org.yourname.expert-slug",
  "slug": "expert-slug",
  "version": "1.0.0",
  "appVersion": ">=1.3.0",
  "displayName": "专家名称",
  "categoryId": "12-IndustryConsultant",
  "entry": "agents/main.md",
  "capabilities": { "network": false, "filesystem": false, "shell": false, "tools": false },
  "sha256": "PENDING",
  "files": []
}
```
> `sha256` 与 `files` 留空即可，`seal.dart` 会自动回填。

`categoryId` 取值（WorkBuddy 15 类）：
`01-ProductDesign` `02-Engineering` `03-GameSpatial` `04-DataAI` `05-MarketingGrowth`
`06-ContentCreative` `07-SalesCommerce` `08-FinanceInvestment` `09-OperationsHR`
`10-ProjectQuality` `11-SecurityCompliance` `12-IndustryConsultant` `13-TencentZone`
`14-WorldWise` `15-Education`

---

## 硬性规则（CI 强制，违反直接拒绝）

| 规则 | 说明 |
|---|---|
| **禁止可执行文件** | `.exe .dll .bat .cmd .ps1 .sh .py .js .jar .msi .scr .com .vbs .so .dylib .app` 一律拒绝 |
| **文件扩展名白名单** | 只允许 `.json .md .png .jpg .jpeg .txt` |
| **capabilities 必须全 false** | 专家包是**纯数据包，不执行任何代码** |
| **禁止硬编码密钥** | 包内不得出现任何真实 Token / API Key |
| **体积限制** | 单文件 ≤5MB，整包 ≤20MB |
| **路径安全** | 禁止绝对路径、盘符、`..`、符号链接（防 Zip Slip） |
| **头像规格** | 512×512 PNG/JPG，≤500KB |
| **哈希一致** | `manifest.sha256` 必须与按契约口径算出的值一致 |

---

## 校验口径（客户端与 CI 必须一致）

```
files[] 按 path 字典序排列
每个文件: sha256(fileBytes)
整包 sha256 = sha256( concat( path + "\0" + sha256hex + "\n" ) )
```

> 客户端实现见 `advisor_core/lib/domain/market.dart` 的 `PackageManifest.computePackageHash`；
> CI 实现见 `scripts/package_utils.dart` 的 `computePackageHash`。**两侧改动必须同步。**

---

## 许可

本仓库工具与 Schema 采用 MIT。
收录的专家包版权归各自作者所有；来自 `agency-agents-zh`（MIT）的专家保留其原始署名。
详见 [LICENSE](./LICENSE)。
