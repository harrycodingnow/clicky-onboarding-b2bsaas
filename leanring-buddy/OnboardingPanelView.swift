//
//  OnboardingPanelView.swift
//  leanring-buddy
//
//  The employee-facing onboarding checklist shown inside the menu bar panel.
//  Walks the new hire through the steps their IT team authored: shows the
//  current step, lets them ask Clicky to perform the step ("Show me"),
//  explain it in text ("Tell me"), advance ("Done"), or start over.
//

import SwiftUI

struct OnboardingPanelView: View {
  @ObservedObject var companionManager: CompanionManager

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let flow = companionManager.onboardingFlow {
        header(for: flow)

        if companionManager.isOnboardingFlowComplete {
          completionCard
        } else if let step = companionManager.currentOnboardingStep {
          progressBar(for: flow)
          stepCard(step: step, flow: flow)
          guidanceSection
          actionButtons
        }
      } else if let loadError = companionManager.onboardingFlowLoadError {
        errorCard(message: loadError)
      } else {
        loadingCard
      }
    }
  }

  // MARK: - Header

  private func header(for flow: OnboardingFlow) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(flow.title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(DS.Colors.textPrimary)
      if !companionManager.isOnboardingFlowComplete {
        Text("Step \(companionManager.onboardingStepIndex + 1) of \(flow.steps.count)")
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(DS.Colors.textTertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Progress

  private func progressBar(for flow: OnboardingFlow) -> some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.08))
          .frame(height: 4)
        Capsule()
          .fill(DS.Colors.accent)
          .frame(width: progressFraction(for: flow) * geometry.size.width, height: 4)
      }
    }
    .frame(height: 4)
  }

  private func progressFraction(for flow: OnboardingFlow) -> CGFloat {
    guard flow.steps.count > 0 else { return 0 }
    return CGFloat(companionManager.onboardingStepIndex) / CGFloat(flow.steps.count)
  }

  // MARK: - Current step

  private func stepCard(step: OnboardingStep, flow: OnboardingFlow) -> some View {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        Circle()
          .fill(DS.Colors.accent)
          .frame(width: 24, height: 24)
        Text("\(companionManager.onboardingStepIndex + 1)")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(DS.Colors.textOnAccent)
      }

      Text(step.instruction)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(DS.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay(
      RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    )
  }

  // MARK: - Guidance

  @ViewBuilder
  private var guidanceSection: some View {
    if companionManager.isRequestingOnboardingGuidance {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Looking at your screen…")
          .font(.system(size: 12))
          .foregroundColor(DS.Colors.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else if let guidance = companionManager.onboardingGuidanceText, !guidance.isEmpty {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(DS.Colors.accentText)
          .padding(.top, 1)
        Text(guidance)
          .font(.system(size: 12))
          .foregroundColor(DS.Colors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
          .fill(DS.Colors.accentSubtle)
      )
    }
  }

  // MARK: - Actions

  private var actionButtons: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        secondaryButton(
          title: "Show me",
          systemImage: "cursorarrow.click.2"
        ) {
          companionManager.requestGuidanceForCurrentStep(reason: .showMe)
        }

        secondaryButton(
          title: "Tell me",
          systemImage: "text.bubble.fill"
        ) {
          companionManager.requestGuidanceForCurrentStep(reason: .tellMe)
        }
      }
      .disabled(companionManager.isRequestingOnboardingGuidance)
      .opacity(companionManager.isRequestingOnboardingGuidance ? 0.5 : 1)

      primaryButton(
        title: isLastStep ? "Finish" : "Done — next step",
        systemImage: "checkmark"
      ) {
        companionManager.advanceOnboardingStep()
      }
    }
  }

  private var isLastStep: Bool {
    guard let flow = companionManager.onboardingFlow else { return false }
    return companionManager.onboardingStepIndex == flow.steps.count - 1
  }

  // MARK: - Completion

  private var completionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(DS.Colors.success)
        Text("You're all set!")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(DS.Colors.textPrimary)
      }

      Text("You finished every step. Need to run through it again?")
        .font(.system(size: 12))
        .foregroundColor(DS.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      secondaryButton(title: "Start again", systemImage: "arrow.counterclockwise") {
        companionManager.restartOnboardingFlow()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
  }

  // MARK: - Loading / error

  private var loadingCard: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Loading your onboarding…")
        .font(.system(size: 12))
        .foregroundColor(DS.Colors.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func errorCard(message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Couldn't load onboarding")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(DS.Colors.textPrimary)
      Text(message)
        .font(.system(size: 11))
        .foregroundColor(DS.Colors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
      secondaryButton(title: "Try again", systemImage: "arrow.clockwise") {
        companionManager.loadOnboardingFlow()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
  }

  // MARK: - Button styles

  private func primaryButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .semibold))
        Text(title)
          .font(.system(size: 14, weight: .semibold))
      }
      .foregroundColor(DS.Colors.textOnAccent)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
          .fill(DS.Colors.accent)
      )
    }
    .buttonStyle(.plain)
    .pointerCursor()
  }

  private func secondaryButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 11, weight: .medium))
        Text(title)
          .font(.system(size: 13, weight: .medium))
      }
      .foregroundColor(DS.Colors.textSecondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
          .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
      )
    }
    .buttonStyle(.plain)
    .pointerCursor()
  }
}
