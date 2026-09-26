// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
//
//  ContentView.swift
//  LaunchDeck
//
//  Created by Reom Nagasaka on 2026/09/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        LaunchDeckEditor()
    }
}

#Preview {
    ContentView().environment(AppCoordinator())
}
