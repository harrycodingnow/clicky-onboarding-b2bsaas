//
//  OnboardingFlow.swift
//  leanring-buddy
//
//  Data model + fetch service for employee onboarding flows. A flow is the
//  ordered list of steps a company's IT team authored in the /admin page.
//  The app fetches a flow by id from the Cloudflare Worker (GET /flow/:id)
//  and walks the new employee through it one step at a time.
//

import Foundation

/// A single instruction in an onboarding flow (e.g. "Install the VPN client").
struct OnboardingStep: Codable, Identifiable, Equatable {
  let id: Int
  let instruction: String
}

/// An ordered onboarding flow authored by a company's IT team.
struct OnboardingFlow: Codable, Equatable {
  let id: String
  let title: String
  let steps: [OnboardingStep]
}

enum OnboardingFlowServiceError: LocalizedError {
  case flowNotFound
  case invalidResponse
  case server(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .flowNotFound:
      return "We couldn't find an onboarding flow with that ID."
    case .invalidResponse:
      return "The onboarding service returned an unexpected response."
    case .server(let status, let message):
      return "Onboarding service error (\(status)): \(message)"
    }
  }
}

/// Fetches onboarding flows from the Worker. Read-only on the client — flows
/// are authored through the /admin web page, not the app.
struct OnboardingFlowService {
  private let flowEndpointBaseURL: String
  private let session: URLSession

  /// - Parameter flowEndpointBaseURL: Worker base URL, e.g.
  ///   "https://your-worker.workers.dev". The `/flow/:id` path is appended.
  init(flowEndpointBaseURL: String, session: URLSession = .shared) {
    self.flowEndpointBaseURL = flowEndpointBaseURL
    self.session = session
  }

  func fetchFlow(id flowID: String) async throws -> OnboardingFlow {
    guard let requestURL = URL(string: "\(flowEndpointBaseURL)/flow/\(flowID)") else {
      throw OnboardingFlowServiceError.invalidResponse
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw OnboardingFlowServiceError.invalidResponse
    }

    if httpResponse.statusCode == 404 {
      throw OnboardingFlowServiceError.flowNotFound
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw OnboardingFlowServiceError.server(status: httpResponse.statusCode, message: message)
    }

    do {
      return try JSONDecoder().decode(OnboardingFlow.self, from: data)
    } catch {
      throw OnboardingFlowServiceError.invalidResponse
    }
  }
}
