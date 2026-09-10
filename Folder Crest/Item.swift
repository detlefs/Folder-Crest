//
//  Item.swift
//  Folder Crest
//
//  Created by Detlef Schneider on 10.09.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
