//
//  vckiostestApp.swift
//  vckiostest
//
//  Created by Bernd Prünster on 22.07.26.
//

import Combine
import SwiftUI

@main
struct vckiostestApp: App {
    @StateObject private var model = WalletModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL(perform: model.handle)
        }
    }
}
