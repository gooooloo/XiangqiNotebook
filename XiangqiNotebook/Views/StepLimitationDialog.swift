import SwiftUI

struct StepLimitationDialog: View {
    @Binding var isPresented: Bool
    @State private var stepLimit: String = ""
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("设置步数限制")
                .font(.headline)
            
            #if os(iOS)
            TextField("最大步数（0或负数表示无限制）", text: $stepLimit)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
                .keyboardType(.numberPad)
            #else
            TextField("最大步数（0或负数表示无限制）", text: $stepLimit)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
            #endif
            
            HStack(spacing: 20) {
                Button("取消") {
                    stepLimit = ""
                    isPresented = false
                }
                
                Button("确定") {
                    if let number = Int(stepLimit.trimmingCharacters(in: .whitespacesAndNewlines)),
                       number > 0 {
                        viewModel.setGameStepLimitation(number)
                    } else {
                        viewModel.setGameStepLimitation(nil)
                    }
                    stepLimit = ""
                    isPresented = false
                }
            }
        }
        .padding()
        .frame(width: 300, height: 150)
        .onAppear {
            if let currentLimit = viewModel.gameStepLimitation {
                stepLimit = String(currentLimit)
            }
        }
    }
} 