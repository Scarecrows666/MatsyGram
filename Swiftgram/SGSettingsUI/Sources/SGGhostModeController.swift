// MARK: Ghost mode
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings

private enum SGGhostOption: Int32 {
    case readReceipts
    case onlineStatus
    case storyViews
    case scheduledSend
}

private final class SGGhostModeArguments {
    let toggleMaster: (Bool) -> Void
    let toggleOption: (SGGhostOption, Bool) -> Void

    init(toggleMaster: @escaping (Bool) -> Void, toggleOption: @escaping (SGGhostOption, Bool) -> Void) {
        self.toggleMaster = toggleMaster
        self.toggleOption = toggleOption
    }
}

private enum SGGhostModeSection: Int32 {
    case master
    case options
}

private enum SGGhostModeEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case master
        case masterNotice
        case optionsHeader
        case option(Int32)
        case optionsNotice
    }

    case master(String, Bool)
    case masterNotice(String)
    case optionsHeader(String)
    case option(SGGhostOption, String, Bool, Bool)
    case optionsNotice(String)

    var section: ItemListSectionId {
        switch self {
        case .master, .masterNotice:
            return SGGhostModeSection.master.rawValue
        case .optionsHeader, .option, .optionsNotice:
            return SGGhostModeSection.options.rawValue
        }
    }

    var stableId: StableId {
        switch self {
        case .master:
            return .master
        case .masterNotice:
            return .masterNotice
        case .optionsHeader:
            return .optionsHeader
        case let .option(option, _, _, _):
            return .option(option.rawValue)
        case .optionsNotice:
            return .optionsNotice
        }
    }

    var sortIndex: Int32 {
        switch self {
        case .master:
            return 0
        case .masterNotice:
            return 1
        case .optionsHeader:
            return 2
        case let .option(option, _, _, _):
            return 10 + option.rawValue
        case .optionsNotice:
            return 100
        }
    }

    static func ==(lhs: SGGhostModeEntry, rhs: SGGhostModeEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.master(lhsTitle, lhsValue), .master(rhsTitle, rhsValue)):
            return lhsTitle == rhsTitle && lhsValue == rhsValue
        case let (.masterNotice(lhsText), .masterNotice(rhsText)):
            return lhsText == rhsText
        case let (.optionsHeader(lhsText), .optionsHeader(rhsText)):
            return lhsText == rhsText
        case let (.option(lhsOption, lhsTitle, lhsValue, lhsEnabled), .option(rhsOption, rhsTitle, rhsValue, rhsEnabled)):
            return lhsOption == rhsOption && lhsTitle == rhsTitle && lhsValue == rhsValue && lhsEnabled == rhsEnabled
        case let (.optionsNotice(lhsText), .optionsNotice(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: SGGhostModeEntry, rhs: SGGhostModeEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGGhostModeArguments
        switch self {
        case let .master(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleMaster(value)
            })
        case let .masterNotice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .optionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .option(option, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleOption(option, value)
            })
        case let .optionsNotice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func sgGhostModeEntries(presentationData: PresentationData) -> [SGGhostModeEntry] {
    let isRussian = presentationData.strings.baseLanguageCode == "ru"
    func text(_ ru: String, _ en: String) -> String {
        return isRussian ? ru : en
    }

    let settings = SGSimpleSettings.shared
    let isEnabled = settings.ghostModeEnabled

    var entries: [SGGhostModeEntry] = []
    entries.append(.master(text("Режим призрака", "Ghost Mode"), isEnabled))
    entries.append(.masterNotice(text(
        "Скрывает ваши действия от других людей. Отдельные функции настраиваются ниже.",
        "Hides your activity from other people. Choose the individual features below."
    )))

    entries.append(.optionsHeader(text("ФУНКЦИИ", "FEATURES")))
    entries.append(.option(.readReceipts, text("Не отмечать прочитанным", "Don't mark as read"), settings.ghostNoReadReceipts, isEnabled))
    entries.append(.option(.onlineStatus, text("Скрывать статус «в сети»", "Hide online status"), settings.ghostNoOnlineStatus, isEnabled))
    entries.append(.option(.storyViews, text("Анонимный просмотр историй", "View stories anonymously"), settings.ghostNoStoryViews, isEnabled))
    entries.append(.option(.scheduledSend, text("Отправка с задержкой 12 с", "Delayed sending (12 s)"), settings.ghostScheduledSend, isEnabled))
    entries.append(.optionsNotice(text(
        "Сообщения отправляются как отложенные и появляются в чате примерно через 12 секунд. В секретных чатах, чатах с ботами и в «Избранном» отправка не меняется. Реакции не требуют отдельной настройки: пока статус «в сети» скрыт, они отправляются без него.",
        "Messages are sent as scheduled ones and appear in the chat after about 12 seconds. Secret chats, bot chats and Saved Messages are not affected. Reactions need no separate option: while the online status is hidden, they are sent without it."
    )))
    return entries
}

public func sgGhostModeController(context: AccountContext) -> ViewController {
    let refreshPromise = ValuePromise(true, ignoreRepeated: false)

    let arguments = SGGhostModeArguments(toggleMaster: { value in
        SGSimpleSettings.shared.ghostModeEnabled = value
        refreshPromise.set(true)
    }, toggleOption: { option, value in
        switch option {
        case .readReceipts:
            SGSimpleSettings.shared.ghostNoReadReceipts = value
        case .onlineStatus:
            SGSimpleSettings.shared.ghostNoOnlineStatus = value
        case .storyViews:
            SGSimpleSettings.shared.ghostNoStoryViews = value
        case .scheduledSend:
            SGSimpleSettings.shared.ghostScheduledSend = value
        }
        refreshPromise.set(true)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refreshPromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = presentationData.strings.baseLanguageCode == "ru" ? "Режим призрака" : "Ghost Mode"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgGhostModeEntries(presentationData: presentationData), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
