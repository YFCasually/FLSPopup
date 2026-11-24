# FLSPopup

面向 iOS / iPadOS 17+ 的 SwiftUI 弹窗库。把同一份内容展示在指定页面，或展示在发起请求的 Scene 窗口中。适用于编辑页提示、Sheet 上方的通知，以及需要排队、挂起和恢复的表单。支持 SPM、CocoaPods，无第三方运行时依赖。

## 安装

**Swift Package Manager** · 在 Xcode 的 File → Add Package Dependencies 中添加仓库，选择从 1.0.0 起的兼容版本，将产品 FLSPopup 加入目标。也可以写入 Package.swift：

```swift
.package(url: "https://github.com/YFCasually/FLSPopup.git", from: "1.0.0")
// target dependencies:
.product(name: "FLSPopup", package: "FLSPopup")
```

**CocoaPods** · 在应用目标的 Podfile 加入以下内容，运行 `pod install`，打开生成的 xcworkspace。此安装方式直接使用 Git 标签。

```ruby
platform :ios, '17.0'
target 'YourApp' do
  use_frameworks!
  pod 'FLSPopup', :git => 'https://github.com/YFCasually/FLSPopup.git', :tag => '1.0.0'
end
```

## 五分钟接入

每个 WindowGroup 的根视图注册一次 Scene 宿主。为需要局部弹窗的页面指定稳定的 ID。同一个 Scene 里的页面 ID 应唯一。

```swift
import SwiftUI
import FLSPopup

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            EditorPage()
                .popupHost(id: "editor")
                .popupSceneHost()
        }
    }
}

struct EditorPage: View {
    @Environment(\.popupSceneID) private var sceneID
    @Environment(\.popupPresenter) private var presenter
    @State private var showingHelp = false

    var body: some View {
        if let sceneID {
            VStack {
                Button("编辑帮助") { showingHelp = true }
                Button("保存草稿") {
                    _ = presenter.present(
                        target: .window(scene: sceneID),
                        options: PopupOptions(style: .toast, identifier: "draft-saved")
                    ) { Label("草稿已保存", systemImage: "checkmark.circle") }
                }
            }
            .flsPopup(isPresented: $showingHelp, target: .page(scene: sceneID, id: "editor")) {
                HelpCard()
            }
        } else {
            ProgressView()
        }
    }
}

struct HelpCard: View {
    @Environment(\.dismissPopup) private var dismiss
    var body: some View {
        VStack {
            Text("编辑帮助").font(.headline)
            Text("离开页面前，可以先保存草稿。")
            Button("继续编辑") { dismiss() }
        }
    }
}
```

业务数据也可以通过 `.flsPopup(item:target:options:content:)` 绑定。使用稳定的 Identifiable.ID。关闭后绑定回写 nil。使用命令式接口时检查返回结果；accepted(handle) 可用于关闭当前实例，rejected(reason) 区分重复、独占阻挡和目标失效。

## 选择宿主和策略

| 目标 | 使用场景 |
| --- | --- |
| `.page(scene:id:)` | 随页面存在，沿用页面环境，受挂载点布局和系统 Sheet 遮挡。导航缓存中的页面可用 `popupHost(id:isActive:)` 显式结束宿主。 |
| `.window(scene:)` | 跨页面、在同一 Scene 的应用 Sheet 上方展示。用实际发起页面取得的 popupSceneID；新视图树需要的自定义模型请显式传入。需要输入时设置 requiresKeyboard。 |

| 模式 | 同组行为 |
| --- | --- |
| queue | 忙时排队，先按优先级，再按入队顺序。 |
| interrupt | 保留当前内容并立即叠加。窗口仍在页面之上。 |
| suspend | 挂起当前活跃项，关闭后恢复原内容。 |
| replaceInheritSuspend | 替换活跃项并继承其挂起链。 |
| replaceClearSuspend | 替换活跃项并清除挂起链，保留队列。 |
| replaceAll | 清空同组后展示，后续仍可提交。 |
| groupUnique | 清空同组并锁定该组直到结束。 |
| globalUnique | 清空应用内所有受管弹窗，仅在指定宿主展示并锁定全局。 |

默认按 Scene 分组和去重。需要跨 Scene 协调时显式使用 `.application`。group 控制调度，identifier 用于业务去重，priority 只影响等待队列。样式可选 toast、card、panel；支持修改对齐、边距、转场、背景点击策略与超时。对需要用户决策的弹窗提供明确按钮。

## 生命周期与查询

从主线程调用 presenter。对需要处理结果的请求，保留返回的 handle。`onFirstDisplay` 在首次进场结束时触发一次。`onEnd` 会收到结束原因，挂起和恢复不会结束请求。

```swift
var options = PopupOptions(style: .panel, mode: .suspend, group: "editor")
options.requiresKeyboard = true
options.background = .dismiss

let result = presenter.present(target: .window(scene: sceneID), options: options,
                               onEnd: { reason in print(reason) }) {
    DraftForm() // 业务自定义的 SwiftUI 表单
}
if case let .accepted(handle) = result {
    // 需要取消这个请求时调用 presenter.dismiss(handle)。
    print(handle.id)
}
```

通过 `records(scene:group:scope:identifier:phase:)` 查看等待、活跃和挂起内容，使用 `activeIdentifiers` 或 `activeCount` 查询展示中的业务键及数量。用 `dismiss(group:scene:)` 清理当前 Scene 的一组弹窗，使用 `dismiss(scene:)` 清理整个 Scene。`dismissAll()` 涵盖应用内所有已注册的宿主。

窗口中的颜色、字号、布局方向和地区设置继承 Scene 根的环境。对当前页面注入的业务模型，在弹窗内容上显式调用 `.environmentObject(model)` 或通过构造参数传入。应用和系统共同决定状态栏及旋转的最终表现。可在弹窗显示且布局稳定后，通过 `presenter.appearanceLimitations(for: handle)` 查询当前受限的外观请求。

## 运行示例与测试

打开 [Demo 工程](Demo/FLSPopupDemo.xcodeproj)，选择 FLSPopupDemo 和 iPhone 或 iPad 模拟器，按 ⌘R。Demo 直接引用仓库根目录的 Swift 包，因此修改框架可以立即验证。UI 测试可从 Demo scheme 执行；调度单元测试可从包的 FLSPopup scheme 执行。具体验证项目见 [验证记录](VALIDATION.md)。

## 许可证

[MIT](LICENSE)
