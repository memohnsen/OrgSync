//
//  AgendaView.swift
//  OrgSync
//
//  Placeholder for the Agenda tab. Phase 5 replaces this with an aggregated
//  view of TODO headlines (Today / Upcoming / All) across every org file.
//

import SwiftUI

struct AgendaView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Agenda", systemImage: "calendar")
            } description: {
                Text("Scheduled and deadline TODOs from your notes will appear here.")
            }
            .navigationTitle("Agenda")
        }
    }
}

#Preview {
    AgendaView()
}
