//
//  HelloStage.swift
//  Sumi
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct HelloStage: View {

    var body: some View {
        VStack(spacing: 24){
            Text("Welcome to Sumi")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Image("sumi-logo-1024")
                .resizable()
                .scaledToFit()
                .frame(width: 128 ,height: 128)
            Text("A focused open-source browser for daily work.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
