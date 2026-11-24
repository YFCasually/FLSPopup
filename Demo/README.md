# FLSPopup workbench

Open `FLSPopupDemo.xcodeproj`, choose the shared **FLSPopupDemo** scheme, and run on an iOS 17 or newer iPhone or iPad. Xcode resolves the FLSPopup product from the parent folder. The checked-in project opens directly. To regenerate it after changing the target definitions, run `xcodegen generate` from this directory.

Run the UI suite from **Product → Test**, or from this directory with a simulator UUID from `xcrun simctl list devices available`.

```sh
xcodebuild test -project FLSPopupDemo.xcodeproj -scheme FLSPopupDemo \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO
```

## Presenting requests

The scene root installs `.popupSceneHost()`. A child reads its own scene ID from the environment. The workbench and sheet install separate page hosts. Both targets can display the same card.

```swift
@Environment(\.popupSceneID) var sceneID

// Called on the main actor from a child of the registered workbench.
if let sceneID {
    let target: PopupTarget = useWindow
        ? .window(scene: sceneID)
        : .page(scene: sceneID, id: "workbench")
    PopupCenter.shared.present(target: target) { Text("Ready to review") }
}
```

## Exercises

| Spec | Steps and expected observation |
| --- | --- |
| T01 | Select Page or Window, choose a mode, and present. On a queue card, use **Submit another request** to queue an ordinary card and two high-priority cards. Finish each. The two urgent cards appear first in submission order. |
| T02 | Present a card, interrupt it, then suspend both using the card menu. Finish the suspending card, then the interrupter. The original card should be last. |
| T03, T07 | Open **Edit a draft** on Page. Enter text, scroll the revisions, then choose **Review in window**. Queue a card and replace the review using either replacement mode. Finishing the inheriting replacement restores the text and scroll position before the queued card. The clearing replacement shows the queued card directly. Repeat from **Navigate to editor** and use the navigation back control to remove the page host. |
| T04 | From a card, queue another, then choose **replaceAll** or **groupUnique**. Try queuing again. Only the latter reports a group lock. Use **Interrupt another group** to submit outside the locked group. |
| T05 | In iPad windowing mode use **Open another scene**. Present ordinary cards in both windows. Select **globalUnique** from a card menu, then try presenting in the other scene. Close the exclusive scene and try again. |
| T06 | Turn on **Use the same business key**, present a card, then choose **Repeat business key on other host**. The card displays the duplicate rejection. Finish it and submit again. |
| T08 | Open the system sheet. Try **Card on sheet**, then finish it. Choose **Card on underlying page** and close the sheet to reveal it. In **Interaction lab**, request a missing page and inspect the rejection. |
| T09 | In **Interaction lab**, select each host and background behavior. Show the touch sample. Tap the content counter once, then tap the background counter once. Check which counter moved and whether the sample closed. Close any remaining sample before changing modes. |
| T10 | Focus the sheet title and type. Save with the keyboard showing. A window notification appears over the sheet and typing can continue. Open **Window input panel**, type, close it and return to the sheet field. |
| T11, T14 | Repeat the form and sheet flows with VoiceOver, Larger Text, Reduce Motion, landscape and split view. In **Interaction lab**, enable the appearance override, open and close the sample, and compare the sample and host. Use Instruments on a device for allocations after repeated window input. |
| T12 | In the workbench, inspect recent events after interrupting, replacing and dismissing cards. Each accepted request should have one terminal event. The request list provides handle-based cancellation for entries reachable from the workbench. |
| T13 | Save from the sheet, background the app promptly, wait longer than three seconds, and foreground it. The toast should resume its remaining time. In **Interaction lab** present the Bool binding twice, closing each time, then present the item binding and switch its identity before closing. |

The event log and request numbers belong to each scene. The scheduler supplies the phases and end reasons. Simulator UI tests cover the flows in `UITests/PopupDemoTests.swift`. Device-only appearance, VoiceOver traversal and resource lifetime require manual observation.
