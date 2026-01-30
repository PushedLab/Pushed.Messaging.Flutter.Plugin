//
//  NotificationService.swift
//  NotificationService
//
//  Created by Sergei Golov on 15.01.26.
//

import UserNotifications

@objc(NotificationService)
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    // TEMP HOTFIX (remove later):
    // Some payload variants arrive with non-empty `data`, but empty `aps.alert`,
    // while actual text is present in `userInfo["pushedNotification"]` (Title/Body).
    // iOS shows empty title/body unless we copy them into the mutable content here.
    private func applyTempTitleBodyHotfix(_ content: UNMutableNotificationContent, userInfo: [AnyHashable: Any]) {
        guard (content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               content.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        else { return }

        func stringOrNil(_ any: Any?) -> String? {
            guard let s = any as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        // pushedNotification keys sometimes come in different casing
        if let pn = userInfo["pushedNotification"] as? [AnyHashable: Any] {
            let title = stringOrNil(pn["Title"] ?? pn["title"])
            let body = stringOrNil(pn["Body"] ?? pn["body"])
            if content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let title { content.title = title }
            if content.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let body { content.body = body }
            return
        }

        if let pn = userInfo["pushedNotification"] as? [String: Any] {
            let title = stringOrNil(pn["Title"] ?? pn["title"])
            let body = stringOrNil(pn["Body"] ?? pn["body"])
            if content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let title { content.title = title }
            if content.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let body { content.body = body }
        }
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        // Confirm APNs delivery (async). Do not block notification rendering.
        if let messageId = PushedCoreClient.extractMessageId(from: request.content.userInfo) {
            PushedCoreClient.confirmApnsDelivery(messageId)
            // SHOW interaction (async). Extension is the most reliable place for "delivered/shown".
            PushedCoreClient.sendInteraction(1, messageId: messageId)
        }

        if let bestAttemptContent = bestAttemptContent {
            applyTempTitleBodyHotfix(bestAttemptContent, userInfo: request.content.userInfo)
            contentHandler(bestAttemptContent)
        } else {
            contentHandler(request.content)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
