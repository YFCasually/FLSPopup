# 验证方法

## 复现命令

在仓库根目录执行以下命令，将目标名称替换为本机可用的 iOS 模拟器。

```sh
xcodebuild test -scheme FLSPopup -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project Demo/FLSPopupDemo.xcodeproj -scheme FLSPopupDemo -destination 'platform=iOS Simulator,name=iPhone 17'
pod lib lint FLSPopup.podspec --platforms=ios
```

## 验收场景

| 编号 | 操作 | 观察依据 |
| --- | --- | --- |
| T01 | 依次提交低、高、高优先级的同组请求 | 当前内容结束后按高、高、低显示，两个高优先级按提交顺序 |
| T02 | 两个内容 interrupt 共存，再 suspend 并关闭第三个 | 二者恢复原叠放顺序，等待项仍在队列 |
| T03 | 挂起已输入的草稿，以两种 replace 接管挂起者 | inherit 恢复原草稿，clear 清除整条链；等待项均保留 |
| T04 | 比较 replaceAll 与 groupUnique | 都清理同组旧项；独占期间重复提交收到组锁拒绝 |
| T05 | iPad 打开第二个窗口，在其中一个发起 globalUnique | 所有受管请求清理；独占只在指定宿主出现；两个窗口的新请求均受锁约束 |
| T06 | 在页面和窗口重复使用相同业务键，并切换组或 Scene | 同一去重范围只能有一个实例，退场期间仍去重 |
| T07 | 在草稿中输入、滚动，用窗口确认卡挂起并恢复；另一次先离开页面 | 草稿和位置得以恢复；已结束的页面不复活 |
| T08 | Sheet 打开时向其内部页面、下层页面、Window 分别提交 | 各层级遵循实际宿主位置；Scene 断开只清理自己的记录 |
| T09 | 在带计数器的页面上测试四种背景策略 | 内容与下层点击均最多执行一次；阻挡、关闭、穿透各自符合设置 |
| T10 | Sheet 输入框聚焦时显示 Window Toast，继续输入；再切换到输入型 Window 卡片 | 焦点、原文字和键盘状态正确，编辑操作可达 |
| T11 | 开启 VoiceOver、最大辅助字号、减少动态效果；旋转及切换分屏/浅深色 | 文字可读、按钮可达，模态有退出入口且焦点范围正确 |
| T12 | 双击关闭、动画中替换、结束回调再提交、取消非顶层与批量清理 | 终结回调只发一次，状态、锁和查询一致 |
| T13 | 通知计时中挂起、进入后台再恢复，快速切换 item | 计时按剩余时长继续；旧请求完成不会清掉新绑定 |
| T14 | 在不同宿主请求状态栏与旋转偏好，多次打开输入卡后用 Instruments 检查 | 可用偏好生效，受限情况按宿主有效配置；窗口、内容和计时器能释放 |

以上表格为复验步骤。自动化用例代码在 Tests 和 Demo/UITests 中；读屏听感、硬件键盘、物理设备窗口切换与 Instruments 需要对应环境核验。
