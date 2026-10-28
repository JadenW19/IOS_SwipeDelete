//
//  OnThisDayView.swift
//  SwipeWipeApp
//
//  Tab showing today's memories from previous years with a completion badge.
//

import SwiftUI
import SwipeWipeCore

struct OnThisDayView: View {
    let assets: [PhotoAssetModel]
    let isCompleted: Bool
    let onStart: () -> Void

    private var yearCounts: [(year: Int, count: Int)] {
        let cal = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: assets) { cal.component(.year, from: $0.creationDate) }
        return grouped.map { (year: $0.key, count: $0.value.count) }.sorted { $0.year > $1.year }
    }

    private var todayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On This Day")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(todayTitle + " in previous years")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if assets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No photos from this day in earlier years.")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(assets.count) photos to look back on today")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Spacer()
                            if isCompleted {
                                Label("Completed", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }

                        ForEach(yearCounts, id: \.year) { entry in
                            HStack {
                                Text(String(entry.year))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text("\(entry.count)")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button(action: onStart) {
                            Text(isCompleted ? "Review Again" : "Start Looking Back")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isCompleted ? Color.green : Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

