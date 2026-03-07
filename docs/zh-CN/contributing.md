# 贡献 Mocker

感谢您有意为 Mocker 做出贡献！本指南涵盖了入门所需的一切内容。

## 目录

- [行为准则](#行为准则)
- [开发环境配置](#开发环境配置)
- [项目结构](#项目结构)
- [进行修改](#进行修改)
- [编码规范](#编码规范)
- [测试](#测试)
- [提交 Pull Request](#提交-pull-request)
- [实现 Apple Containerization TODOs](#实现-apple-containerization-todos)

## 行为准则

请保持尊重和建设性的态度。我们遵循 [贡献者公约](https://www.contributor-covenant.org/)。

## 开发环境配置

### 前置条件

- macOS 26+（完整容器支持）或 macOS 14+（使用占位符进行开发）
- Swift 6.0+
- Xcode 16+

### 克隆并构建

```bash
git clone https://github.com/yourname/mocker.git
cd mocker

# 以调试模式构建
swift build

# 运行测试
swift test

# 直接运行 CLI
swift run mocker --help
```

### 推荐编辑器配置

**VS Code** + Swift 扩展：
```bash
code .
# 安装：Swift for VS Code（sswg.swift-lang）
```

**Xcode：**
```bash
open Package.swift
```

### 测试用清洁环境

```bash
# 删除所有 Mocker 状态（容器、镜像、网络、卷）
rm -rf ~/.mocker

# 重新构建并测试
swift build && swift run mocker system info
```

## 项目结构

完整说明请参阅 [architecture.md](architecture.md)。关键目录：

```
Sources/MockerKit/   # 核心库——大多数功能工作在这里
Sources/Mocker/      # CLI 命令——UI/格式化工作在这里
Sources/MockerApp/   # MenuBar GUI——SwiftUI 工作在这里
Tests/               # 单元测试和集成测试
docs/                # 文档
```

## 进行修改

### 1. Fork 并创建分支

```bash
git checkout -b feat/my-feature
# 或
git checkout -b fix/bug-description
```

### 2. 进行修改

遵循现有代码的模式：
- 新命令：在 `Sources/Mocker/Commands/` 中添加文件
- 新引擎方法：添加到 `MockerKit` 中相应的 actor
- 新数据模型：添加到 `Sources/MockerKit/Models/`

### 3. 编写测试

在 `Tests/MockerKitTests/` 中为新功能添加测试：

```swift
@Test("我的新功能正常工作")
func testMyFeature() throws {
    // ...
}
```

### 4. 验证

```bash
swift build
swift test
swift run mocker --help  # 冒烟测试
```

## 编码规范

### Swift 风格

- 使用 Swift 6 严格并发——所有 actor 必须正确使用 `await`
- 对任何有状态组件优先使用 `actor`
- 所有 I/O 操作使用 `async throws`
- 值类型优先使用 `struct` 而非 `class`
- 使用 `guard` 进行提前返回

### Docker 兼容性

实现或修改命令时，请对照 Docker 的输出进行验证：

```bash
# 检查 Docker 行为
docker run --help
docker inspect <容器>

# 与 Mocker 对比
swift run mocker run --help
swift run mocker inspect <容器>
```

关键兼容规则：
- 错误消息必须匹配：`Error response from daemon: ...`
- `inspect` 始终返回 JSON 数组 `[{...}]`
- `stop` 和 `rm` 回显用户输入的标识符（而非解析后的名称）
- 短 ID 恰好为 12 个字符

### 命名规范

- 容器/镜像/网络/卷名称：遵循 Docker 规范
- Swift 类型：类型用 PascalCase，属性/方法用 camelCase
- CLI 参数：使用 kebab-case 与 Docker 保持一致（`--no-stream`、`--project-name`）

### 提交消息

使用[约定式提交](https://www.conventionalcommits.org/zh-hans/)：

```
feat: 添加 mocker login 命令
fix: 修正 stop 命令中容器名称回显问题
docs: 更新 cli-reference 中的新参数说明
test: 添加 network connect/disconnect 测试
refactor: 将镜像验证提取为辅助函数
chore: 将 Yams 依赖更新至 5.2
```

标题行最多 72 个字符。

## 测试

### 运行测试

```bash
# 全部测试
swift test

# 指定测试套件
swift test --filter MockerKitTests
swift test --filter MockerTests

# 指定单个测试
swift test --filter "ContainerConfigTests/testParsePortMapping"
```

### 测试结构

```
Tests/
├── MockerKitTests/
│   ├── ContainerConfigTests.swift   # PortMapping、VolumeMount 解析
│   ├── ImageReferenceTests.swift    # ImageReference.parse()
│   └── ComposeFileTests.swift       # YAML 解析
└── MockerTests/
    └── CLITests.swift               # CLI 冒烟测试
```

### 编写测试

使用 `Testing` 框架（Swift 6）：

```swift
import Testing
@testable import MockerKit

@Suite("MyFeature 测试")
struct MyFeatureTests {
    @Test("解析有效输入")
    func testParseValid() throws {
        let result = try MyType.parse("valid-input")
        #expect(result.value == "expected")
    }

    @Test("解析无效输入应抛出异常")
    func testParseInvalid() {
        #expect(throws: MockerError.self) {
            try MyType.parse("")
        }
    }
}
```

### 集成测试

对于影响状态的命令，使用临时配置：

```swift
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
let config = MockerConfig(dataRoot: tempDir.path)
try config.ensureDirectories()
// ... 使用此配置进行测试
```

## 提交 Pull Request

1. **确保测试通过：** `swift test`
2. **确保构建成功：** `swift build`
3. **自我审查 diff** — 删除调试输出，检查拼写错误
4. **撰写清晰的 PR 说明：**
   - 解决了什么问题？
   - 如何测试的？
   - 是否有破坏性变更？

### PR 标题格式

遵循约定式提交格式：
- `feat: 添加 mocker login 命令`
- `fix: 防止重复拉取时产生重复镜像`
- `docs: 添加 Compose 指南`

## 实现 Apple Containerization TODOs

影响最大的贡献是将占位符实现替换为真实的 Apple Containerization 框架调用。查找 `// TODO:` 注释：

```bash
grep -r "TODO:" Sources/MockerKit/
```

### 关键集成点

**镜像拉取**（`ImageManager.swift`）：
```swift
// TODO: 使用 Containerization 框架实际拉取镜像
// 替换为 Apple Containerization 的镜像拉取 API
```

**容器启动**（`ContainerEngine.swift`）：
```swift
// TODO: 使用 Containerization 框架启动容器
// 替换为 Container() 初始化 + start()
```

**容器日志**（`ContainerEngine.swift`）：
```swift
// TODO: 从容器进程流式传输真实日志
```

### TODO 实现指南

1. 保持现有方法签名不变——调用方不应需要修改
2. 返回的占位符 `ContainerInfo` 应与框架真实数据格式匹配
3. 为框架特定的错误添加处理，映射到 `MockerError`
4. 更新相关测试

## 有问题？

使用 `question` 标签开一个 Issue，或发起一个 GitHub Discussion。
