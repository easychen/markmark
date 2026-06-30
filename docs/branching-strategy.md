# 分支策略

> 本文档记录 MarkMark 的分支策略与发布方案。

## 当前状态

- `main` 分支为唯一开发线，版本号从 v2.0.0 起
- 渲染引擎：WKWebView + cmark-gfm
- 最低部署：macOS 14.0
- Bundle ID：`com.ft07.markmark`
- 唯一外部依赖：swift-markdown

## 分支模型

### 主线开发

| 分支 | 用途 | 版本号 |
|------|------|--------|
| `main` | 唯一开发分支，所有功能开发和 bug 修复 | v2.x.x |

### 归档分支

| 分支 | 状态 | 说明 |
|------|------|------|
| `release/1.x` | 归档，不再维护 | Textual 渲染引擎时代的维护线，已停止开发 |

## 版本发布

- 版本号从 v2.0.0 开始，遵循语义化版本
- Bundle ID：`com.ft07.markmark`
- DMG/ZIP 分发，资产名：`MarkMark.dmg` / `MarkMark.zip`
- GitHub Release tag：`v2.x.x`
- CI 通过 `v*` tag 触发 `release.yml`

## CI/CD

- `release.yml` 由 `v*` tag 触发
- 默认创建 draft release，等待本地构建上传（`release-local.sh`）
- 可选 CI 构建（需手动启用 `use_ci_build`，已知有文字不可见问题）

## 核心原则

> **单线前进。不做多产品线并行。**
