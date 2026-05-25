import SwiftUI

#if os(macOS)

struct ForceGraphSettingsView: View {
    @ObservedObject var viewModel: ForceGraphViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("外观") {
                    Toggle("箭头", isOn: $viewModel.showArrows)

                    sliderRow("节点大小", value: $viewModel.nodeSizeMultiplier, range: 0.3...3.0)
                    sliderRow("连线粗细", value: $viewModel.lineThickness, range: 0.1...3.0)
                }

                Divider()

                settingsSection("力度") {
                    sliderRow("图谱向心力", value: $viewModel.centerForce, range: 0.0...1.0)
                    sliderRow("节点间的排斥力", value: $viewModel.repulsionStrength, range: 0.0...1.0)
                    sliderRow("相连节点间的吸引力", value: $viewModel.attractionStrength, range: 0.0...1.0)
                }

                Divider()

                Button("重新布局") {
                    viewModel.restartSimulation()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 200)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func sliderRow(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }
}

#endif
